#!/usr/bin/env bash
# =============================================================================
# install.sh -- 安装入口（以 root 运行）
#
# 用法: sudo bash install.sh
#
# 执行顺序：
#   1. 用户创建 / 选择
#   2. pacman 包
#   3. 临时免密 sudo（供 user-phase 使用）
#   4. 安装代理工具 mihomo
#   5. 启用 linger（让 systemd-logind 为目标用户创建运行时目录）
#   6. 移交 repo 所有权给 TARGET_USER
#   7. user-phase（AUR、Flatpak、配置）<-- 以 TARGET_USER 身份运行
#   8. 清理（sudo 规则 + mihomo）       <-- trap 保证必定执行
# =============================================================================

# 加 -e：非 run_step 管控的命令失败时立即退出，避免静默继续
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/proxy.sh"

# -- 前置检查 -----------------------------------------------------------------
[[ $EUID -eq 0 ]]          || die "Please run as root: sudo bash install.sh"
[[ -f /etc/arch-release ]] || die "Arch Linux environment not detected"

echo -e "${BOLD}"
echo "  Arch Linux Personal Setup"
echo -e "${RESET}"

# TARGET_USER 在 _step_user 中赋值，trap 内通过 ${TARGET_USER:-} 守卫
TARGET_USER=""

# -- 共用：清除上次运行残留的临时状态 -----------------------------------------
# 预清理与退出清理共用，避免重复维护两份 path 列表
_clean_tmp_state() {
    set +e
    pkill -9 mihomo 2>/dev/null
    rm -f /etc/sudoers.d/install-tmp
    rm -f "$MIHOMO_PID_FILE" "$MIHOMO_LOG_FILE"
    rm -rf /tmp/yay-build.* /tmp/rime-ice.* /tmp/dms-plugins.*
    set -e
}

# -- 全局清理 -----------------------------------------------------------------
_cleanup() {
    # trap 内禁用 -e，避免某条清理命令失败打断后续步骤
    set +e
    header "Cleanup"

    rm -f /etc/sudoers.d/install-tmp \
        && success "Temporary sudoers rule removed"

    pkill -9 mihomo 2>/dev/null
    if pacman -Q mihomo &>/dev/null; then
        if pacman -Rns --noconfirm mihomo 2>/dev/null; then
            success "mihomo uninstalled"
        else
            warn "mihomo uninstall failed -- please remove manually"
        fi
    fi

    if [[ -n "${TARGET_USER}" ]]; then
        local user_home
        user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
        if [[ -n "$user_home" ]]; then
            rm -rf "$user_home/.config/mihomo"
            success "mihomo config cleaned"
        fi
    fi

    rm -f "$MIHOMO_PID_FILE" "$MIHOMO_LOG_FILE"
    rm -rf /tmp/yay-build.* /tmp/rime-ice.* /tmp/dms-plugins.*
}
trap '_cleanup; print_summary' EXIT

_clean_tmp_state
success "Pre-cleanup done"

# -- Step 1: 用户选择 / 创建 --------------------------------------------------
_step_user() {
    TARGET_USER="$(bash "$REPO_DIR/scripts/setup-user.sh")"
    [[ -n "$TARGET_USER" ]] || { error "Failed to get a valid username"; return 1; }
    export TARGET_USER
}
run_step "User setup" _step_user || exit 1

# -- Step 2: pacman 包 --------------------------------------------------------
run_step "pacman packages" bash "$REPO_DIR/scripts/packages/pacman.sh" || exit 1

# -- Step 3: 临时免密 sudo ----------------------------------------------------
_step_sudo() {
    setup_sudo
    setup_temp_nopasswd_sudo
}
run_step "sudo config" _step_sudo || exit 1

# -- Step 4: 安装代理工具（仅安装期间使用，退出时由 trap 卸载）----------------
run_step "Proxy tool" pacman -S --noconfirm --needed mihomo || exit 1

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
    while [[ ! -d "$runtime" ]] && (( elapsed < 10 )); do
        sleep 1
        (( elapsed++ )) || true
    done

    if [[ -d "$runtime" ]]; then
        success "Runtime dir ready: $runtime"
    else
        warn "Runtime dir $runtime not created within 10s -- user services may need re-enabling at first login"
    fi
}
# 非致命：缺 linger 时退化到首次登录后手动处理
run_step "User linger" _step_linger || true

# -- Step 6: 移交 repo 所有权 -------------------------------------------------
run_step "Repo ownership" \
    chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR" || exit 1

# -- Step 7: 用户阶段 ---------------------------------------------------------
# REPO_DIR 用单引号包裹，防止路径中含空格时 runuser -c 的内层参数断裂
run_step "User phase" \
    runuser -l "$TARGET_USER" -c "bash '${REPO_DIR}/scripts/user-phase.sh' '${REPO_DIR}'" \
    || exit 1

# trap EXIT 自动执行 _cleanup + print_summary
