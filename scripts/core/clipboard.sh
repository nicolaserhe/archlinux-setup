#!/usr/bin/env bash
# =============================================================================
# scripts/core/clipboard.sh -- Wayland ↔ X11 剪贴板完整方案
#
# 单跑：bash scripts/core/clipboard.sh
# 拔除：删除此脚本 + systemctl --user disable primary-sync.service wechat-uri-fix.service
#       + 删除 ~/.config/environment.d/90-clipboard.conf
#       + 删除 ~/.local/bin/primary-sync /usr/local/bin/wechat-uri-fix
#
# 五个子系统协同工作：
#   1. multicliprelay  Wayland CLIPBOARD ↔ X11 CLIPBOARD（支持图片+文件URI）
#   2. primary-sync    Wayland CLIPBOARD ↔ Wayland PRIMARY ↔ X11 PRIMARY
#   3. wechat-uri-fix  Python daemon — Wayland 出现 text/uri-list 时接管 X11
#                      CLIPBOARD，仅暴露 file targets，拒绝 text/plain。
#                      强制 WeChat Flatpak 把文件复制识别为文件粘贴。
#                      微信修好/迁移 Wayland 后整段可独立删除。
#   4. GTK4 设置       gtk-enable-primary-paste（nautilus 等中键粘贴）
#   5. WebKitGTK 设置  WEBKIT_GTK_ENABLE_PRIMARY_PASTE（Yaak 等中键粘贴）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"
source "$REPO_DIR/lib/fs.sh"

# =============================================================================
# 1. multicliprelay CLIPBOARD 桥（Wayland ↔ X11，含图片）
# =============================================================================
header "multicliprelay CLIPBOARD bridge"

aur_install multicliprelay-bin

for _svc in \
    multicliprelay-relay.service \
    multicliprelay-wl-watch.service \
    multicliprelay-wl-apply.service \
    multicliprelay-x11-sync.service
do
    enable_user_service "$_svc"
done
unset _svc

# -- Wayland display name（niri 用 wayland-1）--
# 套层 `|| true` 是因为 set -e + pipefail 下 `var=$(failing_pipeline)`
# 会让脚本静默退出。grep 在 TTY install 阶段（user env 还没 WAYLAND_DISPLAY）
# 必定 no-match → 必须兜住。
_WAYLAND_DISPLAY=$(systemctl --user show-environment 2>/dev/null \
    | { grep '^WAYLAND_DISPLAY=' || true; } | cut -d= -f2)
_WAYLAND_DISPLAY="${_WAYLAND_DISPLAY:-wayland-1}"

# -- 自动选空闲端口（避开常用开发端口）--
_find_free_port() {
    local _existing _port
    # ss 进程名被 Linux 内核截断到 15 字符："multicliprelay-relay" → "multicliprelay-"
    # 所以 grep pattern 必须用截断后的；同时套 `|| true` 兜住 no-match。
    _existing=$( (ss -tlnp 2>/dev/null \
        | grep 'multicliprelay-' \
        | sed -n 's/.*127\.0\.0\.1:\([0-9]*\).*/\1/p' \
        | head -1) || true )
    if [[ -n "$_existing" ]]; then
        echo "$_existing"
        return
    fi
    for _port in 17080 17081 17082 17083 17084 17085 17086 17087 17088 17089; do
        if ! ss -tln | grep -q "127.0.0.1:$_port "; then
            echo "$_port"
            return
        fi
    done
    for _port in $(seq 17000 17999); do
        if ! ss -tln | grep -q "127.0.0.1:$_port "; then
            echo "$_port"
            return
        fi
    done
    error "No free port in 17000-17999"
    exit 1
}
_RELAY_PORT=$(_find_free_port)
_RELAY_ADDR="127.0.0.1:$_RELAY_PORT"
info "Relay port: $_RELAY_PORT"

