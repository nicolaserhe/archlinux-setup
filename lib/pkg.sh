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

# -- 私有：从输入中过滤出未安装项 ---------------------------------------------
# _filter_missing <check_cmd> <pkg>...
# check_cmd 接受单个包名作为参数，已安装时返回 0；未安装项原样输出到 stdout
_filter_missing() {
    local check="$1" pkg
    shift
    for pkg in "$@"; do
        if "$check" "$pkg" &>/dev/null; then
            warn "Already installed, skipping: $pkg" >&2
        else
            printf '%s\n' "$pkg"
        fi
    done
}

_check_pacman() { pacman -Q "$1"; }
_check_flatpak() { flatpak info "$1"; }

# -- pacman_install <pkg>... --------------------------------------------------
# 走 _as_root：root 时直调 pacman，非 root 走 sudo（无需 sudo 也能跑）。
pacman_install() {
    local -a missing
    mapfile -t missing < <(_filter_missing _check_pacman "$@")
    ((${#missing[@]} == 0)) && return 0
    _as_root pacman -S --noconfirm --needed "${missing[@]}"
}

# -- pacman_remove <pkg>... ---------------------------------------------------
# 只对已安装的包执行 -R；未安装项静默跳过。-R 不连带卸载依赖，
# 留 orphan 给用户用 `pacman -Rns $(pacman -Qdtq)` 自己清。
pacman_remove() {
    local -a present
    local pkg
    for pkg in "$@"; do
        if pacman -Q "$pkg" &>/dev/null; then
            present+=("$pkg")
        fi
    done
    ((${#present[@]} == 0)) && return 0
    _as_root pacman -R --noconfirm "${present[@]}"
}

# -- aur_install <pkg>... -----------------------------------------------------
aur_install() {
    local -a missing
    mapfile -t missing < <(_filter_missing _check_pacman "$@")
    ((${#missing[@]} == 0)) && return 0
    yay -S --noconfirm --needed "${missing[@]}"
}

# -- flatpak_install <app-id>... ----------------------------------------------
flatpak_install() {
    command_exists flatpak || die "flatpak is not installed"
    local -a missing
    mapfile -t missing < <(_filter_missing _check_flatpak "$@")
    ((${#missing[@]} == 0)) && return 0
    flatpak install -y --noninteractive flathub "${missing[@]}"
}
