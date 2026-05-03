#!/usr/bin/env bash
# =============================================================================
# scripts/packages/aur.sh -- AUR 软件包（通过 yay，以普通用户运行）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

_install_yay() {
    local build_dir
    build_dir="$(mktemp -d /tmp/yay-build.XXXXXX)"
    trap 'rm -rf "$build_dir"' RETURN
    git_clone "$build_dir/yay" https://aur.archlinux.org/yay.git
    (cd "$build_dir/yay" && makepkg -si --noconfirm)
    success "yay installed"
}

header "yay"
command_exists yay && warn "yay already installed, skipping" || _install_yay

header "AUR packages"
# dms-shell-niri:          DankMaterialShell，niri 优化版本，替代 mako/fuzzel/polkit
# matugen:                 DMS 壁纸动态取色主题引擎
# kanata:                  键盘重映射守护进程
# maple-mono-nf-cn:        提供 "Maple Mono NL NF CN" 字族，alacritty.toml 中使用
aur_install \
    greetd-tuigreet \
    kanata \
    google-chrome \
    wechat-appimage \
    linuxqq-appimage \
    fcitx5-skin-adwaita-dark \
    maple-mono-nf-cn \
    dms-shell-niri \
    matugen

success "AUR packages done"
