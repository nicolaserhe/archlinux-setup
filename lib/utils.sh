#!/usr/bin/env bash
# =============================================================================
# lib/utils.sh -- 颜色、日志、步骤追踪
#
# 规则：本文件只能被 source，不能直接执行。
#       不设顶层 set -e / set -u，避免污染调用方 shell。
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

# -- 日志（全部写到 stderr）---------------------------------------------------
info() { echo -e "${BLUE}[INFO]${RESET}  $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*" >&2; }
warn() { echo -e "${YELLOW}[SKIP]${RESET}  $*" >&2; }
error() { echo -e "${RED}[ERR]${RESET}   $*" >&2; }
header() { echo -e "\n${BOLD}==> $*${RESET}" >&2; }
die() {
    error "$*"
    exit 1
}

# -- 步骤追踪 -----------------------------------------------------------------
# 每个编排脚本（install.sh / user-phase.sh）在自己的 shell 中独立维护列表。
# 子模块脚本只需 exit 0 / 非零，无需关心追踪逻辑。

_STEPS_PASS=()
_STEPS_FAIL=()

# run_step <label> <cmd> [args...]
#   运行命令，捕获退出码，记录 PASS / FAIL。
#   调用方 shell 本身不受子命令 set -e 影响。
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
        return 1
    fi
}

print_summary() {
    local np=${#_STEPS_PASS[@]} nf=${#_STEPS_FAIL[@]}
    echo -e "\n${BOLD}========================================${RESET}" >&2
    echo -e "${BOLD}  Summary${RESET}" >&2
    echo -e "${BOLD}========================================${RESET}" >&2
    for s in "${_STEPS_PASS[@]:+"${_STEPS_PASS[@]}"}"; do echo -e "  ${GREEN}[PASS]${RESET}  $s" >&2; done
    for s in "${_STEPS_FAIL[@]:+"${_STEPS_FAIL[@]}"}"; do echo -e "  ${RED}[FAIL]${RESET}  $s" >&2; done
    echo -e "${BOLD}========================================${RESET}" >&2
    if [[ $nf -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}All $np steps completed successfully.${RESET}" >&2
    else
        echo -e "  ${RED}${BOLD}$nf step(s) failed${RESET}, $np passed." >&2
        echo -e "  Fix the failed steps and re-run the relevant script." >&2
    fi
    echo >&2
}
