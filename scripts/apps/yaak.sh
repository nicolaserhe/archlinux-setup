#!/usr/bin/env bash
# =============================================================================
# scripts/apps/yaak.sh -- Yaak API 客户端
# 单跑：bash scripts/apps/yaak.sh
#
# REST / GraphQL / gRPC API 客户端
# https://github.com/mountain-loop/yaak
#
# 走官方仓库（extra/yaak），不是 AUR：AUR 只剩 yaak-bin / yaak-git 之类，
# 没有与包名同名的 yaak 了（2026-10-12 AUR RPC 查不到）。原来写 aur_install
# 是让 yay 绕一圈去装 extra 的包。副作用是这条脚本不再需要 yay。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Yaak"
pacman_install yaak

success "Yaak done"