# Drop-in 设计要点：
#   * **不**用 ExecStartPre 等 socket — 即便加 `-` 前缀让 ExecStartPre 失败
#     非致命，systemctl start **仍会阻塞**等它跑完 30s。TTY install 阶段三个
#     drop-in 累计阻塞 90s，体验差。
#   * Daemon 启动连不上 X11/Wayland → 立刻 exit → systemd Restart=on-failure
#     在 5s 后重启 → 一直 retry 到用户登录 niri、socket 就绪。
#   * StartLimitBurst=0：禁用启动速率限制。否则 install→reboot 间隔几分钟内
#     daemon 重试 12+ 次就会 hit burst limit 进入永久 failed state，graphical-
#     session.target 启动也不会自动 reset。
#   * StartLimit* 必须在 [Unit] 段（[Service] 下 systemd 静默忽略）。

# -- drop-in: relay --
_relay_dropin="$HOME/.config/systemd/user/multicliprelay-relay.service.d"
mkdir -p "$_relay_dropin"
tee "$_relay_dropin/startlimit.conf" <<DROPDONE
[Unit]
StartLimitBurst=0

[Service]
Environment=MULTICLIPRELAY_BIND=$_RELAY_ADDR
RestartSec=5
DROPDONE

# -- drop-in: x11-sync --
_x11_dropin="$HOME/.config/systemd/user/multicliprelay-x11-sync.service.d"
mkdir -p "$_x11_dropin"
tee "$_x11_dropin/display.conf" <<DROPDONE
[Unit]
StartLimitBurst=0

[Service]
Environment=DISPLAY=:0
Environment=MULTICLIPRELAY_RELAY=$_RELAY_ADDR
RestartSec=5
DROPDONE

# -- drop-in: wl-watch + wl-apply --
for _svc in multicliprelay-wl-watch.service multicliprelay-wl-apply.service; do
    _d="$HOME/.config/systemd/user/$_svc.d"
    mkdir -p "$_d"
    tee "$_d/wayland.conf" <<DROPDONE
[Unit]
StartLimitBurst=0

[Service]
Environment=WAYLAND_DISPLAY=$_WAYLAND_DISPLAY
Environment=MULTICLIPRELAY_RELAY=$_RELAY_ADDR
RestartSec=5
DROPDONE
done

systemctl --user daemon-reload
systemctl --user reset-failed \
    multicliprelay-x11-sync.service \
    multicliprelay-relay.service \
    multicliprelay-wl-apply.service \
    multicliprelay-wl-watch.service 2>/dev/null || true
for _svc in \
    multicliprelay-relay.service \
    multicliprelay-x11-sync.service \
    multicliprelay-wl-watch.service \
    multicliprelay-wl-apply.service
do
    systemctl --user restart "$_svc"
done

success "CLIPBOARD bridge ready"

# =============================================================================
# 2. PRIMARY + CLIPBOARD 三向同步 daemon（Python，事件驱动）
#    替代上一代 bash + 200ms 轮询版本。三个事件源：
#      * wl-paste --watch                — Wayland CLIPBOARD
#      * wl-paste --primary --watch      — Wayland PRIMARY
#      * XFIXES SelectSelectionInput     — X11 PRIMARY
#    依赖：python-xlib + wl-clipboard + xclip
# =============================================================================
header "PRIMARY + CLIPBOARD three-way sync"

pacman_install python-xlib  # idempotent，wechat-uri-fix 也用

_psync_bin="/usr/local/bin/primary-sync"
sudo install -m 755 "$REPO_DIR/config/helpers/clipboard/primary-sync" "$_psync_bin"

# 老 bash 版清理（如果之前装过）
rm -f "$HOME/.local/bin/primary-sync"

_svc_name="primary-sync.service"
mkdir -p "$HOME/.config/systemd/user"
tee "$HOME/.config/systemd/user/$_svc_name" <<PSYNCDONE
[Unit]
Description=PRIMARY selection sync between Wayland and X11 (Python event-driven)
After=graphical-session.target
Wants=graphical-session.target
# 禁用启动速率限制 — daemon 已内部 retry-loop 等待 X11/Wayland，不会进入
# crash-loop；保留 burst 限制反而会让 install 阶段的 retry 击中 limit。
StartLimitBurst=0

