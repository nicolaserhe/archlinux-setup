#!/usr/bin/env bash
# =============================================================================
# lib/fs.sh -- 文件系统、Git、sudo、用户/组管理助手
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
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/install-tmp
    chmod 440 /etc/sudoers.d/install-tmp
    success "Temporary passwordless sudo configured"
}

# -- Git 克隆 -----------------------------------------------------------------
# git_clone <dest> <url> [extra git args...]
git_clone() {
    local dest="$1" url="$2"
    shift 2

    if [[ -d "$dest/.git" ]]; then
        warn "Already cloned, skipping: $dest"
        return 0
    fi

    # 父目录缺失会让 git clone 报错 "could not create work tree"
    mkdir -p "$(dirname "$dest")"

    _do_clone() {
        rm -rf "$dest"
        git clone --depth=1 "$@" "$url" "$dest"
    }

    if retry 3 3 _do_clone "$@"; then
        success "Cloned: $dest"
    else
        error "git clone failed after 3 attempts: $url"
        return 1
    fi
}

# -- 配置文件复制 -------------------------------------------------------------
# copy_config <src> <dest>
copy_config() {
    local src="$1" dest="$2"

    # 缺失源文件时静默 cp 会成功复制 0 字节，必须显式校验
    [[ -f "$src" ]] || die "Source config not found: $src"

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Copied: $dest"
}

# -- 资源文件查找 -------------------------------------------------------------
# find_asset <dir> <name-glob>: 在 dir 顶层按通用图片后缀匹配，按字典序取第一个
find_asset() {
    local dir="$1" pattern="$2"
    find "$dir" -maxdepth 1 \( \
        -iname "*.jpg" -o -iname "*.jpeg" \
        -o -iname "*.png" -o -iname "*.webp" \
        \) -name "$pattern" 2>/dev/null | sort | head -1
}

# -- 组管理 -------------------------------------------------------------------
# add_user_to_group <user> <group>: 用户已在组内则跳过
add_user_to_group() {
    local user="$1" group="$2"
    if id -nG "$user" | grep -qw "$group"; then
        warn "Already in group $group, skipping: $user"
    else
        sudo usermod -aG "$group" "$user"
        success "Added $user to group $group (re-login to apply)"
    fi
}
