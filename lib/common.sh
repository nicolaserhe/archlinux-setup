#!/usr/bin/env bash
# =============================================================================
# lib/common.sh -- 包安装 / 通用工具函数
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

enable_user_service() {
    local svc="$1"
    # 补全 XDG_RUNTIME_DIR，保证新用户 / runuser 场景下 systemctl --user 可用
    ensure_xdg_runtime_dir
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    else
        systemctl --user enable "$svc" 2>/dev/null &&
            success "$svc enabled" ||
            warn "$svc could not be enabled (no systemd user session?)"
    fi
}

# add_user_service_wants <unit> <wanted-by-unit>
# 通过直接创建 .wants/ 软链接，将 <unit> 挂到 <wanted-by-unit> 下。
# 不依赖 D-Bus / 活跃的用户会话，在 runuser 安装场景中始终可用。
# 软链接的目标按优先级搜索：用户配置目录 > 包安装目录。
add_user_service_wants() {
    local unit="$1" wanted_by="$2"
    local wants_dir="$HOME/.config/systemd/user/${wanted_by}.wants"
    local unit_path=""

    # 按优先级搜索 unit 文件
    local search_dirs=(
        "$HOME/.config/systemd/user"
        "$HOME/.local/share/systemd/user"
        /etc/systemd/user
        /usr/lib/systemd/user
        /usr/local/lib/systemd/user
    )
    for dir in "${search_dirs[@]}"; do
        if [[ -f "$dir/$unit" ]]; then
            unit_path="$dir/$unit"
            break
        fi
    done

    if [[ -z "$unit_path" ]]; then
        warn "Unit file not found: $unit (searched ${search_dirs[*]})"
        warn "  $unit will NOT be linked to ${wanted_by}.wants/ -- enable manually after first login"
        return 0
    fi

    mkdir -p "$wants_dir"
    ln -sf "$unit_path" "$wants_dir/$unit"
    success "Linked $unit -> ${wanted_by}.wants/"
}

switch_display_manager() {
    local svc="$1"
    sudo rm -f /etc/systemd/system/display-manager.service
    enable_system_service "$svc"
}

# -- 文件工具 -----------------------------------------------------------------

command_exists() { command -v "$1" &>/dev/null; }

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

copy_config() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Copied: $dest"
}
