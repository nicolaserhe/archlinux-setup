#!/usr/bin/env bash
# =============================================================================
# scripts/apps/dbx.sh -- DBX 数据库客户端（AUR）
# 单跑：bash scripts/apps/dbx.sh
#
# 开源跨平台数据库 GUI，支持 40+ 数据库，内置 AI 助手和 MCP Server
# https://github.com/t8y2/dbx
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "DBX"
aur_install dbx-bin

success "DBX done"
