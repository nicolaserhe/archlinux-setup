#!/usr/bin/env bash
# =============================================================================
# scripts/core/04-flatpak-init.sh -- Flathub remote（用户阶段）
# 各 apps/<name>.sh 通过 lib/pkg.sh 的 flatpak_install 调用 flatpak。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

header "Flathub remote"
if flatpak remotes | grep -q flathub; then
    warn "Flathub remote already exists, skipping"
else
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    success "Flathub remote added"
fi

success "Flatpak init done"
