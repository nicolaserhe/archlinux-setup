#!/usr/bin/env bash
# =============================================================================
# scripts/apps/qq.sh -- 腾讯 QQ（AUR linuxqq-appimage，Electron AppImage）
# 单跑：bash scripts/apps/qq.sh
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "linuxqq (AppImage)"
aur_install linuxqq-appimage

# Electron 在 Wayland/niri 下 GPU 进程用 memfd 共享内存触发 SIGBUS，
# --no-sandbox 不覆盖 GPU sandbox，必须单独禁用。
# 系统 desktop 文件用 --no-sandbox，这里创建用户级 override 补上缺失的 flag。
# 同名 desktop 文件：用户级优先于系统级。
_desktop_src="/usr/share/applications/linuxqq.desktop"
_desktop_dst_dir="$HOME/.local/share/applications"
_desktop_dst="$_desktop_dst_dir/linuxqq.desktop"

if [[ -f "$_desktop_src" ]]; then
    mkdir -p "$_desktop_dst_dir"
    sed 's/--no-sandbox/--no-sandbox --disable-gpu-sandbox/' \
        "$_desktop_src" > "$_desktop_dst"
    success "QQ desktop override with --disable-gpu-sandbox"
else
    warn "qq.desktop not found at $_desktop_src, skip override"
fi

success "QQ done"
