#!/usr/bin/env bash
# =============================================================================
# lib/utils.sh -- 颜色、日志、命令检测、重试、XDG 运行时目录、步骤追踪
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

# -- 日志 ---------------------------------------------------------------------
# 全部写到 stderr，保持 stdout 干净，便于通过 $() 捕获脚本输出
# 若 LOG_FILE 非空，每条日志同时追加到该文件（无颜色，纯文本）
: "${LOG_FILE:=}"
info() { echo -e "${BLUE}[INFO]${RESET}  $*" >&2; [[ -n "$LOG_FILE" ]] && echo "[INFO]  $*" >> "$LOG_FILE"; :; }
success() { echo -e "${GREEN}[OK]${RESET}    $*" >&2; [[ -n "$LOG_FILE" ]] && echo "[OK]    $*" >> "$LOG_FILE"; :; }
warn() { echo -e "${YELLOW}[SKIP]${RESET}  $*" >&2; [[ -n "$LOG_FILE" ]] && echo "[SKIP]  $*" >> "$LOG_FILE"; :; }
error() { echo -e "${RED}[ERR]${RESET}   $*" >&2; [[ -n "$LOG_FILE" ]] && echo "[ERR]   $*" >> "$LOG_FILE"; :; }
header() { echo -e "\n${BOLD}==> $*${RESET}" >&2; [[ -n "$LOG_FILE" ]] && echo "==> $*" >> "$LOG_FILE"; :; }
die() {
    error "$*"
    exit 1
}

# -- 命令检测 -----------------------------------------------------------------
command_exists() { command -v "$1" &>/dev/null; }

# -- 重试 ---------------------------------------------------------------------
# retry <count> <delay_seconds> <cmd...>
retry() {
    local count=$1 delay=$2 attempt
    shift 2
    for ((attempt = 1; attempt <= count; attempt++)); do
        "$@" && return 0
        if ((attempt < count)); then
            warn "Attempt $attempt/$count failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
    done
    return 1
}

# -- XDG 运行时目录 -----------------------------------------------------------
# runuser / su 不会建立完整的 systemd 用户会话；XDG_RUNTIME_DIR 与
# DBUS_SESSION_BUS_ADDRESS 缺失时所有 systemctl --user 调用都会失败。
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
        warn "XDG_RUNTIME_DIR $runtime_dir missing -- user services may need re-enabling at first login"
    fi
}

# -- 步骤追踪 -----------------------------------------------------------------
_STEPS_PASS=()
_STEPS_FAIL=()

run_step() {
    local label="$1"
    shift
    header "$label"
    local rc=0

    if [[ -n "$LOG_FILE" ]]; then
        local tmpfile
        tmpfile="$(mktemp /tmp/run_step.XXXXXX)"
        "$@" 2> >(tee -a "$tmpfile" >&2) || rc=$?
        if [[ -s "$tmpfile" ]]; then
            cat "$tmpfile" >> "$LOG_FILE"
        fi
        rm -f "$tmpfile"
    else
        "$@" || rc=$?
    fi

    if ((rc == 0)); then
        _STEPS_PASS+=("$label")
        success "$label -- done"
        return 0
    else
        _STEPS_FAIL+=("$label")
        error "$label -- failed (exit $rc)"
        return $rc
    fi
}

print_summary() {
    local s np=${#_STEPS_PASS[@]} nf=${#_STEPS_FAIL[@]}

    echo -e "\n${BOLD}========================================${RESET}" >&2
    echo -e "${BOLD}  Summary${RESET}" >&2
    echo -e "${BOLD}========================================${RESET}" >&2

    # (( var > 0 )) 守卫，兼容老版本 bash 在 set -u 下展开空数组报错
    if ((np > 0)); then
        for s in "${_STEPS_PASS[@]}"; do
            echo -e "  ${GREEN}[PASS]${RESET}  $s" >&2
        done
    fi
    if ((nf > 0)); then
        for s in "${_STEPS_FAIL[@]}"; do
            echo -e "  ${RED}[FAIL]${RESET}  $s" >&2
        done
    fi

    echo -e "${BOLD}========================================${RESET}" >&2
    if ((nf == 0)); then
        echo -e "  ${GREEN}${BOLD}All $np steps completed successfully.${RESET}" >&2
    else
        echo -e "  ${RED}${BOLD}$nf step(s) failed${RESET}, $np passed." >&2
        echo -e "  Fix the failed steps and re-run the relevant script." >&2
    fi
    echo >&2
}
