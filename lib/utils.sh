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
_LOG_FILE_WARNED=""

# 写一行到 LOG_FILE，失败时一次性 warn 到 stderr，避免后续日志静默丢失。
_log_to_file() {
    [[ -n "$LOG_FILE" ]] || return 0
    if ! printf '%s\n' "$1" >> "$LOG_FILE" 2>/dev/null; then
        if [[ -z "$_LOG_FILE_WARNED" ]]; then
            _LOG_FILE_WARNED=1
            echo -e "${YELLOW}[SKIP]${RESET}  LOG_FILE=$LOG_FILE 不可写，后续日志只输出到 stderr" >&2
        fi
    fi
}

info()    { echo -e "${BLUE}[INFO]${RESET}  $*" >&2;  _log_to_file "[INFO]  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*" >&2; _log_to_file "[OK]    $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${RESET}  $*" >&2; _log_to_file "[SKIP]  $*"; }
error()   { echo -e "${RED}[ERR]${RESET}   $*" >&2;   _log_to_file "[ERR]   $*"; }
header()  { echo -e "\n${BOLD}==> $*${RESET}" >&2;    _log_to_file "==> $*"; }
die() {
    error "$*"
    exit 1
}

# -- ERR trap helper ---------------------------------------------------------
# 调用方 `set -Eeuo pipefail`，触发 unhandled 命令失败时打印 source:line + cmd。
# `||` / `&&` 兜住的失败不触发 ERR（bash 默认行为），不会污染 run_step 流程。
_err_handler() {
    local src="${1:-?}" line="${2:-?}" cmd="${3:-?}" rc="${4:-?}"
    echo -e "${RED}[ERR]${RESET}   $src:$line: '$cmd' (exit $rc)" >&2
    _log_to_file "[ERR]   $src:$line: '$cmd' (exit $rc)"
}
# source 时自动安装 ERR trap。调用方仍需 `set -Ee` 才会触发。
# 仅在调用方未自设 ERR trap 时安装，避免静默覆盖调用方逻辑。注意 source
# 后调用方再设 trap 仍会反向覆盖本 trap（bash 单 trap 语义），此处无法兜底。
if [[ -z "$(trap -p ERR)" ]]; then
    trap '_err_handler "$BASH_SOURCE" "$LINENO" "$BASH_COMMAND" $?' ERR
fi

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
        # stdout + stderr 都进 LOG_FILE：pacman/git/yay 的进度与关键输出在 stdout，
        # 单收 stderr 会让事后排查空盲。tee 输出到 stderr 维持"日志走 stderr"约定。
        #
        # 用 `> >(tee)` 而不是 `| tee`：pipe 会把 "$@" 放进 subshell，function
        # caller 内的 export 全部逃不出去。install.sh 的 _step_user 靠
        # `export TARGET_USER` 把用户名传给后续 step；user-phase.sh 的
        # proxy_start 靠 `export http_proxy/https_proxy/...` 把代理传给后续
        # 子脚本。pipe 模式下两者都丢，runuser 会拿到空用户名，AUR/git 子脚本
        # 都直连下载。process substitution 让 "$@" 在主 shell 跑，env 正常透传。
        "$@" > >(tee -a "$LOG_FILE" >&2) 2>&1
        rc=$?
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
        return "$rc"
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
