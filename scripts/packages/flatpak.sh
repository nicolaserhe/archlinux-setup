#!/usr/bin/env bash
# =============================================================================
# scripts/packages/flatpak.sh -- Flatpak 包（来自 Flathub，以普通用户运行）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Flathub remote"
if flatpak remotes | grep -q flathub; then
    warn "Flathub remote already exists, skipping"
else
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    success "Flathub remote added"
fi

success "Flatpak packages done"
