#!/usr/bin/env bash
# =============================================================================
# lib/proxy.sh -- Mihomo 代理管理
#
# 规则：本文件只能被 source，不能直接执行。
#       不设顶层 set -e / set -u / readonly，避免污染调用方 shell，
#       保证同一 shell 中多次 source 不会报错。
#       需要先 source lib/utils.sh。
#
# 用法（必须 source，才能把环境变量导出到调用方 shell）：
#   source "$REPO_DIR/lib/proxy.sh"
#   proxy_start "$REPO_DIR"   # 启动代理，导出 http_proxy 等变量
#   proxy_stop                # 停止代理，清除环境变量
# =============================================================================

[[ -n "${_PROXY_LOADED:-}" ]] && return 0
_PROXY_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/proxy.sh" >&2
    return 1
}

_MIHOMO_CFG_DIR="$HOME/.config/mihomo"
_MIHOMO_PID_FILE="/tmp/mihomo-bootstrap.pid"
_MIHOMO_LOG="/tmp/mihomo-bootstrap.log"
_PROXY_PORT=7890

# =============================================================================
# proxy_start <repo_dir>
# =============================================================================
proxy_start() {
    local repo_dir="${1:?proxy_start: repo_dir argument required}"
    local config_dir="$repo_dir/usb/sub2clash/files"

    # -- 定位并校验配置文件 ---------------------------------------------------
    [[ -d "$config_dir" ]] \
        || die "proxy_start: config directory not found: $config_dir"

    local config_file
    config_file="$(find "$config_dir" -maxdepth 1 \
        \( -name "*.yaml" -o -name "*.yml" \) \
        2>/dev/null | sort | head -1)"

    [[ -n "$config_file" ]] \
        || die "proxy_start: no YAML config file found in: $config_dir"

    grep -qE '^(proxies:|proxy-providers:)' "$config_file" \
        || die "proxy_start: invalid Clash YAML (missing proxies/proxy-providers): $config_file"

    local size
    size="$(wc -c < "$config_file")"
    (( size >= 50 )) \
        || die "proxy_start: config too small (${size} bytes), possibly corrupted: $config_file"

    info "Using Mihomo config: $config_file"

    # -- 部署并修补配置 -------------------------------------------------------
    mkdir -p "$_MIHOMO_CFG_DIR"
    cp "$config_file" "$_MIHOMO_CFG_DIR/config.yaml"

    # BUG FIX: geoip.metadb 不一定存在；加存在性检查，缺失时降级为警告
    local geoip_src
    geoip_src="$(dirname "$config_file")/geoip.metadb"
    if [[ -f "$geoip_src" ]]; then
        cp "$geoip_src" "$_MIHOMO_CFG_DIR/geoip.metadb"
        success "geoip.metadb deployed"
    else
        warn "geoip.metadb not found alongside config -- mihomo will download if needed"
    fi

    python3 - "$_MIHOMO_CFG_DIR/config.yaml" <<'PYEOF'
import sys, re
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if not re.search(r'^mixed-port\s*:', text, re.M):
    text = "mixed-port: 7890\n" + text
text = re.sub(r'^tun\s*:.*?(?=^\S|\Z)', '', text, flags=re.M | re.S)
text = re.sub(r'^(redir-port|tproxy-port)\s*:.*',
              r'# \g<0>  # disabled: requires root', text, flags=re.M)
open(path, 'w', encoding="utf-8").write(text)
PYEOF
    success "Config deployed (mixed-port: $_PROXY_PORT, tun disabled)"

    # -- 清理残留进程 ---------------------------------------------------------
    if [[ -f "$_MIHOMO_PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$_MIHOMO_PID_FILE")"
        if kill -0 "$old_pid" 2>/dev/null; then
            warn "Stale mihomo found (PID: $old_pid), stopping it"
            kill "$old_pid" 2>/dev/null || true
            sleep 1
        fi
        rm -f "$_MIHOMO_PID_FILE"
    fi

    # -- 启动 -----------------------------------------------------------------
    mihomo -d "$_MIHOMO_CFG_DIR" > "$_MIHOMO_LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$_MIHOMO_PID_FILE"
    info "mihomo started (PID: $pid), waiting for port $_PROXY_PORT..."

    # -- 等待端口就绪（最多 10 秒）--------------------------------------------
    local elapsed=0
    while (( elapsed < 10 )); do
        sleep 1
        (( elapsed++ )) || true   # ++ 在值为 0 时返回 1，需要 || true
        if ! kill -0 "$pid" 2>/dev/null; then
            error "mihomo exited unexpectedly. Last log:"
            tail -20 "$_MIHOMO_LOG" >&2
            die "mihomo failed to start -- check config: $config_file"
        fi
        ss -tlnp 2>/dev/null | grep -q ":$_PROXY_PORT" && break
    done

    ss -tlnp 2>/dev/null | grep -q ":$_PROXY_PORT" \
        || die "mihomo started but port $_PROXY_PORT not ready after 10s"

    # -- 验证出网（最多重试 3 次）---------------------------------------------
    local attempt
    for attempt in 1 2 3; do
        curl -fsS --max-time 8 \
            -x "http://127.0.0.1:$_PROXY_PORT" \
            https://www.google.com -o /dev/null && break
        warn "Connectivity check failed (attempt $attempt/3), retrying in 5s..."
        sleep 5
    done
    curl -fsS --max-time 8 \
        -x "http://127.0.0.1:$_PROXY_PORT" \
        https://www.google.com -o /dev/null \
        || die "Proxy port is up but cannot reach internet -- check your nodes"

    success "Proxy active -> http://127.0.0.1:$_PROXY_PORT  (log: $_MIHOMO_LOG)"

    # -- 导出代理环境变量到调用方 shell ---------------------------------------
    local no_proxy_list
    no_proxy_list="localhost,127.0.0.1"
    no_proxy_list+=",mirrors.tuna.tsinghua.edu.cn"
    no_proxy_list+=",mirrors.ustc.edu.cn"
    no_proxy_list+=",mirrors.aliyun.com"
    no_proxy_list+=",mirrors.hit.edu.cn"
    no_proxy_list+=",repo.huaweicloud.com"

    export http_proxy="http://127.0.0.1:$_PROXY_PORT"
    export https_proxy="http://127.0.0.1:$_PROXY_PORT"
    export all_proxy="socks5://127.0.0.1:$_PROXY_PORT"
    export no_proxy="$no_proxy_list"
}

# =============================================================================
# proxy_stop
# =============================================================================
proxy_stop() {
    if [[ -f "$_MIHOMO_PID_FILE" ]]; then
        local pid
        pid="$(cat "$_MIHOMO_PID_FILE")"
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" \
                && success "mihomo stopped (PID: $pid)" \
                || warn "Failed to kill PID $pid"
        else
            warn "PID $pid is not running, already stopped"
        fi
        rm -f "$_MIHOMO_PID_FILE"
    else
        warn "No PID file found -- mihomo may not be running"
    fi

    unset http_proxy https_proxy all_proxy no_proxy 2>/dev/null || true
    success "Proxy env vars cleared"
}
