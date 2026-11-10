#!/usr/bin/env bash
# =============================================================================
# scripts/core/mousehop.sh -- Mousehop 键鼠共享（AUR mousehop-bin）
#
# lan-mouse 的替代：mDNS 自动发现对端，配置只写 hostname 不写 IP。Windows 侧
# 装同名 Mousehop（实例名 win），Linux 实例名取系统 hostname（archlinux）。
#
# 本脚本负责：
#   1. 安装 mousehop-bin（AUR 预编译二进制，不拉 Rust 工具链现场编译）
#   2. 首次播种 ~/.config/mousehop/config.toml（之后归运行时所有）
#   3. 写 systemd user service（随 graphical-session.target 启停）
#
# 配对授权不在这里做：两边 GUI 互相 Authorize 指纹，或
# `mousehop cli authorize-key <描述> <指纹>`。指纹属于机器私有状态。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# mousehop-bin: 作者维护的 AUR 预编译包（/usr/bin/mousehop + .desktop + 图标），
# 依赖 gtk4/libadwaita 由 pacman 解析。
header "Mousehop package (AUR)"
aur_install mousehop-bin

# -- 配置 ---------------------------------------------------------------------
# seed 而不是覆盖：授权指纹、last_addr、连接参数由 GUI/daemon 写回同一文件，
# 每次 install 覆盖会把已配对设备全部清掉。
header "Mousehop config"
copy_config_seed \
    "$REPO_DIR/config/mousehop/config.toml" \
    "$HOME/.config/mousehop/config.toml"

# -- systemd user service -----------------------------------------------------
# BindsTo=graphical-session.target：只有 niri 会话在时才跑（daemon 需要 Wayland
# 捕获/模拟后端）。Restart=on-failure：正常退出不拉回，崩溃或被杀才重试。
header "Mousehop systemd user service"
write_user_unit mousehop.service <<'EOF'
[Unit]
Description=Mousehop keyboard/mouse sharing
After=graphical-session.target
BindsTo=graphical-session.target

[Service]
ExecStart=/usr/bin/mousehop daemon
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
enable_user_service mousehop.service

success "Mousehop done"
