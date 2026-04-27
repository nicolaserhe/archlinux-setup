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

mkdir -p "$REPO_DIR/log"
LOG_FILE="$REPO_DIR/log/user-phase-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

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

# -- 启动代理 -----------------------------------------------------------------
run_step "Proxy start" proxy_start "$REPO_DIR" || exit 1

# -- core/ 模块 ---------------------------------------------------------------
# 显式排序：dms 必须早于 matugen 和 kdeconnect。其他模块互相独立，
# 但 02-aur-bootstrap / 03-flatpak-init 必须先跑（后续模块装 AUR/Flatpak）。
CORE_SCRIPTS=(
    02-aur-bootstrap.sh
    03-fonts.sh
    04-flatpak-init.sh
    compositor.sh
    login.sh
    audio.sh
    system-services.sh
    docker.sh
    shell.sh
    dms.sh
    matugen.sh
    fcitx.sh
    keyd.sh
    kdeconnect.sh
    clipboard.sh
    flclash.sh
    boot.sh
)

for _core in "${CORE_SCRIPTS[@]}"; do
    run_step "core/${_core%.sh}" bash "$REPO_DIR/scripts/core/${_core}" || exit 1
done
unset _core

# -- apps/ 模块 ---------------------------------------------------------------
# 应用之间互相独立，单个失败不阻断其他应用安装
for _app in "$REPO_DIR/scripts/apps/"*.sh; do
    [[ -f "$_app" ]] || continue
    run_step "app/$(basename "${_app%.sh}")" bash "$_app" || true
done
unset _app
