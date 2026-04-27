#!/usr/bin/env bash
# =============================================================================
# scripts/core/login.sh -- greetd + regreet 图形登录（用户阶段）
#
# 包装脚本 regreet 主、tuigreet 兜底。开机走 [initial_session] 自动登录，
# 只有 logout 后才会看到 greeter，所以美观让位给"永远能登录"。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# greetd:               轻量 TTY 登录管理器
# greetd-regreet:       GTK4 图形登录界面（开机首次启动时由 initial_session 跳过）
# greetd-tuigreet:      TTY 字符登录界面，作为 regreet 失败时的 fallback
header "greetd packages"
pacman_install greetd greetd-regreet greetd-tuigreet

# -- greetd 配置 --------------------------------------------------------------
header "greetd config"
sudo mkdir -p /etc/greetd

sudo cp "$REPO_DIR/config/greetd/greetd-wrapper.sh" /usr/local/bin/greetd-wrapper.sh
sudo chmod +x /usr/local/bin/greetd-wrapper.sh
success "Deployed greetd wrapper"

sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "/usr/local/bin/greetd-wrapper.sh"
user = "greeter"

# 开机首次启动自动登录到 niri；DMS lockAtStartup 仍会立即锁屏，
# 解锁一次即可进入桌面。后续 logout 回到 default_session（regreet）。
[initial_session]
command = "niri-session"
user = "$USER"
EOF
success "Written: /etc/greetd/config.toml"

sudo tee /etc/greetd/regreet.toml >/dev/null <<'EOF'
[background]
path = ""
fit = "Cover"

[GTK]
application_prefer_dark_theme = true
font_name = "Cantarell 16"

[appearance]
greeting_msg = "Welcome back"

[widget.clock]
format = "%a %H:%M"
resolution = "500ms"
EOF
success "Written: /etc/greetd/regreet.toml"

switch_display_manager greetd.service

success "Login manager done"
