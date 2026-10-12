#!/usr/bin/env bash
# =============================================================================
# scripts/core/login.sh -- greetd + regreet 图形登录（用户阶段）
#
# 包装脚本 regreet 主、tuigreet 兜底。开机直接走 regreet 选择用户输密码
# 登录（无 autologin），避免 DMS lockAtStartup 在 niri 启动后再锁一次屏
# 导致闪桌面 1-2 秒。
#
# 两个配置文件都是 **仓库拥有**（config/greetd/ 下），login.sh 只负责部署。
# autologin 那段以注释形式躺在仓库文件里：要启用就取消注释再重跑，改的是仓库、
# 不是本机文件。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
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

install_config_root \
    "$REPO_DIR/config/greetd/config.toml" \
    /etc/greetd/config.toml 644

install_config_root \
    "$REPO_DIR/config/greetd/regreet.toml" \
    /etc/greetd/regreet.toml 644

install_config_root \
    "$REPO_DIR/config/greetd/greetd-wrapper.sh" \
    /usr/local/bin/greetd-wrapper.sh 755

switch_display_manager greetd.service

success "Login manager done"
