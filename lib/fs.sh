#!/usr/bin/env bash
# =============================================================================
# lib/fs.sh -- 文件系统、Git、sudo、用户/组管理助手
#
# 依赖：lib/utils.sh
# =============================================================================

[[ -n "${_FS_LOADED:-}" ]] && return 0
_FS_LOADED=1

# 本库自己的位置 —— 供 copy_config_merge 定位 lib/helpers/ 下的 Python helper。
# 不用调用方的 $REPO_DIR：函数库不该依赖调用方先设好哪个全局变量。
_FS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# setup_temp_nopasswd_sudo <user> —— install 期间给**单个用户**临时免密
#
# 不写 `%wheel`：这条规则的有效期是整个安装过程（十几分钟，期间系统还在从
# archlinuxcn / AUR 拉包），而 wheel 组在那台机器上是谁不由本脚本决定。只授
# `$TARGET_USER` 一个账户，爆炸半径就是这次安装本身。用户名先按 Linux 用户
# 名规则校验 —— 它是拼进 sudoers 的一行文本，畸形值能改写文件语法。
setup_temp_nopasswd_sudo() {
    local user="${1:?setup_temp_nopasswd_sudo: user required}"

    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        die "setup_temp_nopasswd_sudo: refused suspicious username: '$user'"

    echo "$user ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/install-tmp
    chmod 440 /etc/sudoers.d/install-tmp
    success "Temporary passwordless sudo configured for $user"
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

    # 走到这里 = dest 不是 git checkout，而 _git_clone_attempt 的第一条命令是
    # `rm -rf "$dest"`。空目录 / 不存在才是正常路径；非空说明用户在那儿放了
    # 别的东西（调用点里有 ~/.config/nvim 这种位置），静默删掉是不可接受的。
    # 直接 die，把选择权交回给人：确认无用就自己挪走再重跑。
    if [[ -e "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        die "git_clone: $dest exists, is not a git checkout, and is not empty -- refusing to overwrite it (move it away and re-run)"
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

# -- 配置文件部署（归属感知） -------------------------------------------------
#
# 每一处部署都必须显式声明"谁拥有目标文件"，归属由调用哪个函数决定 —— 仓库里
# 没有第二份归属清单要维护（曾有过 config-map.md 那种文档，它自己就会腐烂）。
# `scripts/checks/drift-check.sh`（`just drift`）反过来扫这些调用点，得出
# "仓库 ↔ 本机"的归属表和漂移结论。
#
#   copy_config / copy_config_dir / install_config / install_config_root
#       仓库拥有（own）：每次安装无条件覆盖。本机上同名文件与仓库不一致 = 漂移。
#   copy_config_seed
#       仅首次播种（seed）：目标已存在就跳过，之后由运行时程序接管 —— 它改它、
#       重写它、给它加注释都是正常的。漂移检查只关心文件还在不在，不比对内容。
#   copy_config_merge
#       共同拥有（merge）：仓库只贡献若干键，运行时程序同时也在写同一个文件。

# copy_config <src> <dest> —— 仓库拥有，无条件覆盖
copy_config() {
    local src="$1" dest="$2"

    # 缺失源文件时静默 cp 会成功复制 0 字节，必须显式校验
    [[ -f "$src" ]] || die "Source config not found: $src"

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Copied: $dest"
}

# copy_config_seed <src> <dest> —— 仅首次播种；已存在则完全不动
copy_config_seed() {
    local src="$1" dest="$2"
    [[ -f "$src" ]] || die "Source config not found: $src"

    if [[ -e "$dest" ]]; then
        warn "Already exists (runtime-owned after seeding), skipping: $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Seeded: $dest"
}

# copy_config_merge <src> <dest> —— 共同拥有；**只有 merge 一条路径**
#
# 历史上这段 if/else 写在 dms.sh 里：只在 merge 分支声明归属的话，dest 不存在
# 时会落到 copy 分支，同一对文件出现两种归属结论。搬进库里之后，两条分支仍在
# —— 而它们结果并不一样：`cp` 会把 src 整体抄过去，包括顶层 `__doc__` 这类只对
# merge 语义有意义的键。所以这里统一成"dest 不在就先放一个空 object，然后一律
# merge"，结论与产物都只有一种。
copy_config_merge() {
    local src="$1" dest="$2"
    [[ -f "$src" ]] || die "Source config not found: $src"

    if [[ ! -f "$dest" ]]; then
        mkdir -p "$(dirname "$dest")"
        printf '{}\n' >"$dest"
        info "Merge target absent, starting from an empty object: $dest"
    fi

    # 保留 dest 里运行时程序自己写的键，只把 src 的键 merge 进去
    python3 "$_FS_LIB_DIR/helpers/merge-json-deep.py" "$dest" "$src"
    success "Merged: $dest"
}

# copy_config_dir <src-dir> <dest-dir> —— 仓库拥有，目录内每个普通文件
# 逐一部署（不递归子目录）。用例：matugen 模板集。
copy_config_dir() {
    local src="$1" dest="$2"
    [[ -d "$src" ]] || die "Source config dir not found: $src"

    local f
    # 无匹配时 glob 原样保留，"$f" 不是普通文件即跳过（不开 nullglob：
    # 开了会影响调用方的 glob 语义）
    for f in "$src"/*; do
        [[ -f "$f" ]] || continue
        copy_config "$f" "$dest/$(basename "$f")"
    done
}

# install_config <src> <dest> <perm> —— 仓库拥有 + 显式权限位（无 .sh 后缀的
# 可执行 helper 脚本走这条，cp 会丢执行位）
install_config() {
    local src="$1" dest="$2" perm="${3:-}"
    [[ -f "$src" ]] || die "Source config not found: $src"
    [[ -n "$perm" ]] || die "install_config: perm is empty"

    install -Dm"$perm" "$src" "$dest"
    success "Installed ($perm): $dest"
}

# install_config_root <src> <dest> <perm> —— 同上，目标是 /etc 等 root 拥有的路径
install_config_root() {
    local src="$1" dest="$2" perm="${3:-}"
    [[ -f "$src" ]] || die "Source config not found: $src"
    [[ -n "$perm" ]] || die "install_config_root: perm is empty"

    _as_root install -Dm"$perm" "$src" "$dest"
    success "Installed ($perm, root): $dest"
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

# append_block_once_root <file> <marker> < heredoc
#
# 同上，但目标是 /etc 这类 root 拥有的文件 —— 普通用户的 `>>` 写不进去，改走
# _as_root tee。marker 判断仍用 grep（这些文件通常 world-readable），所以读取
# 不需要提权，只有写入需要。
#
# 用例：memory.sh 往 /etc/fstab 追加 swapfile 那一行。
append_block_once_root() {
    local file="$1" marker="$2"
    [[ -n "$file" ]] || die "append_block_once_root: file is empty"
    [[ -n "$marker" ]] || die "append_block_once_root: marker is empty"

    if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
        warn "Already present, skipping append: $marker"
        return 0
    fi

    _as_root mkdir -p "$(dirname "$file")"
    printf '\n' | _as_root tee -a "$file" >/dev/null
    _as_root tee -a "$file" >/dev/null
    success "Appended block to $file (root)"
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
