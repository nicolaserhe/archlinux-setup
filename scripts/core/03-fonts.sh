#!/usr/bin/env bash
# =============================================================================
# scripts/core/fonts.sh -- 字体基础设施（用户阶段）
#
# 收敛所有字体相关配置：系统字体包、fontconfig 规则、Flatpak 字体修复。
# 应用的字体选择（Alacritty/fcitx5/greetd 各自用哪个字体）不归这里管。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 系统字体包 ----------------------------------------------------------------
header "System font packages"
pacman_install fontconfig noto-fonts noto-fonts-cjk noto-fonts-emoji

# -- 系统级 fontconfig 规则 ----------------------------------------------------
header "System fontconfig rules"
sudo install -Dm644 "$REPO_DIR/config/fontconfig/60-emoji.conf" \
    /etc/fonts/conf.d/60-emoji.conf
sudo install -Dm644 "$REPO_DIR/config/fontconfig/65-cjk-sc.conf" \
    /etc/fonts/conf.d/65-cjk-sc.conf
sudo fc-cache -f
success "System fontconfig rules deployed"

# -- Flatpak CJK 字体修复 ------------------------------------------------------
header "Flatpak CJK fontconfig"
if [[ ! -f ~/.config/fontconfig/fonts.conf ]] \
    || ! grep -q 'Noto Sans CJK SC' ~/.config/fontconfig/fonts.conf 2>/dev/null; then
    mkdir -p ~/.config/fontconfig
    copy_config "$REPO_DIR/config/flatpak/fonts.conf" ~/.config/fontconfig/fonts.conf
    success "Deployed Flatpak fonts.conf"
else
    warn "Flatpak fonts.conf already configured, skipping"
fi

flatpak override --user \
    --filesystem="~/.config/fontconfig:ro" \
    --env=FONTCONFIG_FILE="$HOME/.config/fontconfig/fonts.conf"
success "Flatpak fontconfig override applied"

success "Font infrastructure done"
