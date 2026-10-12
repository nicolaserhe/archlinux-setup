#!/usr/bin/env bash
# =============================================================================
# scripts/core/memory.sh -- 内存压力下的兜底：swapfile + zswap 校验 + SSD TRIM
#
# 为什么是磁盘 swapfile 而不是 zram（Arch 口径）：
#   zram 是"内存里开一块块设备当 swap"，与 zswap 职责重叠 —— 用它就必须显式
#   关掉 zswap，换来的只是"换出更快"。它真正的适用面是 8-16 GiB 那一档；本机
#   30 GiB，而且 zswap 已经开着，建一个磁盘 swapfile 就让那层压缩立刻有了用武
#   之地：零新包、零配置、不与休眠互斥。
#
# 为什么大小是 16 GiB：
#   够吸收一次失控的尖峰（docker build / 本地模型 / 多开浏览器），但不假装支持
#   休眠 —— 休眠要 swap ≥ 内存（本机 30 GiB）**外加** resume hook 和 ext4
#   swapfile 的 resume_offset，是独立一项（本机 HOOKS 里没有 resume）。
#
# 为什么不动 vm.swappiness：
#   Arch wiki 给的两个值都不适用 —— Swap 页的 10 是针对纯磁盘 swap（避免 I/O），
#   Zram 页的 180 是针对内存 swap（换出近乎免费）。本机是第三种组合（磁盘 swap
#   + zswap），没有现成答案，而 30 GiB 上这个旋钮平时根本不动。真出现压力时再
#   按实测调，方向是升不是降。
#
# 为什么不开 systemd-oomd：
#   Arch wiki 连配方都不给（只在 Improving performance 里和 earlyoom 并列提了
#   个名字）；默认开它的 Fedora 和 Ubuntu 都被杀错进程咬过，Debian/openSUSE/
#   Mint 都不开。它是"某个进程失控把桌面拖死"的保险，而加了 swapfile 之后这个
#   场景已经大幅缩小 —— 真遇到了再上，届时照 Fedora 收敛后的值（80%、20s、
#   不用 swap 策略）。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

readonly SWAPFILE=/swapfile
readonly SWAP_SIZE=16G

# -- swapfile -----------------------------------------------------------------
header "Swap file ($SWAP_SIZE)"

# btrfs 上的 swapfile 需要 nodatacow + 单设备 + 关压缩，配方完全不同。直接建会
# 得到一个 swapon 失败的半成品，而 set -e 会把它变成"整个 user-phase 中断" ——
# 所以这里只跳过 swap 这部分，不阻断安装。（本机根是 ext4。）
_root_fs="$(findmnt -no FSTYPE --target /)"
if [[ "$_root_fs" == btrfs ]]; then
    warn "root is btrfs -- swapfile needs nodatacow/single-device handling, skipping"
else
    # 只有真把 swap 起起来（或确认它本来就在跑）才写 fstab：写进去的条目在启动时
    # 由 swapon -a 消费，指向一块 mkswap 失败、没有 swap 头部的文件只会换来每次
    # 开机一条报错。
    _swap_ok=1

    if swapon --show=NAME --noheadings 2>/dev/null | grep -qxF "$SWAPFILE"; then
        warn "$SWAPFILE already active, skipping"
    else
        # 已存在就复用：删掉重建等于把一块可能正在被引用的空间换掉，
        # 而 mkswap 会重刷头部，效果一样
        [[ -f "$SWAPFILE" ]] || _as_root fallocate -l "$SWAP_SIZE" "$SWAPFILE"
        # 必须 0600：可读的 swapfile 能把别人的内存内容捞出来
        _as_root chmod 600 "$SWAPFILE"

        # 失败降级成 warn，不带走后面所有模块：这一步在 user-phase 里排第 8，
        # 后面还有 shell / dms / matugen / fcitx 等一大串，而 swap 起不来只影响
        # 极端内存压力下的表现，跟那些模块毫无关系。（btrfs 分支早退也是同一个
        # 理由 —— 磁盘布局类的问题不该表现成"装到一半断了"。）
        if ! _as_root mkswap "$SWAPFILE" >/dev/null; then
            warn "mkswap failed on $SWAPFILE -- no swap this boot (later modules continue)"
            _swap_ok=0
        elif ! _as_root swapon "$SWAPFILE"; then
            warn "swapon failed on $SWAPFILE -- no swap this boot (later modules continue)"
            _swap_ok=0
        else
            success "swap on $SWAPFILE"
        fi
    fi

    # 条目与"当前是否已激活"分开判断：激活过但 fstab 丢了（重启后不会自动起）
    # 或反过来，都要补齐。幂等由 marker 保证。
    if ((_swap_ok)); then
        header "fstab entry"
        {
            printf '# swap（由 scripts/core/memory.sh 部署；zswap 在这之上做压缩）\n'
            printf '%s none swap defaults 0 0\n' "$SWAPFILE"
        } | append_block_once_root /etc/fstab "$SWAPFILE none swap"
    else
        warn "fstab entry skipped -- re-run this script after fixing the swapfile"
    fi
    unset _swap_ok
fi
unset _root_fs

# -- zswap --------------------------------------------------------------------
header "zswap"
# 这套方案把"压缩"整个交给 zswap：内核自带，本机（7.2.8-arch）默认 enabled=Y。
# 但它依赖一个**内核默认值**，而默认值会变 —— Arch wiki 的 Zswap 页至今还停留
# 在"要你手动 zswap.enabled=1"的年代。依赖会变的东西，就在使用点上断言它，
# 而不是相信它。
_zswap=/sys/module/zswap/parameters
if [[ -r "$_zswap/enabled" ]] && [[ "$(cat "$_zswap/enabled")" == Y ]]; then
    success "zswap enabled (compressor: $(cat "$_zswap/compressor"))"
else
    warn "zswap is NOT enabled -- swapped pages will go to disk uncompressed"
    warn "add zswap.enabled=1 to the kernel command line (see scripts/core/boot.sh)"
fi
unset _zswap

# -- SSD TRIM -----------------------------------------------------------------
header "SSD TRIM"
# 根分区挂载参数里没有 discard（Arch 默认 rw,relatime），回收完全靠这个 timer，
# 而 Arch 装了它却不替你启用（Ubuntu/Fedora 是开箱就开）。fstrim --all 会对不
# 支持的设备自己跳过，所以不需要这里再判断根设备是不是 SSD。
enable_system_service fstrim.timer
# timer 只有 active 才会排期，enable 只保证"下次开机起"
start_system_service fstrim.timer

success "Memory setup done"
