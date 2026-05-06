#!/usr/bin/env bash
# =============================================================================
# scripts/packages/aur.sh -- AUR 软件包（通过 yay，以普通用户运行）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

_install_yay() {
    local build_dir
    build_dir="$(mktemp -d /tmp/yay-build.XXXXXX)"
    # trap RETURN 保证函数返回时清理临时目录，无论成功还是失败
    trap 'rm -rf "$build_dir"' RETURN
    git_clone "$build_dir/yay" https://aur.archlinux.org/yay.git
    (cd "$build_dir/yay" && makepkg -si --noconfirm)
    success "yay installed"
}

header "yay"
if command_exists yay; then
    warn "yay already installed, skipping"
else
    _install_yay
fi

# dms-shell-niri:    DankMaterialShell（niri 优化版），替代 mako/fuzzel/polkit
# matugen:           DMS 壁纸动态取色引擎
# kanata:            键盘重映射守护进程
# maple-mono-nf-cn:  alacritty 使用的 "Maple Mono NL NF CN" 字族
# valent:            KDE Connect 的 GNOME/GTK 实现，DankKDEConnect 的后端
header "AUR packages"
aur_install \
    greetd-tuigreet \
    kanata \
    google-chrome \
    wechat-appimage \
    linuxqq-appimage \
    maple-mono-nf-cn \
    dms-shell-niri \
    matugen \
    valent

success "AUR packages done"
