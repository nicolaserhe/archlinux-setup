#!/usr/bin/env bash
# =============================================================================
# scripts/core/kdeconnect.sh -- KDE Connect (kdeconnectd) + DankKDEConnect 插件
#
# 后端选型：上游 KDE Connect，不用 Valent。
#   - kdeconnect 在官方仓库、随 KDE Gear 稳定发版；Valent 是 AUR 的 alpha 软件
#     （1.0.0.alpha.x），协议层 CVE 也只在 alpha 通道修
#   - DankKDEConnect 插件两种后端都支持（services/KDEConnectService.qml），
#     换后端不丢功能
#
# 启动路径：包自带 /etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop，
# 而 niri.service 带 Wants=xdg-desktop-autostart.target，systemd 的
# xdg-autostart-generator 会据此生成受管的
# app-org.kde.kdeconnect.daemon@autostart.service。
# 所以这里既不写 niri spawn-at-startup，也不自建 unit —— 少一条拉起路径就少一个
# 重复实例的来源（同 fcitx5 那次的教训，见 docs/quirks/input-and-fonts.md）。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 包安装 -------------------------------------------------------------------
# kdeconnect:      KDE Connect 守护进程 + kdeconnect-cli
# sshfs:           kdeconnect 的可选依赖，「浏览设备文件」（SFTP）需要
# nautilus-python: nautilus 加载 Python 扩展的桥。右键 Send to device 由
#                  kdeconnect 自带的 /usr/share/nautilus-python/extensions/
#                  kdeconnect-share.py 提供，没有这个桥就不加载
header "KDE Connect packages"
pacman_install kdeconnect sshfs nautilus-python

# -- DankKDEConnect 插件 ------------------------------------------------------
header "DankKDEConnect plugin"
_plugins_dir="$HOME/.config/DankMaterialShell/plugins"
_kdeconnect_dst="$_plugins_dir/DankKDEConnect"

if [[ -d "$_kdeconnect_dst" ]]; then
    warn "DankKDEConnect plugin already installed: $_kdeconnect_dst"
else
    mkdir -p "$_plugins_dir"
    (
        set -euo pipefail
        _tmp="$(mktemp -d /tmp/dms-plugins.XXXXXX)"
        # install.sh _cleanup 清理 /tmp/dms-plugins.*
        git_clone "$_tmp/dms-plugins" https://github.com/AvengeMedia/dms-plugins

        if [[ -d "$_tmp/dms-plugins/DankKDEConnect" ]]; then
            cp -r "$_tmp/dms-plugins/DankKDEConnect" "$_kdeconnect_dst"
            success "DankKDEConnect plugin installed: $_kdeconnect_dst"
        else
            warn "DankKDEConnect subdirectory not found in dms-plugins repo"
        fi
    )
fi
unset _plugins_dir _kdeconnect_dst

# -- 清理 Valent 时代的残留 ---------------------------------------------------
# valent 后端已弃用。旧的 kdeconnect.sh 是 aur_install valent，所以跑过旧版本的
# 机器上**装着 valent 包**，而 valent 自带
# /etc/xdg/autostart/ca.andyholmes.Valent-autostart.desktop（无 Hidden=true），
# 配上 niri.service 的 Wants=xdg-desktop-autostart.target，登录就会自动拉起
# 第二个守护进程，和 kdeconnectd 抢 org.kde.kdeconnect 并各做一遍设备发现。
header "Remove Valent-era leftovers"

# 卸载顺序很重要：**先卸包，再撤 mask**。反过来的话，包还在、mask 没了，
# 等于亲手把第二个守护进程放出来。（pacman_remove 对未安装的包静默跳过。）
#
# 卸载失败（包被别的包依赖、pacman db 上锁）不让它中断整个清理段 —— 但也不能在
# 包还在的情况下去撤 mask。所以记住结果，mask 只在这个包确实不在了才撤。
_valent_gone=0
if pacman_remove valent; then
    _valent_gone=1
else
    warn "Failed to remove valent; keeping its mask so it cannot autostart"
fi

# pacman -R 只删磁盘上的文件，**已经在跑的** valent 不受影响：旧版是用 niri 的
# spawn-at-startup 拉起的 gapplication service，不是 systemd unit，没有 unit 可 stop，
# 只能按进程名收。不收掉的话它会继续占着 org.kde.kdeconnect 抢设备发现，
# 一直闹到用户重新登录为止 —— 迁移就"看起来没生效"。
# pkill 返回 0 只代表信号递出去了，不代表进程真退了（它要 ignore SIGTERM 就还在），
# 所以复查一次再决定要不要补 SIGKILL。
if pkill -x valent 2>/dev/null; then
    sleep 0.3
    if pgrep -x valent >/dev/null 2>&1; then
        pkill -9 -x valent 2>/dev/null || true
        warn "valent ignored SIGTERM; sent SIGKILL"
    else
        success "Stopped running valent process"
    fi
