#!/usr/bin/env bash
# =============================================================================
# scripts/packages.sh -- 软件包安装编排入口
#
# 用法:
#   bash scripts/packages.sh              # 安装全部来源
#   bash scripts/packages.sh pacman aur  # 只安装指定来源
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

ALL_SOURCES=(pacman aur flatpak)
sources=("${ALL_SOURCES[@]}")
[[ $# -gt 0 ]] && sources=("$@")

for src in "${sources[@]}"; do
    pkg_script="$REPO_DIR/scripts/packages/$src.sh"
    if [[ -f "$pkg_script" ]]; then
        bash "$pkg_script"
    else
        die "Unknown package source: $src (expected: $pkg_script)"
    fi
done

success "All package sources completed: ${sources[*]}"
