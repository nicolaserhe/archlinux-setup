#!/usr/bin/env bash
# =============================================================================
# lib/utils.sh -- 颜色、日志、XDG 运行时目录、步骤追踪
# =============================================================================

[[ -n "${_UTILS_LOADED:-}" ]] && return 0
_UTILS_LOADED=1

# -- 颜色 ---------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# -- 日志（全部写到 stderr，不干扰 stdout 捕获）-------------------------------
info()    { echo -e "${BLUE}[INFO]${RESET}  $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*" >&2; }
warn()    { echo -e "${YELLOW}[SKIP]${RESET}  $*" >&2; }
error()   { echo -e "${RED}[ERR]${RESET}   $*" >&2; }
header()  { echo -e "\n${BOLD}==> $*${RESET}" >&2; }
die()     { error "$*"; exit 1; }

# -- XDG 运行时目录 -----------------------------------------------------------
# runuser / su 不建立完整 systemd 用户会话，新用户首次运行时
# XDG_RUNTIME_DIR 和 DBUS_SESSION_BUS_ADDRESS 均未定义，
# 导致所有 systemctl --user 调用失败。
ensure_xdg_runtime_dir() {
    local uid runtime_dir
    uid="$(id -u)"
    runtime_dir="/run/user/$uid"

    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
        return 0
    fi

    export XDG_RUNTIME_DIR="$runtime_dir"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus"

    if [[ -d "$runtime_dir" ]]; then
        success "XDG_RUNTIME_DIR: $runtime_dir"
    else
        warn "XDG_RUNTIME_DIR $runtime_dir 不存在，用户服务可能需要首次登录后手动重新启用"
    fi
}

# -- 步骤追踪 -----------------------------------------------------------------
_STEPS_PASS=()
_STEPS_FAIL=()

run_step() {
    local label="$1"
    shift
    header "$label"
    if "$@"; then
        _STEPS_PASS+=("$label")
        success "$label -- done"
        return 0
    else
        local rc=$?
        _STEPS_FAIL+=("$label")
        error "$label -- failed (exit $rc)"
        return $rc
    fi
}

print_summary() {
    local s np nf
    np=${#_STEPS_PASS[@]}
    nf=${#_STEPS_FAIL[@]}

    echo -e "\n${BOLD}========================================${RESET}" >&2
    echo -e "${BOLD}  Summary${RESET}" >&2
    echo -e "${BOLD}========================================${RESET}" >&2

    # 用 (( np > 0 )) 守卫，兼容 bash 4.3 及以下 set -u 环境
    if (( np > 0 )); then
        for s in "${_STEPS_PASS[@]}"; do
            echo -e "  ${GREEN}[PASS]${RESET}  $s" >&2
        done
    fi
    if (( nf > 0 )); then
        for s in "${_STEPS_FAIL[@]}"; do
            echo -e "  ${RED}[FAIL]${RESET}  $s" >&2
        done
    fi

    echo -e "${BOLD}========================================${RESET}" >&2
    if (( nf == 0 )); then
        echo -e "  ${GREEN}${BOLD}All $np steps completed successfully.${RESET}" >&2
    else
        echo -e "  ${RED}${BOLD}$nf step(s) failed${RESET}, $np passed." >&2
        echo -e "  Fix the failed steps and re-run the relevant script." >&2
    fi
    echo >&2
}
