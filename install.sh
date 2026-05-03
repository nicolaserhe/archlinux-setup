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
#   6. user-phase（AUR、Flatpak、配置）<- 以 TARGET_USER 身份运行
#   7. 清理（sudo 规则 + mihomo）      <- trap 保证必定执行
# =============================================================================

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

# -- 前置检查 -----------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Please run as root: sudo bash install.sh"
[[ -f /etc/arch-release ]] || die "Arch Linux environment not detected"

echo -e "${BOLD}"
echo "  Arch Linux Personal Setup"
echo -e "${RESET}"

# -- 全局清理（trap 保证无论如何都会执行）-------------------------------------
_cleanup() {
    header "Cleanup"

    rm -f /etc/sudoers.d/install-tmp &&
        success "Temporary sudoers rule removed"

    pkill -9 mihomo 2>/dev/null || true
    if pacman -Q mihomo &>/dev/null; then
        pacman -Rns --noconfirm mihomo 2>/dev/null &&
            success "mihomo uninstalled" ||
            warn "mihomo uninstall failed -- please remove manually"
    fi

    if [[ -n "${TARGET_USER:-}" ]]; then
        local user_home
        user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || true)"
        if [[ -n "$user_home" ]]; then
            rm -rf "$user_home/.config/mihomo"
            success "mihomo config cleaned"
        fi
    fi

    rm -f /tmp/mihomo-bootstrap.pid /tmp/mihomo-bootstrap.log
    rm -rf /tmp/yay-build.* /tmp/rime-ice.*
}
trap '_cleanup; print_summary' EXIT

# -- 预清理（清除上次运行残留）------------------------------------------------
_pre_cleanup() {
    pkill -9 mihomo 2>/dev/null || true
    rm -f /etc/sudoers.d/install-tmp
    rm -f /tmp/mihomo-bootstrap.pid /tmp/mihomo-bootstrap.log
    rm -rf /tmp/yay-build.* /tmp/rime-ice.*
    success "Pre-cleanup done"
}
_pre_cleanup

# -- Step 1: 用户选择 / 创建 --------------------------------------------------
_step_user() {
    TARGET_USER="$(bash "$REPO_DIR/scripts/setup-user.sh")"
    export TARGET_USER
    [[ -n "$TARGET_USER" ]] || {
        error "Failed to get a valid username"
        return 1
    }
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
_step_mihomo() {
    pacman -S --noconfirm --needed mihomo
}
run_step "Proxy tool" _step_mihomo || exit 1

# -- Step 5: 启用 linger，让 systemd-logind 为目标用户建好运行时目录 ----------
# loginctl enable-linger 使 systemd 在用户未登录时也维护其用户会话，
# 副作用是立即创建 /run/user/<uid>，保证后续 systemctl --user 可用。
_step_linger() {
    local uid runtime
    uid="$(id -u "$TARGET_USER")"
    runtime="/run/user/$uid"

    loginctl enable-linger "$TARGET_USER" &&
        success "Linger enabled for $TARGET_USER (UID $uid)" ||
        {
            warn "loginctl enable-linger failed -- user services may need re-enabling at first login"
            return 0
        }

    # 等待 systemd-logind 创建运行时目录（通常 < 1s）
    local elapsed=0
    while [[ ! -d "$runtime" ]] && ((elapsed < 10)); do
        sleep 1
        ((elapsed++))
    done

    if [[ -d "$runtime" ]]; then
        success "Runtime dir ready: $runtime"
    else
        warn "Runtime dir $runtime not created within 10s -- user services may need re-enabling at first login"
    fi
}
run_step "User linger" _step_linger || true # 非致命：没有 linger 时退化到首次登录后手动处理

# -- Step 6: 用户阶段 ---------------------------------------------------------
run_step "User phase" \
    runuser -l "$TARGET_USER" -c "bash '$REPO_DIR/scripts/user-phase.sh' '$REPO_DIR'" ||
    exit 1

# trap EXIT 自动执行 _cleanup + print_summary