[Service]
Type=simple
# NO ExecStartPre — daemon retries internally until X11/Wayland are ready
# (see daemon source). This keeps `systemctl restart` returning 0 even when
# install.sh runs from a TTY with no graphical session yet, so the install
# script's `set -e` doesn't trip.
ExecStart=$_psync_bin
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=$_WAYLAND_DISPLAY
# Restart=always covers daemon crashes after a successful start. The 5s
# debounce keeps tight crash loops cheap. Internal retry loop handles the
# pre-niri "not yet ready" phase without restarts.
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
PSYNCDONE
systemctl --user daemon-reload
enable_user_service "$_svc_name"
systemctl --user restart "$_svc_name"

success "PRIMARY selection sync ready"

# =============================================================================
# 3. wechat-uri-fix —— Wayland → X11 CLIPBOARD 文件粘贴兼容层
#    单一 Python daemon。当 Wayland 剪贴板包含 text/uri-list 时接管 X11
#    CLIPBOARD，只暴露 file targets，拒绝所有 text/* 请求 → WeChat Flatpak
#    fall back 到 text/uri-list，正确识别为文件粘贴。
#    其它时间释放 X11 CLIPBOARD，由 multicliprelay 接管正常同步。
#
#    独立模块。微信修复或迁移 Wayland 后整段可删（见文件顶部 docstring）。
# =============================================================================
header "wechat-uri-fix (file URI compatibility for WeChat)"

pacman_install python-xlib

_wuf_bin="/usr/local/bin/wechat-uri-fix"
sudo install -m 755 "$REPO_DIR/config/helpers/clipboard/wechat-uri-fix" "$_wuf_bin"

# 老 daemon 清理（如果之前装过 bash 版）
_old_svc="x11-file-uri-bridge.service"
if systemctl --user list-unit-files "$_old_svc" &>/dev/null; then
    systemctl --user disable --now "$_old_svc" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$_old_svc"
fi
rm -f "$HOME/.local/bin/x11-file-uri-bridge"
sudo rm -f /usr/local/bin/x11-file-uri-owner

_wuf_svc="wechat-uri-fix.service"
mkdir -p "$HOME/.config/systemd/user"
tee "$HOME/.config/systemd/user/$_wuf_svc" <<WUFDONE
[Unit]
Description=WeChat clipboard compatibility (Wayland text/uri-list → X11 CLIPBOARD)
After=graphical-session.target multicliprelay-x11-sync.service
Wants=graphical-session.target
# 禁用启动速率限制 — 同 primary-sync 的理由。
StartLimitBurst=0

[Service]
Type=simple
# NO ExecStartPre — daemon retries internally until X11/Wayland are ready,
# so TTY install.sh runs don't trip systemctl restart's exit code.
ExecStart=$_wuf_bin
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=$_WAYLAND_DISPLAY
# Restart=always covers daemon crashes after a successful start.
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
WUFDONE
systemctl --user daemon-reload
enable_user_service "$_wuf_svc"
systemctl --user restart "$_wuf_svc"

success "wechat-uri-fix ready"

# =============================================================================
# 4. GTK4 中键粘贴（非 GNOME 环境默认关闭）
# =============================================================================
header "GTK4 PRIMARY paste"

if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true
    success "gtk-enable-primary-paste = true"
else
    warn "gsettings not found, skip GTK4 PRIMARY paste"
fi

# =============================================================================
# 5. WebKitGTK 中键粘贴（2.34+ 默认关闭）
# =============================================================================
header "WebKitGTK PRIMARY paste"

_env_dropin="$HOME/.config/environment.d/90-clipboard.conf"
mkdir -p "$HOME/.config/environment.d"
tee "$_env_dropin" <<WEBDONE
# Clipboard module: WebKitGTK PRIMARY paste (middle-click)
WEBKIT_GTK_ENABLE_PRIMARY_PASTE=1
WEBDONE

success "Clipboard module done"
