#!/usr/bin/env bash
# =============================================================================
# lib/fs.sh -- 文件系统、Git、sudo 配置助手
#
# 依赖：lib/utils.sh
# =============================================================================

[[ -n "${_FS_LOADED:-}" ]] && return 0
_FS_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/fs.sh" >&2
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
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/install-tmp
    chmod 440 /etc/sudoers.d/install-tmp
    success "Temporary passwordless sudo configured"
}

# -- 命令检测 -----------------------------------------------------------------

command_exists() { command -v "$1" &>/dev/null; }

# -- Git 克隆（最多重试 3 次）-------------------------------------------------
# git_clone <dest> <url> [extra git flags...]
git_clone() {
    local dest="$1" url="$2"
    shift 2

    if [[ -d "$dest/.git" ]]; then
        warn "Already cloned, skipping: $dest"
        return 0
    fi

    # BUG FIX: 确保父目录存在，否则 git clone 会因路径不存在而报错
    mkdir -p "$(dirname "$dest")"

    local attempt
    for attempt in 1 2 3; do
        git clone --depth=1 "$@" "$url" "$dest" && break
        warn "git clone failed (attempt $attempt/3), retrying in 3s..."
        rm -rf "$dest"
        sleep 3
    done

    if [[ ! -d "$dest/.git" ]]; then
        error "git clone failed after 3 attempts: $url"
        return 1
    fi
    success "Cloned: $dest"
}

# -- 配置文件复制 -------------------------------------------------------------
# copy_config <src> <dest>
copy_config() {
    local src="$1" dest="$2"

    # BUG FIX: 原版未校验源文件是否存在，缺失时会静默复制失败
    if [[ ! -f "$src" ]]; then
        error "Source config not found: $src"
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Copied: $dest"
}
