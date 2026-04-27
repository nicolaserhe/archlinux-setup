#!/usr/bin/env bash
# =============================================================================
# scripts/core/login.sh -- greetd + regreet 图形登录（用户阶段）
#
# 包装脚本 regreet 主、tuigreet 兜底。开机直接走 regreet 选择用户输密码
# 登录（无 autologin），避免 DMS lockAtStartup 在 niri 启动后再锁一次屏
# 导致闪桌面 1-2 秒。要恢复 autologin：在 /etc/greetd/config.toml 末尾
# 追加 [initial_session] command="niri-session" user="<USER>"，同时把
# config/dms/settings.json 的 lockAtStartup 改回 true。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# greetd:               轻量 TTY 登录管理器
# greetd-regreet:       GTK4 图形登录界面（每次开机都会看到，无 autologin）
# greetd-tuigreet:      TTY 字符登录界面，作为 regreet 失败时的 fallback
header "greetd packages"
pacman_install greetd greetd-regreet greetd-tuigreet

# -- greetd 配置 --------------------------------------------------------------
header "greetd config"
sudo mkdir -p /etc/greetd

sudo install -Dm755 \
    "$REPO_DIR/config/greetd/greetd-wrapper.sh" \
    /usr/local/bin/greetd-wrapper.sh
success "Deployed greetd wrapper"

sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "/usr/local/bin/greetd-wrapper.sh"
user = "greeter"
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
