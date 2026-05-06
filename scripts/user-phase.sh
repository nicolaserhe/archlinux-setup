#!/usr/bin/env bash
# =============================================================================
# scripts/user-phase.sh -- 用户阶段编排（以 TARGET_USER 身份运行）
#
# 由 install.sh 通过 runuser 调用：
#   runuser -l <user> -c "bash scripts/user-phase.sh <repo_dir>"
#
# 也可以单独运行以重新应用所有配置：
#   bash scripts/user-phase.sh /path/to/repo
# =============================================================================

set -euo pipefail

REPO_DIR="${1:?Usage: bash user-phase.sh <repo_dir>}"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/proxy.sh"

echo -e "${BOLD}"
echo "  User phase: $(whoami)"
echo -e "${RESET}"

# runuser -l 不会建立完整的 systemd 用户会话；linger 步骤已经创建了
# /run/user/<uid>，这里把路径导出供后续 systemctl --user 使用
ensure_xdg_runtime_dir

_on_exit() {
    set +e
    proxy_stop 2>/dev/null
    print_summary
}
trap '_on_exit' EXIT

# -- Step 1: 启动代理 ---------------------------------------------------------
run_step "Proxy start" proxy_start "$REPO_DIR" || exit 1

# -- Step 2..N: 包 + 配置 -----------------------------------------------------
# matugen 必须在 desktop（含 dms setup）之后：要在 DMS 生成的 config.toml
# 上做追加而不是覆盖。kdeconnect 必须在 desktop 之后：依赖 niri config.kdl 已存在。
run_step "AUR packages"      bash "$REPO_DIR/scripts/packages/aur.sh"
run_step "Flatpak packages"  bash "$REPO_DIR/scripts/packages/flatpak.sh"
run_step "Shell config"      bash "$REPO_DIR/scripts/config/shell.sh"
run_step "Desktop config"    bash "$REPO_DIR/scripts/config/desktop.sh"
run_step "matugen config"    bash "$REPO_DIR/scripts/config/matugen.sh"
run_step "Fcitx5 config"     bash "$REPO_DIR/scripts/config/fcitx.sh"
run_step "KDE Connect config" bash "$REPO_DIR/scripts/config/kdeconnect.sh"
