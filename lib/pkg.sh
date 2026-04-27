#!/usr/bin/env bash
# =============================================================================
# lib/pkg.sh -- 包安装助手（pacman / AUR / Flatpak）
#
# 依赖：lib/utils.sh
# =============================================================================

[[ -n "${_PKG_LOADED:-}" ]] && return 0
_PKG_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/pkg.sh" >&2
    return 1
}

# pacman_install <pkg>... -- 跳过已安装的包
pacman_install() {
    local pkg
    local -a to_install=()
    for pkg in "$@"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            warn "Already installed, skipping: $pkg"
        else
            to_install+=("$pkg")
        fi
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    pacman -S --noconfirm "${to_install[@]}"
}

# aur_install <pkg>... -- 通过 yay 安装，跳过已安装的包
aur_install() {
    local pkg
    local -a to_install=()
    for pkg in "$@"; do
        if pacman -Q "$pkg" &>/dev/null; then
            warn "Already installed, skipping: $pkg"
        else
            to_install+=("$pkg")
        fi
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    yay -S --needed --noconfirm "${to_install[@]}"
}

# flatpak_install <app-id>... -- 从 Flathub 安装，跳过已安装的应用
flatpak_install() {
    command -v flatpak &>/dev/null || { error "flatpak is not installed"; return 1; }
    local app
    local -a to_install=()
    for app in "$@"; do
        if flatpak info "$app" &>/dev/null; then
            warn "Already installed, skipping: $app"
        else
            to_install+=("$app")
        fi
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    flatpak install -y --noninteractive flathub "${to_install[@]}"
}
