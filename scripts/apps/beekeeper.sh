#!/usr/bin/env bash
# =============================================================================
# scripts/apps/beekeeper.sh -- Beekeeper Studio 数据库 GUI（AUR）
# 单跑：bash scripts/apps/beekeeper.sh
#
# 支持 MySQL / PostgreSQL / SQLite / SQL Server 等
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Beekeeper Studio"
aur_install beekeeper-studio-bin

success "Beekeeper done"
