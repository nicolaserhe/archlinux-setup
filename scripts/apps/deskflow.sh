#!/usr/bin/env bash
# =============================================================================
# scripts/apps/deskflow.sh -- Deskflow 键鼠共享（软件 KVM）
# 单跑：bash scripts/apps/deskflow.sh
#
# 走官方仓库（extra/deskflow），不是 AUR：AUR 里已经没有 deskflow 这个包名了
# （2026-10-12 `yay -Si` / AUR RPC 都查不到；只剩 deskflow-git）。原来写 aur_install
# 是把 yay 当中间人绕一圈，包本身在 extra 里。副作用是这条脚本不再需要 yay。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Deskflow"
pacman_install deskflow

success "Deskflow done"
