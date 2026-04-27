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

# 订阅 YAML：usb/sub2clash/files/*.yaml 任一
if compgen -G "$REPO_DIR/usb/sub2clash/files/*.yaml" >/dev/null \
    || compgen -G "$REPO_DIR/usb/sub2clash/files/*.yml" >/dev/null; then
    success "subscription YAML found in usb/sub2clash/files/"
else
    error "缺订阅配置：usb/sub2clash/files/*.yaml（mihomo 启动必需）"
    error "  参考：bash usb/sub2clash/convert.sh <subscription-url>"
    _failed=1
fi

# -- 冲突检查：通知 daemon ---------------------------------------------------
# DMS 注册 org.freedesktop.Notifications；mako/dunst/notification-daemon 会
# 抢占 D-Bus name 让 dms.service 启不起来
header "Preflight: notification daemon conflicts"

_conflict_pkgs=()
for _pkg in mako dunst notification-daemon; do
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
# core/system-services.sh 装 power-profiles-daemon；tlp / auto-cpufreq 同样
# 管 CPU 频率与电源策略，同时运行会互相覆盖设置（PPD 与 tlp 是众所周知互斥）
header "Preflight: power management daemon conflicts"

_conflict_pkgs=()
for _pkg in tlp auto-cpufreq cpupower; do
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
