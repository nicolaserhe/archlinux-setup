#!/usr/bin/env bash
# =============================================================================
# lib/common.sh -- 包安装 / 通用工具函数
#
# 规则：只能 source，不能直接执行。
#       需要先 source lib/utils.sh。
# =============================================================================

[[ -n "${_COMMON_LOADED:-}" ]] && return 0
_COMMON_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/common.sh" >&2
    return 1
}

# -- sudo 配置 ----------------------------------------------------------------

setup_sudo() {
    pacman -S --noconfirm --needed sudo
    if grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
        warn "wheel sudo already enabled, skipping"
    else
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        success "wheel sudo enabled"
    fi
}

setup_temp_nopasswd_sudo() {
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/install-tmp
    chmod 440 /etc/sudoers.d/install-tmp
    success "Temporary passwordless sudo configured"
}

# -- 包安装（幂等：已装则跳过）-----------------------------------------------

pacman_install() {
    local to_install=()
    for pkg in "$@"; do
        pacman -Qi "$pkg" &>/dev/null &&
            warn "Already installed, skipping: $pkg" ||
            to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    pacman -S --noconfirm "${to_install[@]}"
}

aur_install() {
    local to_install=()
    for pkg in "$@"; do
        pacman -Q "$pkg" &>/dev/null &&
            warn "Already installed, skipping: $pkg" ||
            to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    yay -S --needed --noconfirm "${to_install[@]}"
}

flatpak_install() {
    command -v flatpak &>/dev/null || {
        error "flatpak is not installed"
        return 1
    }
    local to_install=()
    for app in "$@"; do
        flatpak info "$app" &>/dev/null &&
            warn "Already installed, skipping: $app" ||
            to_install+=("$app")
    done
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    flatpak install -y --noninteractive flathub "${to_install[@]}"
}

# -- systemd 服务 -------------------------------------------------------------

# enable_system_service <service>
#   幂等地 enable 一个 system 级 unit（需要 sudo / root）。
enable_system_service() {
    local svc="$1"
    if systemctl is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    else
        sudo systemctl enable "$svc" &&
            success "$svc enabled" ||
            warn "$svc could not be enabled"
    fi
}

# enable_user_service <service>
#   幂等地 enable 一个 user 级 unit（不需要 root）。
enable_user_service() {
    local svc="$1"
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    else
        systemctl --user enable "$svc" 2>/dev/null &&
            success "$svc enabled" ||
            warn "$svc could not be enabled (no systemd user session?)"
    fi
}

# switch_display_manager <service>
#   切换 display manager：移除旧的 display-manager.service 软链接后 enable 新服务。
#   systemd 约定多个 DM 竞争同一个 display-manager.service 别名，
#   直接 enable 时若旧链接已存在会报错，需先清除。
switch_display_manager() {
    local svc="$1"
    sudo rm -f /etc/systemd/system/display-manager.service
    enable_system_service "$svc"
}

# -- 文件工具 -----------------------------------------------------------------

command_exists() { command -v "$1" &>/dev/null; }

# git_clone <dest> <url> [额外 git 参数...]
#   --depth=1 克隆，失败最多重试 3 次。
git_clone() {
    local dest="$1" url="$2"
    shift 2
    if [[ -d "$dest/.git" ]]; then
        warn "Already cloned, skipping: $dest"
        return 0
    fi
    local attempt
    for attempt in 1 2 3; do
        git clone --depth=1 "$@" "$url" "$dest" && break
        warn "git clone failed (attempt $attempt/3), retrying in 3s..."
        rm -rf "$dest"
        sleep 3
    done
    [[ -d "$dest/.git" ]] || {
        error "git clone failed after 3 attempts: $url"
        return 1
    }
    success "Cloned: $dest"
}

# copy_config <src> <dest>
#   自动创建父目录。
copy_config() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Copied: $dest"
}
