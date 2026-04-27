#!/usr/bin/env bash
# =============================================================================
# scripts/core/compositor.sh -- niri Wayland 合成器 + XDG portals
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- Wayland compositor -------------------------------------------------------
# niri:                 基于 smithay 的平铺式 Wayland 合成器
# xwayland-satellite:   让 X11 应用在 niri 下独立运行
# xorg-xwayland:        xwayland-satellite 的运行时依赖
header "Wayland compositor"
pacman_install \
    niri \
    xwayland-satellite \
    xorg-xwayland

# -- Desktop portals ----------------------------------------------------------
# xdg-desktop-portal:       XDG 门户基础框架
# xdg-desktop-portal-gnome: 文件选择器后端（GTK file picker）
# xdg-desktop-portal-gtk:   GTK 应用的后备门户
# xdg-desktop-portal-wlr:   niri/wlroots ScreenCast 后端（视频会议屏幕共享必须）
header "Desktop portals"
pacman_install \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-wlr

success "Compositor + portals done"
