#!/usr/bin/env bash
# =============================================================================
# scripts/core/niri-focus-restore.sh -- niri 焦点兜底服务
#
# 背景：Mousehop 的 layer-shell 捕获层是 keyboard_interactivity=Exclusive，
# 抢键盘时本地窗口会失焦，fcitx5 看到 focus:0 就"打不了字"。实测 niri 在层
# 消失后会自己把焦点还给窗口，所以主修复是 mousehop.sh 里的
# require_crossing_modifier 门控（碰右边缘不再抢键盘）。
#
# 这个 watcher 只是兜底：万一 niri 没还焦点，把最后聚焦的窗口找回来。
# 依赖 niri 的 JSON IPC（event-stream / focused-window / windows / workspaces
# / layers / overview-state）和 loginctl LockedHint。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

header "niri focus restore helper"
install_config \
    "$REPO_DIR/config/helpers/niri-focus-restore" \
    "$HOME/.local/bin/niri-focus-restore" \
    755

# -- systemd user service -----------------------------------------------------
# PartOf=graphical-session.target：会话结束就停。Restart=always：脚本在
# NIRI_SOCKET 失效（niri 重启换了 socket 路径）时会主动退出，靠 systemd 用
# 新导入的环境拉起。
header "niri focus restore systemd user service"
write_user_unit niri-focus-restore.service <<'EOF'
[Unit]
Description=Restore niri focus after exclusive keyboard layers
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/niri-focus-restore
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF
enable_user_service niri-focus-restore.service

success "niri focus restore done"
