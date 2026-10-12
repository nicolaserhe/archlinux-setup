#!/usr/bin/env bash
# =============================================================================
# scripts/preflight.sh -- install.sh 跑之前的资产 + 冲突检查
#
# 早 fail 比跑到中段才 die 友好。install.sh 在 step 1 之前自动调用本脚本；
# 也可以单独跑 `bash scripts/preflight.sh` 做手动 sanity check。
#
# 退出码：0 = 全过；1 = 有问题。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

_failed=0

# -- 资产文件 ----------------------------------------------------------------
header "Preflight: assets"

# 壁纸：assets/wallpaper.{jpg,jpeg,png,webp}
if _wp="$(find_asset "$REPO_DIR/assets" "wallpaper.*")" && [[ -n "$_wp" ]]; then
    success "wallpaper found: $_wp"
else
    error "缺壁纸：assets/wallpaper.{jpg,jpeg,png,webp}"
    _failed=1
fi
unset _wp

# 头像
if _av="$(find_asset "$REPO_DIR/assets" "avatar.*")" && [[ -n "$_av" ]]; then
    success "avatar found: $_av"
else
    error "缺头像：assets/avatar.{jpg,jpeg,png,webp}"
    _failed=1
fi
unset _av

# 订阅 YAML：usb/sub2clash/files/ 下的 Clash 配置。
#
# 这个目录在 .gitignore 里（订阅内容不进仓库），内容由 usb/sub2clash/convert.sh
# 生成：约定名为 config.yaml 的转换产物 + geoip.metadb。但 lib/proxy.sh 取配置
# 时**不看文件名** —— 它 glob 目录里所有 *.yaml/*.yml 再 `sort | head -1`，所以
# 多躺一个别的 YAML（手写的备用配置、下载残骸）会静默顶掉 config.yaml；而那个
# 文件只要自己是个合法 Clash 配置，proxy.sh 的格式校验就放行，问题要到"代理走的
# 是别的节点"时才暴露。这里按名字与个数点出来。
_yamls=()
while IFS= read -r _y; do
    _yamls+=("$_y")
done < <(find "$REPO_DIR/usb/sub2clash/files" -maxdepth 1 \
    \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)

if ((${#_yamls[@]} == 0)); then
    error "缺订阅配置：usb/sub2clash/files/ 下没有 YAML（mihomo 启动必需）"
    error "  参考：bash usb/sub2clash/convert.sh <subscription-url>"
    _failed=1
elif ((${#_yamls[@]} > 1)); then
    warn "usb/sub2clash/files/ 下有多个 YAML，proxy.sh 只用排序后的第一个："
    for _y in "${_yamls[@]}"; do
        warn "    $(basename "$_y")"
    done
    warn "  → 实际生效的是 $(basename "${_yamls[0]}")；多余的那个请挪出这个目录"
    unset _y
elif [[ "$(basename "${_yamls[0]}")" != config.yaml ]]; then
    warn "订阅配置名为 $(basename "${_yamls[0]}")；convert.sh 的产物约定叫 config.yaml"
    warn "  → 名字不同不影响使用，但确认一下这确实是你要的那份"
else
    success "subscription YAML found: usb/sub2clash/files/config.yaml"
fi
unset _yamls

# -- 冲突检查：通知 daemon ---------------------------------------------------
# DMS 注册 org.freedesktop.Notifications；别的通知 daemon 抢到这个名字，
# dms.service 就起不来。列表按"Wayland 与 X11 上真会被装到的"收全：mako /
# swaync / fnott 是 wlroots 系（niri 用户最容易顺手装的就是它们），dunst /
# xfce4-notifyd 跨环境，notification-daemon 是老 X11 那个。
# 判断依据是**包在不在**，不是"有没有在跑"：装了但没跑的，下次登录就可能被
# autostart 拉起来，而那时 install 早跑完了，问题会以"通知重复弹两次"的形式出现。
header "Preflight: notification daemon conflicts"

_conflict_pkgs=()
for _pkg in mako dunst swaync fnott xfce4-notifyd notification-daemon; do
    if pacman -Q "$_pkg" &>/dev/null; then
        _conflict_pkgs+=("$_pkg")
    fi
done
unset _pkg

if ((${#_conflict_pkgs[@]} > 0)); then
    error "检测到与 DMS 冲突的通知 daemon：${_conflict_pkgs[*]}"
    error "  卸载：sudo pacman -Rns ${_conflict_pkgs[*]}"
    error "  也 disable user service：systemctl --user disable --now ${_conflict_pkgs[*]} 2>/dev/null"
    _failed=1
else
    success "no conflicting notification daemons"
fi
unset _conflict_pkgs

# -- 冲突检查：电源管理 daemon -----------------------------------------------
# core/system-services.sh 装 power-profiles-daemon；tlp / auto-cpufreq / cpupower
# 同样管 CPU 频率与电源策略，同时运行会互相覆盖设置（PPD 与 tlp 是众所周知互斥）。
#
# tuned-ppd 比它们更硬：它同时声明 Provides 和 Conflicts power-profiles-daemon，
# 装了它就轮不到 PPD —— 而 pacman_install 走的是 --noconfirm（冲突询问默认答
# No），于是 install 会在 user-phase 中段以"包冲突"中止，错误现场离病因很远。
# tuned 是 tuned-ppd 依赖的那个真正做调优的 daemon，自己不声明冲突（pacman 会
# 放行），但它跟 PPD 是同一件事的两种实现，装着它基本等于已经用它接管了 CPU/IO
# 调优 —— 同样列上，让"二选一"发生在装之前而不是运行期。
header "Preflight: power management daemon conflicts"

_conflict_pkgs=()
for _pkg in tlp auto-cpufreq cpupower tuned tuned-ppd; do
    if pacman -Q "$_pkg" &>/dev/null; then
        _conflict_pkgs+=("$_pkg")
    fi
done
unset _pkg

if ((${#_conflict_pkgs[@]} > 0)); then
    error "检测到与 power-profiles-daemon 冲突的电源管理工具：${_conflict_pkgs[*]}"
    error "  卸载：sudo pacman -Rns ${_conflict_pkgs[*]}"
    error "  也 disable system service：sudo systemctl disable --now ${_conflict_pkgs[*]} 2>/dev/null"
    _failed=1
else
    success "no conflicting power management daemons"
fi
unset _conflict_pkgs

# -- 结论 --------------------------------------------------------------------
if ((_failed != 0)); then
    error "Preflight 失败 —— 修复以上问题后重跑"
    exit 1
fi
success "Preflight 全过"
