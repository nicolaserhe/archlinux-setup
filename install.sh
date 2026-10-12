#!/usr/bin/env bash
# =============================================================================
# install.sh -- 安装入口（以 root 运行）
#
# 用法: bash install.sh
#
# 执行顺序：
#   1. 用户创建 / 选择
#   2. pacman 基础包（core/pacman-base.sh）
#   3. 临时免密 sudo（供 user-phase 使用）
#   4. 安装代理工具 mihomo
#   5. 启用 linger（让 systemd-logind 为目标用户创建运行时目录）
#   6. 移交 repo 所有权给 TARGET_USER
#   7. user-phase（core/* + apps/*）<-- 以 TARGET_USER 身份运行
#   8. 清理（sudo 规则 + mihomo）   <-- trap 保证必定执行
# =============================================================================

# -Ee：非 run_step 管控的命令失败时立即退出 + 触发 lib/utils.sh 的 ERR trap
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/proxy.sh"

# runuser -c 用单引号包内层参数；REPO_DIR 含单引号会断裂
[[ "$REPO_DIR" != *\'* ]] || die "REPO_DIR contains single quote: $REPO_DIR"

mkdir -p "$REPO_DIR/log"
LOG_FILE="$REPO_DIR/log/install-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

# 慢机器（树莓派 / 虚拟机）调大；linger 后 /run/user/<uid> 出现需要的最长秒数
LINGER_TIMEOUT=10

# -- 前置检查 -----------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Please run as root: bash install.sh"
[[ -f /etc/arch-release ]] || die "Arch Linux environment not detected"

header "Network check"
if ! ping -c 1 -W 3 baidu.com &>/dev/null; then
    die "Network is not reachable -- please check your connection"
fi
success "Network OK"

echo -e "${BOLD}"
echo "  Arch Linux Personal Setup"
echo -e "${RESET}"

# TARGET_USER 在 _step_user 中赋值，trap 内通过 ${TARGET_USER:-} 守卫
TARGET_USER=""

# -- mihomo 的"装卸前状态"------------------------------------------------------
# _cleanup 只回滚本脚本自己造成的变化，所以这些必须在 trap 生效前就存在：
#   _MIHOMO_PKG_PREEXISTING=1  机器上本来就有 mihomo 包（不是我们装的）→ 不卸
#   _MIHOMO_CFG_BACKUP          用户原有 ~/.config/mihomo 被挪到的位置 → 装完搬回
_MIHOMO_PKG_PREEXISTING=0
_MIHOMO_CFG_BACKUP=""
_MIHOMO_CFG_DIR=""

# -- 共用：用 PID 文件杀 mihomo（不用 pkill 避免误杀机器上其他 mihomo 实例）---
_kill_mihomo_by_pidfile() {
    [[ -f "$MIHOMO_PID_FILE" ]] || return 0
    local pid
    pid="$(cat "$MIHOMO_PID_FILE" 2>/dev/null)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$MIHOMO_PID_FILE"
}

# -- 共用：清除上次运行残留的临时状态 -----------------------------------------
# 预清理与退出清理共用，避免重复维护两份 path 列表
_clean_tmp_state() {
    set +e
    _kill_mihomo_by_pidfile
    rm -f /etc/sudoers.d/install-tmp
    rm -f "$MIHOMO_LOG_FILE"
    rm -rf /tmp/yay-build.* /tmp/dms-plugins.* /tmp/grub-matter.*
    set -e
}

# -- 全局清理 -----------------------------------------------------------------
_cleanup() {
    # trap 内禁用 -e，避免某条清理命令失败打断后续步骤
    set +e
    header "Cleanup"

    if [[ -f /etc/sudoers.d/install-tmp ]]; then
        if rm -f /etc/sudoers.d/install-tmp; then
            success "Temporary sudoers rule removed"
        else
            warn "Failed to remove /etc/sudoers.d/install-tmp -- remove it manually before next run"
        fi
    fi

    _kill_mihomo_by_pidfile

    # 只卸"我们装的"。mihomo 在 archlinuxcn（step 2 刚启用该源），用过 Clash 的
    # 机器上很可能本来就有 —— 无条件 `pacman -Rns` 会把用户自己的包拆掉。
    if ((_MIHOMO_PKG_PREEXISTING == 1)); then
        success "mihomo was already installed before this run -- left in place"
    elif pacman -Q mihomo &>/dev/null; then
        if pacman -Rns --noconfirm mihomo 2>/dev/null; then
            success "mihomo uninstalled"
        else
            warn "mihomo uninstall failed -- please remove manually"
        fi
    fi

    # 配置目录同理：装之前有就搬回去（原样还原），装之前没有才删。
    if [[ -n "$_MIHOMO_CFG_BACKUP" && -d "$_MIHOMO_CFG_BACKUP" ]]; then
        rm -rf "$_MIHOMO_CFG_DIR"
        if mv "$_MIHOMO_CFG_BACKUP" "$_MIHOMO_CFG_DIR"; then
            success "Restored original ~/.config/mihomo"
        else
            warn "Failed to restore ~/.config/mihomo from $_MIHOMO_CFG_BACKUP -- move it back manually"
        fi
    elif [[ -n "$TARGET_USER" ]]; then
        local user_home
        user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
        if [[ -n "$user_home" && -d "$user_home/.config/mihomo" ]]; then
            if rm -rf "$user_home/.config/mihomo"; then
                success "mihomo config cleaned"
            else
                warn "Failed to clean $user_home/.config/mihomo -- remove it manually"
            fi
        fi
    fi

    # mihomo log + /tmp/* 残留：复用 _clean_tmp_state，避免在 pre-flight 与
    # cleanup 两处重复维护同一份 path 列表
    _clean_tmp_state
}
# INT/TERM 转成 exit 让 EXIT trap 只跑一次（trap INT 后 bash 退出会再触发 EXIT，
# 显式 exit 设定退出码可观察 -- 130=Ctrl+C, 143=SIGTERM）
trap 'exit 130' INT
trap 'exit 143' TERM
trap '_cleanup; print_summary' EXIT

_clean_tmp_state
success "Pre-cleanup done"

# -- Preflight: 资产 + 冲突检查 ----------------------------------------------
# 缺壁纸/头像/订阅 yaml 时早 fail，避免跑到 step 7 中段才 die
#
# 注意：run_step 一律**不加** `|| exit 1`。bash 规定，被放进 `||`/`&&` 列表的
# 函数，其函数体内（以及它调用的所有函数内）的 errexit 与 ERR trap 全部失效 ——
# 中段某条命令失败会被后面的命令掩盖，run_step 拿到 0 照样打印 "-- done"，而
# 屏幕上既没有 ERR trap 的 `source:line` 也没有中止（shellcheck SC2310）。
# 顶层 set -e 已经保证 run_step 返回非零时立即退出，语义完全一致。
run_step "Preflight" bash "$REPO_DIR/scripts/preflight.sh"

# -- Step 1: 用户选择 / 创建 --------------------------------------------------
_step_user() {
    TARGET_USER="$(bash "$REPO_DIR/scripts/setup-user.sh")"
    [[ -n "$TARGET_USER" ]] || {
        error "Failed to get a valid username"
        return 1
    }
    export TARGET_USER
}
run_step "User setup" _step_user

# -- Step 2: pacman 基础包 ----------------------------------------------------
run_step "pacman base" bash "$REPO_DIR/scripts/core/pacman-base.sh"

# -- Step 3: 临时免密 sudo ----------------------------------------------------
_step_sudo() {
    setup_sudo
    setup_temp_nopasswd_sudo "$TARGET_USER"
}
run_step "sudo config" _step_sudo

# -- Step 4: 安装代理工具（仅安装期间使用，退出时由 trap 卸载）----------------
# 装卸 / 清理都必须在"确实是本脚本造成的"前提下进行，所以先记录装卸前状态：
# 包已存在则退出时不卸；用户已有 ~/.config/mihomo 则先整体挪开（不是删），
# user-phase 期间用仓库订阅现建一份，退出时再把原来那份搬回来。
if pacman -Q mihomo &>/dev/null; then
    _MIHOMO_PKG_PREEXISTING=1
    warn "mihomo 本来就装着（不是本脚本装的）—— 退出时不会卸载它"
fi

if [[ -n "$TARGET_USER" ]]; then
    _MH_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    _MIHOMO_CFG_DIR="${_MH_HOME}/.config/mihomo"
    if [[ -n "$_MH_HOME" && -d "$_MIHOMO_CFG_DIR" ]]; then
        _MIHOMO_CFG_BACKUP="${_MIHOMO_CFG_DIR}.pre-archlinux-setup"
        rm -rf "$_MIHOMO_CFG_BACKUP" # 上次中断留下的，直接换新
        if mv "$_MIHOMO_CFG_DIR" "$_MIHOMO_CFG_BACKUP"; then
            warn "原有 ~/.config/mihomo 已暂存到 $(basename "$_MIHOMO_CFG_BACKUP")，安装结束后还原"
        else
            warn "暂存原有 ~/.config/mihomo 失败 —— 本次安装会覆盖它"
            _MIHOMO_CFG_BACKUP=""
        fi
    fi
fi

run_step "Proxy tool" pacman_install mihomo

# -- Step 5: 启用 linger，让 systemd-logind 为目标用户建好运行时目录 ----------
_step_linger() {
    local uid runtime
    uid="$(id -u "$TARGET_USER")"
    runtime="/run/user/$uid"

    if loginctl enable-linger "$TARGET_USER"; then
        success "Linger enabled for $TARGET_USER (UID $uid)"
    else
        warn "loginctl enable-linger failed -- user services may need re-enabling at first login"
        return 0
    fi

    local elapsed=0
    while [[ ! -d "$runtime" ]] && ((elapsed < LINGER_TIMEOUT)); do
        sleep 1
        ((elapsed++)) || true
    done

    if [[ -d "$runtime" ]]; then
        success "Runtime dir ready: $runtime"
    else
        warn "Runtime dir $runtime not created within ${LINGER_TIMEOUT}s -- user services may need re-enabling at first login"
    fi
}
# 非致命：缺 linger 时退化到首次登录后手动处理。这里的 `|| true` 是刻意保留的 ——
# 它同时关掉 _step_linger 体内的 errexit（见上面那条注释），而这正是本步想要的：
# 函数内部自己 warn 后 return 0，不该因为某条 loginctl 失败就中断整个安装。
run_step "User linger" _step_linger || true

# -- Step 6: 移交 repo 所有权 -------------------------------------------------
run_step "Repo ownership" \
    chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR"

# -- Step 7: 用户阶段 ---------------------------------------------------------
# REPO_DIR 用单引号包裹，防止路径中含空格时 runuser -c 的内层参数断裂
run_step "User phase" \
    runuser -l "$TARGET_USER" -c "bash '${REPO_DIR}/scripts/user-phase.sh' '${REPO_DIR}'"

# trap EXIT 自动执行 _cleanup + print_summary
