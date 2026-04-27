#!/usr/bin/env bash
# =============================================================================
# scripts/core/clipboard.sh -- Wayland ↔ X11 剪贴板统一方案
#
# 单跑：bash scripts/core/clipboard.sh
# 拔除：systemctl --user disable --now unified-clipboard.service
#       + sudo rm /usr/local/bin/unified-clipboard
#       + rm ~/.config/systemd/user/unified-clipboard.service
#       + rm ~/.config/environment.d/90-clipboard.conf
#
# 一个 Python daemon 替代旧的 6-service 方案：
#   - CLIPBOARD 双向（text + image + file URI）
#   - PRIMARY 双向（text only）
#   - WeChat 文件粘贴兼容（text/uri-list 且无 image/* 时拒绝 text/*）
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"
source "$REPO_DIR/lib/fs.sh"

# =============================================================================
# 1. 依赖
# =============================================================================
header "Clipboard dependencies"

pacman_install python-xlib wl-clipboard xclip

# =============================================================================
# 2. unified-clipboard daemon
# =============================================================================
header "unified-clipboard daemon"

_BIN="/usr/local/bin/unified-clipboard"
sudo install -m 755 "$REPO_DIR/config/helpers/clipboard/unified-clipboard" "$_BIN"

_WAYLAND_DISPLAY=$(systemctl --user show-environment 2>/dev/null \
    | { grep '^WAYLAND_DISPLAY=' || true; } | cut -d= -f2)
_WAYLAND_DISPLAY="${_WAYLAND_DISPLAY:-wayland-1}"

_SVC="unified-clipboard.service"
write_user_unit "$_SVC" <<UNITDONE
[Unit]
Description=Wayland-X11 clipboard sync (CLIPBOARD + PRIMARY)
After=graphical-session.target
Wants=graphical-session.target
StartLimitBurst=0

[Service]
Type=simple
ExecStart=$_BIN
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=$_WAYLAND_DISPLAY
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
UNITDONE

systemctl --user daemon-reload
enable_user_service "$_SVC"
systemctl --user restart "$_SVC"

success "unified-clipboard daemon ready"

# =============================================================================
# 3. GTK4 中键粘贴（非 GNOME 环境默认关闭）
# =============================================================================
header "GTK4 PRIMARY paste"

if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true
    success "gtk-enable-primary-paste = true"
else
    warn "gsettings not found, skip GTK4 PRIMARY paste"
fi

# =============================================================================
# 4. WebKitGTK 中键粘贴（2.34+ 默认关闭）
# =============================================================================
header "WebKitGTK PRIMARY paste"

_env_dropin="$HOME/.config/environment.d/90-clipboard.conf"
mkdir -p "$HOME/.config/environment.d"
tee "$_env_dropin" >/dev/null <<WEBDONE
# Clipboard module: WebKitGTK PRIMARY paste (middle-click)
WEBKIT_GTK_ENABLE_PRIMARY_PASTE=1
WEBDONE

success "Clipboard module done"
