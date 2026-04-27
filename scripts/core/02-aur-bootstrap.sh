#!/usr/bin/env bash
# =============================================================================
# scripts/core/02-aur-bootstrap.sh -- yay 编译安装（用户阶段）
# 各 core/<name>.sh 与 apps/<name>.sh 通过 lib/pkg.sh 的 aur_install 调用 yay。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

_install_yay() {
    local build_dir
    build_dir="$(mktemp -d /tmp/yay-build.XXXXXX)"
    # root 阶段 install.sh 的 _cleanup 会清理 /tmp/yay-build.*
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

success "AUR bootstrap done"
