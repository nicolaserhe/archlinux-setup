#!/usr/bin/env bash
# =============================================================================
# scripts/apps/yaak.sh -- Yaak API 客户端（AUR）
# 单跑：bash scripts/apps/yaak.sh
#
# REST / GraphQL / gRPC API 客户端
# https://github.com/mountain-loop/yaak
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Yaak"
aur_install yaak

success "Yaak done"
