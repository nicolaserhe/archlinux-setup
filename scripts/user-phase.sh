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

set -Eeuo pipefail

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
# 但 aur-bootstrap / flatpak-init / fonts 必须先跑（后续模块装 AUR/Flatpak、
# 字体规则被 GTK/CJK 应用所依赖）。
CORE_SCRIPTS=(
    aur-bootstrap.sh
    fonts.sh
    flatpak-init.sh
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
    niri-shm-fix.sh
)

for _core in "${CORE_SCRIPTS[@]}"; do
    run_step "core/${_core%.sh}" bash "$REPO_DIR/scripts/core/${_core}" || exit 1
done
unset _core

# -- apps/ 模块 ---------------------------------------------------------------
# 显式声明顺序：glob 字典序遇到 rename 会默默改顺序；显式数组让"加 app"成为
# 有意识的操作。应用间互相独立 → 单个失败不阻断其他。
APP_SCRIPTS=(
    beekeeper
    biu
    chrome
    dbx
    qq
    rendercv
    recordly
    wechat
    yaak
)

for _app in "${APP_SCRIPTS[@]}"; do
    _app_path="$REPO_DIR/scripts/apps/${_app}.sh"
    if [[ ! -f "$_app_path" ]]; then
        warn "Declared in APP_SCRIPTS but missing: $_app_path"
        continue
    fi
    run_step "app/$_app" bash "$_app_path" || true
done
unset _app _app_path
