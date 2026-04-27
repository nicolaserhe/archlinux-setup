#!/usr/bin/env bash
# =============================================================================
# scripts/user-phase.sh -- 用户阶段编排（以 TARGET_USER 身份运行）
#
# 由 install.sh 通过 runuser 调用：
#   runuser -l $TARGET_USER -c "bash scripts/user-phase.sh <repo_dir>"
#
# 也可以单独运行来重新应用所有配置：
#   bash scripts/user-phase.sh /path/to/repo
#
# 步骤顺序（关键）：
#   1. 代理启动    <- 最先，后续 git / yay / flatpak 都需要
#   2. AUR 包
#   3. Flatpak 包
#   4. Shell 配置
#   5. 桌面配置
#   6. Fcitx5 配置
#   7. 代理停止    <- 由 trap 保证，即使中间步骤失败也会执行
# =============================================================================

set -uo pipefail

REPO_DIR="${1:?Usage: bash user-phase.sh <repo_dir>}"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/proxy.sh"

echo -e "${BOLD}"
echo "  User phase: $(whoami)"
echo -e "${RESET}"

# -- trap：退出时必定停止代理并打印摘要 ---------------------------------------
_on_exit() {
    proxy_stop 2>/dev/null || true
    print_summary
}
trap '_on_exit' EXIT

# -- Step 1: 启动代理 ---------------------------------------------------------
# proxy_start 将 http_proxy / https_proxy / all_proxy / no_proxy
# 导出到当前 shell，后续所有子进程（yay、git、flatpak）自动继承。
_step_proxy_start() { proxy_start "$REPO_DIR"; }
run_step "Proxy start" _step_proxy_start || exit 1

# -- Step 2-6: 包 + 配置 ------------------------------------------------------
run_step "AUR packages" bash "$REPO_DIR/scripts/packages/aur.sh"
run_step "Flatpak packages" bash "$REPO_DIR/scripts/packages/flatpak.sh"
run_step "Shell config" bash "$REPO_DIR/scripts/config/shell.sh"
run_step "Desktop config" bash "$REPO_DIR/scripts/config/desktop.sh"
run_step "Fcitx5 config" bash "$REPO_DIR/scripts/config/fcitx.sh"

# trap EXIT 自动调用 _on_exit（proxy_stop + print_summary）
