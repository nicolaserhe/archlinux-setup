#!/usr/bin/env bash
# =============================================================================
# scripts/config.sh -- 配置编排入口
#
# 用法:
#   bash scripts/config.sh              # 应用全部配置
#   bash scripts/config.sh shell fcitx  # 只应用指定模块
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

ALL_CONFIGS=(shell desktop matugen dms fcitx kdeconnect)
configs=("${ALL_CONFIGS[@]}")
(( $# > 0 )) && configs=("$@")

for cfg in "${configs[@]}"; do
    cfg_script="$REPO_DIR/scripts/config/$cfg.sh"
    [[ -f "$cfg_script" ]] || die "Unknown config module: $cfg (expected: $cfg_script)"
    bash "$cfg_script"
done

success "All config modules completed: ${configs[*]}"
