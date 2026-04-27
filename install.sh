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
#   5. user-phase（AUR、Flatpak、配置）<- 以 TARGET_USER 身份运行
#   6. 清理（sudo 规则 + mihomo）      <- trap 保证必定执行
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

    # 卸载 mihomo（仅安装期间临时使用）
    pkill -9 mihomo 2>/dev/null || true
    if pacman -Q mihomo &>/dev/null; then
        pacman -Rns --noconfirm mihomo 2>/dev/null &&
            success "mihomo uninstalled" ||
            warn "mihomo uninstall failed -- please remove manually"
    fi

    # 清理用户目录下的 mihomo 运行时配置
    if [[ -n "${TARGET_USER:-}" ]]; then
        local user_home
        user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || true)"
        if [[ -n "$user_home" ]]; then
            rm -rf "$user_home/.config/mihomo"
            success "mihomo config cleaned"
        fi
    fi

    # 清理安装过程中产生的临时文件
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
run_step "pacman packages" bash "$REPO_DIR/scripts/packages/pacman.sh"

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

# -- Step 5: 用户阶段 ---------------------------------------------------------
run_step "User phase" \
    runuser -l "$TARGET_USER" -c "bash '$REPO_DIR/scripts/user-phase.sh' '$REPO_DIR'"

# trap EXIT 自动执行 _cleanup + print_summary
