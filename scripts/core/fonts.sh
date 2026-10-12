#!/usr/bin/env bash
# =============================================================================
# scripts/core/fonts.sh -- 字体基础设施（用户阶段）
#
# 收敛所有字体相关配置：系统字体包、fontconfig 规则、Flatpak 字体修复。
# 应用的字体选择（Alacritty/fcitx5/greetd 各自用哪个字体）不归这里管。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 系统字体包 ----------------------------------------------------------------
header "System font packages"
pacman_install fontconfig noto-fonts noto-fonts-cjk noto-fonts-emoji

# -- 系统级 fontconfig 规则 ----------------------------------------------------
header "System fontconfig rules"
install_config_root "$REPO_DIR/config/fontconfig/60-emoji.conf" \
    /etc/fonts/conf.d/60-emoji.conf 644
install_config_root "$REPO_DIR/config/fontconfig/65-cjk-sc.conf" \
    /etc/fonts/conf.d/65-cjk-sc.conf 644
_as_root fc-cache -f
success "System fontconfig rules deployed"

# -- Flatpak CJK 字体修复 ------------------------------------------------------
# 这个文件只有本仓库会写（flatpak override 不动它），所以是 own 而非 seed：
# 内容对不对交给 just drift 比对，不在这里做内容探测。
#
# 文件名带 flatpak-：它**只**通过下面的 FONTCONFIG_FILE 给沙箱内的应用用。
# 主机那侧由 /etc/fonts/conf.d/65-cjk-sc.conf 管，没必要占 fontconfig 的
# 用户级配置路径（`~/.config/fontconfig/fonts.conf`）那个槽位。
header "Flatpak CJK fontconfig"

copy_config "$REPO_DIR/config/flatpak/fonts.conf" \
    "$HOME/.config/fontconfig/flatpak-cjk.conf"

flatpak override --user \
    --filesystem="~/.config/fontconfig:ro" \
    --env=FONTCONFIG_FILE="$HOME/.config/fontconfig/flatpak-cjk.conf"
success "Flatpak fontconfig override applied"

success "Font infrastructure done"
