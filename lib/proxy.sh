#!/usr/bin/env bash
# =============================================================================
# lib/proxy.sh -- Mihomo 代理管理
#
# 必须 source 才能将代理环境变量导出到调用方 shell。
# 不在本文件顶层设置 set -e/-u，避免污染调用方。
#
# 用法：
#   source "$REPO_DIR/lib/utils.sh"
#   source "$REPO_DIR/lib/proxy.sh"
#   proxy_start "$REPO_DIR"
#   proxy_stop
# =============================================================================

[[ -n "${_PROXY_LOADED:-}" ]] && return 0
_PROXY_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/proxy.sh" >&2
    return 1
}

# 暴露给 install.sh 用于清理（root 与用户阶段共享同一文件路径）
MIHOMO_PID_FILE="/tmp/mihomo-bootstrap.pid"
MIHOMO_LOG_FILE="/tmp/mihomo-bootstrap.log"
_MIHOMO_CFG_DIR="$HOME/.config/mihomo"
_PROXY_PORT=7890

# -- 私有：定位订阅产物中的 YAML 配置 -----------------------------------------
_proxy_locate_config() {
    local repo_dir="$1"
    local cfg_dir="$repo_dir/usb/sub2clash/files"
    [[ -d "$cfg_dir" ]] || die "proxy: config directory not found: $cfg_dir"

    local cfg
    cfg="$(find "$cfg_dir" -maxdepth 1 \
        \( -name "*.yaml" -o -name "*.yml" \) \
        2>/dev/null | sort | head -1)"
    [[ -n "$cfg" ]] || die "proxy: no YAML config file found in: $cfg_dir"

    grep -qE '^(proxies:|proxy-providers:)' "$cfg" \
        || die "proxy: invalid Clash YAML (missing proxies/proxy-providers): $cfg"

    # 防御性体积检查：低于 50 字节几乎可以确定是空模板或下载残骸
    local size
    size="$(wc -c < "$cfg")"
    (( size >= 50 )) || die "proxy: config too small (${size} bytes): $cfg"

    printf '%s' "$cfg"
}

# -- 私有：部署配置并修补 mixed-port / 删除 tun / 注释特权端口 ----------------
_proxy_install_config() {
    local src="$1"
    mkdir -p "$_MIHOMO_CFG_DIR"
    cp "$src" "$_MIHOMO_CFG_DIR/config.yaml"

    # geoip.metadb 由 sub2clash/convert.sh 同步下载到 files/，此处缺失只降级为警告
    local geoip_src
    geoip_src="$(dirname "$src")/geoip.metadb"
    if [[ -f "$geoip_src" ]]; then
        cp "$geoip_src" "$_MIHOMO_CFG_DIR/geoip.metadb"
        success "geoip.metadb deployed"
    else
        warn "geoip.metadb not found alongside config -- mihomo will download if needed"
    fi

    # 通过 python 修改 yaml，避免引入额外 yaml 解析依赖；端口从 shell 注入
    python3 - "$_MIHOMO_CFG_DIR/config.yaml" "$_PROXY_PORT" <<'PYEOF'
import sys, re
path, port = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    text = f.read()
if not re.search(r'^mixed-port\s*:', text, re.M):
    text = f"mixed-port: {port}\n" + text
text = re.sub(r'^tun\s*:.*?(?=^\S|\Z)', '', text, flags=re.M | re.S)
text = re.sub(r'^(redir-port|tproxy-port)\s*:.*',
              r'# \g<0>  # disabled: requires root', text, flags=re.M)
with open(path, 'w', encoding="utf-8") as f:
    f.write(text)
PYEOF
    success "Config deployed (mixed-port: $_PROXY_PORT, tun disabled)"
}

# -- 私有：清理上次残留的 mihomo 进程 -----------------------------------------
_proxy_kill_stale() {
    [[ -f "$MIHOMO_PID_FILE" ]] || return 0
    local old_pid
    old_pid="$(cat "$MIHOMO_PID_FILE")"
    if kill -0 "$old_pid" 2>/dev/null; then
        warn "Stale mihomo found (PID: $old_pid), stopping it"
        kill "$old_pid" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$MIHOMO_PID_FILE"
}

# -- 私有：等待端口就绪 -------------------------------------------------------
_proxy_wait_port() {
    local pid="$1" elapsed=0
    while (( elapsed < 10 )); do
        sleep 1
        # ((var++)) 当值为 0 时返回 1，配合 set -e 会误判，必须 || true
        (( elapsed++ )) || true
        if ! kill -0 "$pid" 2>/dev/null; then
            error "mihomo exited unexpectedly. Last log:"
            tail -20 "$MIHOMO_LOG_FILE" >&2
            return 1
        fi
        ss -tlnp 2>/dev/null | grep -q ":$_PROXY_PORT" && return 0
    done
    return 1
}

# -- 私有：通过代理验证出网 ---------------------------------------------------
_proxy_check_internet() {
    curl -fsS --max-time 8 \
        -x "http://127.0.0.1:$_PROXY_PORT" \
        https://www.google.com -o /dev/null
}

# =============================================================================
# proxy_start <repo_dir>
# =============================================================================
proxy_start() {
    local repo_dir="${1:?proxy_start: repo_dir argument required}"

    local cfg
    cfg="$(_proxy_locate_config "$repo_dir")"
    info "Using Mihomo config: $cfg"

    _proxy_install_config "$cfg"
    _proxy_kill_stale

    mihomo -d "$_MIHOMO_CFG_DIR" >"$MIHOMO_LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$MIHOMO_PID_FILE"
    info "mihomo started (PID: $pid), waiting for port $_PROXY_PORT..."

    _proxy_wait_port "$pid" \
        || die "mihomo failed to start -- check config: $cfg"

    retry 3 5 _proxy_check_internet \
        || die "Proxy port is up but cannot reach internet -- check your nodes"

    success "Proxy active -> http://127.0.0.1:$_PROXY_PORT  (log: $MIHOMO_LOG_FILE)"

    # 国内常用 mirror 不走代理，避免 sub provider 中转抖动影响 pacman/AUR 下载
    local no_proxy_list="localhost,127.0.0.1"
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
    if [[ -f "$MIHOMO_PID_FILE" ]]; then
        local pid
        pid="$(cat "$MIHOMO_PID_FILE")"
        if kill -0 "$pid" 2>/dev/null; then
            if kill "$pid" 2>/dev/null; then
                success "mihomo stopped (PID: $pid)"
            else
                warn "Failed to kill PID $pid"
            fi
        else
            warn "PID $pid is not running, already stopped"
        fi
        rm -f "$MIHOMO_PID_FILE"
    else
        warn "No PID file found -- mihomo may not be running"
    fi

    unset http_proxy https_proxy all_proxy no_proxy
    success "Proxy env vars cleared"
}
