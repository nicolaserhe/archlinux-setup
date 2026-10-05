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
# 私有：单次 clone 尝试，被 retry 调用。
# 抽到模块顶层是为了避免 nested function 污染全局命名空间 + 拿不到 dynamic
# scoping 的隐式依赖（bash 没有真正的 local function）。
# shellcheck disable=SC2329 # called indirectly via `retry _git_clone_attempt ...`
_git_clone_attempt() {
    local dest="$1" url="$2"
    shift 2
    rm -rf "$dest"
    git clone --depth=1 "$@" "$url" "$dest"
}

# git_clone <dest> <url> [extra git args...]
git_clone() {
    local dest="$1" url="$2"
    shift 2

    # 空字符串校验：rm -rf "" 本身不删 /，但 mkdir/git clone 行为模糊；
    # 早 fail 比沉默执行更易调试
    [[ -n "$dest" ]] || die "git_clone: dest is empty"
    [[ -n "$url" ]] || die "git_clone: url is empty"

    if [[ -d "$dest/.git" ]]; then
        warn "Already cloned, skipping: $dest"
        return 0
    fi

    # 父目录缺失会让 git clone 报错 "could not create work tree"
    mkdir -p "$(dirname "$dest")"

    if retry 3 3 _git_clone_attempt "$dest" "$url" "$@"; then
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

# -- 文本追加（幂等） --------------------------------------------------------
# append_block_once <file> <marker> < heredoc
#
# 把 stdin 内容追加到 file 末尾，但仅当 file 中不含 marker 子串时。
# marker 是"判断是否已追加过"的指纹（用块内任意一行唯一字符串即可）。
# 追加前自动插入一个空行作为视觉分隔。
#
# 用例：dms.sh 多次往 niri config.kdl 追加 include / layer-rule 等块。
append_block_once() {
    local file="$1" marker="$2"
    [[ -n "$file" ]] || die "append_block_once: file is empty"
    [[ -n "$marker" ]] || die "append_block_once: marker is empty"

    if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
        warn "Already present, skipping append: $marker"
        return 0
    fi

    mkdir -p "$(dirname "$file")"
    printf '\n' >> "$file"
    cat >> "$file"
    success "Appended block to $file"
}

# -- 删除含指定字面量的行 -----------------------------------------------------
# remove_lines_containing <file> <literal>
#
# 就地删除所有含该字面量的行。用途：迁移清理历史版本 append_block_once 写下的块。
# append_block_once 是单向的（没有对应的移除函数），且它按 marker 判断"是否已追加"，
# 当整个功能被弃用时，旧机器上的残留块必须显式删掉 —— 否则它会一直生效。
remove_lines_containing() {
    local file="$1" literal="$2"
    # 空字面量能匹配所有行 —— 不挡的话会把整个文件清空。跟 append_block_once
    # 的空 marker 守卫保持同一标准。（set -u 只挡 unset，不挡空串。）
    [[ -n "$literal" ]] || die "remove_lines_containing: literal is empty"
    # 空路径会一路走到 [[ -f "" ]] 为假然后 return 0：调用方看到"成功"，实际
    # 什么都没做，迁移静默失效。append_block_once / git_clone 对空参数都是 die。
    [[ -n "$file" ]] || die "remove_lines_containing: file is empty"
    # 目录同样会被 [[ -f ]] 判假然后静默 return 0。这跟"文件不存在"不是一回事
    # （后者是幂等跳过），传目录属于调用方写错了，必须响。
    if [[ -d "$file" ]]; then
        die "remove_lines_containing: not a regular file: $file"
    fi
    # literal 带换行时 grep -F 会按多模式处理（等于多个 -e），一次删掉好几类行
    # 而且不留痕迹。调用点都是单行字面量，直接在入口堵死。
    if [[ "$literal" == *$'\n'* ]]; then
        die "remove_lines_containing: literal contains a newline"
    fi
    [[ -f "$file" ]] || return 0

    # grep 退出码：0 有匹配，1 无匹配，>1 是 I/O 错误。只有 1 是正常路径 ——
    # 把 >1 也当"无匹配"会让迁移在文件不可读时悄悄不生效，留在机器上的
    # valent spawn 行永远不会被清掉。
    local rc=0
    grep -qF -- "$literal" "$file" || rc=$?
    if ((rc == 1)); then
        return 0
    elif ((rc > 1)); then
        die "remove_lines_containing: grep failed (exit $rc) on $file"
    fi

    local tmp
    tmp="$(mktemp)"
    rc=0
    # 全文件都匹配时 grep -v 无输出、退出码 1，这是正常结果（文件被清空到零行）
    grep -vF -- "$literal" "$file" >"$tmp" || rc=$?
    if ((rc > 1)); then
        rm -f "$tmp"
        die "remove_lines_containing: grep failed (exit $rc) on $file"
    fi

    # 用 cat 覆盖而不是 mv：保持原 inode 与权限位。mktemp 建出来的是 600，
    # mv 过去会把配置文件降成 600。代价是有一个极短的截断窗口（写失败时
    # 目标已被截断）——比换掉权限位可接受。写失败时顺手收掉临时文件，
    # 否则 set -e 直接退出，rm 那行永远轮不到。
    if ! cat "$tmp" >"$file"; then
        rm -f "$tmp"
        die "remove_lines_containing: failed to write $file"
    fi
    rm -f "$tmp"
    success "Removed lines containing: $literal"
}

# -- 组管理 -------------------------------------------------------------------
# add_user_to_group <user> <group>: 用户已在组内则跳过
add_user_to_group() {
    local user="$1" group="$2"
    if id -nG "$user" | grep -qw "$group"; then
        warn "Already in group $group, skipping: $user"
    else
        _as_root usermod -aG "$group" "$user"
        success "Added $user to group $group (re-login to apply)"
    fi
}
