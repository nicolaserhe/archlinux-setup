#!/usr/bin/env bash
# =============================================================================
# scripts/config.sh -- 配置编排入口
#
# 用法:
#   bash scripts/config.sh              # 应用全部配置
#   bash scripts/config.sh shell fcitx # 只应用指定模块
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

ALL_CONFIGS=(shell desktop matugen dms fcitx)
configs=("${ALL_CONFIGS[@]}")
[[ $# -gt 0 ]] && configs=("$@")

for cfg in "${configs[@]}"; do
    cfg_script="$REPO_DIR/scripts/config/$cfg.sh"
    if [[ -f "$cfg_script" ]]; then
        bash "$cfg_script"
    else
        die "Unknown config module: $cfg (expected: $cfg_script)"
    fi
done

success "All config modules completed: ${configs[*]}"
