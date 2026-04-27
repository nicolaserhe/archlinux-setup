#!/usr/bin/env bash
# =============================================================================
# scripts/core/keyd.sh -- keyd 键盘重映射（系统级 daemon）
#
# keyd 是纯 C 实现的轻量 key remapping daemon，hook 内核层 evdev/uinput，
# 配置极简（INI 风格）。相对 kanata 的优势：系统级（不需 user session）、
# 启动早、不需要为用户配 input/uinput 组。
#
# 配置文件：/etc/keyd/default.conf  ← config/input/keyd.conf
# 服务：keyd.service（系统级）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
header "keyd package"
pacman_install keyd

# -- 配置文件 -----------------------------------------------------------------
# keyd 按字典序加载 /etc/keyd/*.conf，默认入口为 default.conf
header "keyd config"
sudo install -Dm644 "$REPO_DIR/config/input/keyd.conf" /etc/keyd/default.conf
success "Installed: /etc/keyd/default.conf"

# -- 启用服务 -----------------------------------------------------------------
# 系统级 daemon，enable + restart 后立刻生效（与 kanata 跑 user-level 不同，
# keyd 在登录前就工作，TTY/greetd 阶段就有正确的键位映射）。
header "keyd service"
enable_system_service keyd.service
sudo systemctl restart keyd.service
success "keyd is active (configuration applied)"

# 旧 kanata 残留若需清理（手动执行，本脚本不主动卸载）：
#   systemctl --user disable --now kanata.service
#   rm -f ~/.config/systemd/user/kanata.service
#   yay -Rns kanata
#   sudo gpasswd -d "$USER" uinput
