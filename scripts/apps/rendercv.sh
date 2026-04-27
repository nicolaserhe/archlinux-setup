#!/usr/bin/env bash
# =============================================================================
# scripts/apps/rendercv.sh -- rendercv 简历生成器（AUR）
# 单跑：bash scripts/apps/rendercv.sh
#
# 基于 YAML 的简历生成器
# https://github.com/rendercv/rendercv
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "rendercv"
aur_install rendercv-bin

success "rendercv done"