fi

_need_reload=0

# 1) 旧的手工 mask。它压的是 systemd 从 desktop 文件名生成的 unit
#    （systemd 把名字里的 - 转义成 \x2d），包已卸载后它只是个悬空链接。
_valent_unit='app-ca.andyholmes.Valent\x2dautostart@autostart.service'
if ((_valent_gone)) && [[ -L "$HOME/.config/systemd/user/$_valent_unit" ]]; then
    rm -f "$HOME/.config/systemd/user/$_valent_unit"
    _need_reload=1
    success "Removed stale mask: $_valent_unit"
fi

# 2) 用户级 autostart 里的 kdeconnect 桌面文件：它按 basename 遮蔽包自带的
#    /etc/xdg/autostart/ 同名文件，通常是旧版 kdeconnect 留下的陈旧副本
#    （实测比系统级少一行 Name[ug] 翻译）。删掉，让包自己提供。
_user_autostart="$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop"
if [[ -f "$_user_autostart" ]]; then
    # 判定规则就是"有没有带禁用标记"，不做内容比对 —— 陈旧副本本来就与包内版本
    # 不同（少翻译行），逐字节比对会永远不相等、永远删不掉，遮蔽就留着。
    # 代价：用户往里加了自定义（如 Exec 参数）又没写禁用标记时会被一并删掉。
    # 标记的写法不能锚死：= 两侧允许空格（Desktop Entry 规范 + GLib 解析器），
    # 布尔值的判定实际由 systemd 的 xdg-autostart-generator 做，用的是
    # parse_boolean 语义 —— 大小写不敏感，且 1/yes/on 都算真，0/no/off 都算假。
    # 正则锚死 `Hidden=true` 的话，`Hidden = True` / `Hidden=1` 会被漏判成"没标记"，
    # 文件被删掉 —— 等于替用户把自启重新打开，跟这段代码的意图正好相反。
    # 取值方向也要看对：Hidden=false / X-GNOME-Autostart-enabled=true 是"显式启用"，
    # 不是禁用标记，不该保留。
    if grep -qiE '^[[:space:]]*Hidden[[:space:]]*=[[:space:]]*(true|1|yes|on)([[:space:]]|$)' "$_user_autostart" ||
        grep -qiE '^[[:space:]]*X-GNOME-Autostart-enabled[[:space:]]*=[[:space:]]*(false|0|no|off)([[:space:]]|$)' "$_user_autostart"; then
        warn "User autostart override carries a deliberate disable flag, leaving it"
    else
        rm -f "$_user_autostart"
        _need_reload=1
        success "Removed stale autostart override: $_user_autostart"
    fi
fi

# 3) Valent 用的 GCR SSH agent 环境变量：它指向 gcr-ssh-agent.socket 的路径，
#    而该 socket 单元默认未启用 —— SSH_AUTH_SOCK 指向不存在的 socket 只会让 ssh 报错。
#    kdeconnectd 的 SFTP 用设备自带的 key，不需要 agent。
_valent_env="$HOME/.config/environment.d/valent.conf"
if [[ -f "$_valent_env" ]]; then
    rm -f "$_valent_env"
    success "Removed: $_valent_env"
fi

# 4) Valent 专用的 nautilus 右键扩展：kdeconnect 自带等价功能的 kdeconnect-share.py。
_nautilus_ext="$HOME/.local/share/nautilus-python/extensions/valent_send.py"
if [[ -f "$_nautilus_ext" ]]; then
    rm -f "$_nautilus_ext"
    success "Removed: valent_send.py (kdeconnect ships kdeconnect-share.py instead)"
fi

# mask 增删与 autostart 覆盖都会改动 unit 图，统一在这里 reload 一次 ——
# 放在各分支里的话，只命中其一（比如有 mask 但没有那份 autostart 覆盖）就会漏掉。
if ((_need_reload)); then
    systemctl --user daemon-reload || warn "daemon-reload failed; re-login to apply"
fi

unset _valent_unit _user_autostart _valent_env _nautilus_ext _need_reload _valent_gone

success "KDE Connect done"
