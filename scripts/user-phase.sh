#!/usr/bin/env bash
# =============================================================================
# scripts/user-phase.sh -- 用户阶段编排（以 TARGET_USER 身份运行）
#
# 由 install.sh 通过 runuser 调用：
#   runuser -l $TARGET_USER -c "bash scripts/user-phase.sh <repo_dir>"
#
# 也可以单独运行来重新应用所有配置：
#   bash scripts/user-phase.sh /path/to/repo
# =============================================================================

set -euo pipefail

REPO_DIR="${1:?Usage: bash user-phase.sh <repo_dir>}"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/proxy.sh"

echo -e "${BOLD}"
echo "  User phase: $(whoami)"
echo -e "${RESET}"

# runuser -l 不建立真正的 systemd 用户会话。
# install.sh 中的 linger 步骤负责创建 /run/user/<uid>，
# 这里将路径导出为环境变量，供后续所有 systemctl --user 调用使用。
ensure_xdg_runtime_dir

# -- trap：退出时必定停止代理并打印摘要 ---------------------------------------
_on_exit() {
    set +e
    proxy_stop 2>/dev/null || true
    print_summary
}
trap '_on_exit' EXIT

# -- Step 1: 启动代理 ---------------------------------------------------------
run_step "Proxy start" proxy_start "$REPO_DIR" || exit 1

# -- Step 2–8: 包 + 配置 ------------------------------------------------------
# 注意：matugen config 必须在 desktop config（含 dms setup）之后运行，
#       才能以追加方式扩展 DMS 生成的 matugen config.toml，而非覆盖。
# kdeconnect 必须在 desktop config 之后运行（需要 niri config.kdl 已存在）。
run_step "AUR packages" bash "$REPO_DIR/scripts/packages/aur.sh"
run_step "Flatpak packages" bash "$REPO_DIR/scripts/packages/flatpak.sh"
run_step "Shell config" bash "$REPO_DIR/scripts/config/shell.sh"
run_step "Desktop config" bash "$REPO_DIR/scripts/config/desktop.sh"
run_step "matugen config" bash "$REPO_DIR/scripts/config/matugen.sh"
run_step "Fcitx5 config" bash "$REPO_DIR/scripts/config/fcitx.sh"
run_step "KDE Connect config" bash "$REPO_DIR/scripts/config/kdeconnect.sh"

# trap EXIT 自动调用 _on_exit（proxy_stop + print_summary）
