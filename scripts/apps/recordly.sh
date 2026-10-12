#!/usr/bin/env bash
# =============================================================================
# scripts/apps/recordly.sh -- Recordly 屏幕录制（AUR）
# 单跑：bash scripts/apps/recordly.sh
#
# 开源 Screen Studio 替代品：自动缩放、光标平滑、时间轴编辑
# https://github.com/webadderall/Recordly
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Recordly"
aur_install recordly-bin

success "Recordly done"
