#!/usr/bin/env bash
# =============================================================================
# usb/lib.sh -- USB 工具集共用的轻量日志与重试助手
#
# 设计原则：与项目主 lib/ 解耦，仅提供最小依赖；usb/ 下脚本可在任意主机
# 单独运行（如另一台机器上跑订阅转换），无需 clone 完整仓库。
# =============================================================================

[[ -n "${_USB_LIB_LOADED:-}" ]] && return 0
_USB_LIB_LOADED=1

# 与主 lib/utils.sh 保持同名前缀，便于阅读时统一识别
log()     { printf '[INFO] %s\n' "$*" >&2; }
success() { printf '[OK]   %s\n' "$*" >&2; }
warn()    { printf '[WARN] %s\n' "$*" >&2; }
die()     { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

# retry <count> <delay> <cmd...>
retry() {
    local count=$1 delay=$2 attempt
    shift 2
    for (( attempt = 1; attempt <= count; attempt++ )); do
        "$@" && return 0
        if (( attempt < count )); then
            warn "Attempt $attempt/$count failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
    done
    return 1
}
