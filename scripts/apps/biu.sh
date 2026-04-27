#!/usr/bin/env bash
# =============================================================================
# scripts/apps/biu.sh -- biu B 站音乐播放器（AUR）
# 单跑：bash scripts/apps/biu.sh
#
# https://github.com/wood3n/biu
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "biu"
aur_install biu-bin

success "biu done"
