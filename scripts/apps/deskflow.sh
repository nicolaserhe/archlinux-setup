#!/usr/bin/env bash
# =============================================================================
# scripts/apps/deskflow.sh -- Deskflow 键鼠共享（软件 KVM）
# 单跑：bash scripts/apps/deskflow.sh
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Deskflow (AUR)"
aur_install deskflow

success "Deskflow done"
