#!/usr/bin/env bash
# =============================================================================
# scripts/apps/chrome.sh -- Google Chrome 浏览器（AUR）
# 单跑：bash scripts/apps/chrome.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Google Chrome"
aur_install google-chrome

success "Chrome done"
