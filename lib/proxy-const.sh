#!/usr/bin/env bash
# =============================================================================
# lib/proxy-const.sh -- 代理相关常量（无副作用，可独立 source）
#
# install.sh 只需要 PID/LOG 文件路径做 cleanup，不需要 lifecycle 函数；
# 把常量拆出来，让"想要常量但不要 lifecycle"的调用方避免 source 整个
# proxy.sh（proxy.sh 内部仍 source 本文件，向后兼容）。
# =============================================================================

[[ -n "${_PROXY_CONST_LOADED:-}" ]] && return 0
_PROXY_CONST_LOADED=1

# 不 export：install.sh → runuser -l user-phase.sh 是 fresh login shell，env
# 漏过去会让 user-phase 子进程的 proxy_start 拿到"_PROXY_ENV_SAVED=1"误以为
# 上次 save 过，跳过 env 备份 → proxy_stop 时把空字符串覆盖用户真实代理 env。
# 当前 install.sh 不调 proxy_start 所以没踩雷，紧约束写法防御未来扩展。
# shellcheck disable=SC2034 # used by lib/proxy.sh after source
# install.sh 与 user-phase.sh 各自独立 source 本文件，PID/LOG 路径相同即可
# 跨阶段 cleanup（无需 export，路径常量在子进程内独立赋值得到相同值）
MIHOMO_PID_FILE="/tmp/mihomo-bootstrap.pid"
# shellcheck disable=SC2034
MIHOMO_LOG_FILE="/tmp/mihomo-bootstrap.log"

# 期望端口（与 FlClash 默认一致，no_proxy_list 也假定 7890）；被占用时回退
# 到 17890-17899。最终值由 proxy_start 设置。
# shellcheck disable=SC2034
_PROXY_PORT_DEFAULT=7890
# shellcheck disable=SC2034
_PROXY_PORT=""

# 等待 mihomo 端口就绪的最大秒数（慢机器可调）
# shellcheck disable=SC2034
_PROXY_PORT_TIMEOUT=10

# proxy_start 备份的调用方原有 proxy env，proxy_stop 用来还原 -- 避免无差
# 别 unset 破坏 user shell 原本设置好的代理环境
# shellcheck disable=SC2034
_PROXY_SAVED_HTTP=""
# shellcheck disable=SC2034
_PROXY_SAVED_HTTPS=""
# shellcheck disable=SC2034
_PROXY_SAVED_ALL=""
# shellcheck disable=SC2034
_PROXY_SAVED_NO=""
# shellcheck disable=SC2034
_PROXY_ENV_SAVED=""  # 标记 saved vars 是否有效（避免重复 save 覆盖）
