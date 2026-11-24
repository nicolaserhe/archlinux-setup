#!/usr/bin/env bash
# =============================================================================
# scripts/apps/nautilus.sh -- Nautilus 右键终端扩展（AUR）+ Alacritty 配置
# 单跑：bash scripts/apps/nautilus.sh
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Nautilus terminal extension"
aur_install nautilus-open-any-terminal

# 右键“在终端中打开”默认是 gnome-terminal；改成 Alacritty。
if command_exists gsettings; then
    if gsettings list-schemas 2>/dev/null |
        grep -qx 'com.github.stunkymonkey.nautilus-open-any-terminal'; then
        gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal alacritty
        success "nautilus-open-any-terminal -> alacritty"
    else
        warn "nautilus-open-any-terminal schema not found; configure manually"
    fi
else
    warn "gsettings not found; configure nautilus-open-any-terminal manually"
fi

success "Nautilus extensions done"
