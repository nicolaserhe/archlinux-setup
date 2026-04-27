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

# 本文件所在目录，用于定位同级 helpers/ 和 proxy-const.sh
_PROXY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 常量拆到 proxy-const.sh -- install.sh 想只要 PID 文件路径可以单独 source 它
# shellcheck source=SCRIPTDIR/proxy-const.sh
source "$_PROXY_LIB_DIR/proxy-const.sh"

# user-only 值：用户 home 才能定 mihomo config dir
_MIHOMO_CFG_DIR="$HOME/.config/mihomo"

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

    grep -qE '^(proxies:|proxy-providers:)' "$cfg" ||
        die "proxy: invalid Clash YAML (missing proxies/proxy-providers): $cfg"

    # 防御性体积检查：低于 50 字节几乎可以确定是空模板或下载残骸
    local size
    size="$(wc -c <"$cfg")"
    ((size >= 50)) || die "proxy: config too small (${size} bytes): $cfg"

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

    # 提取到独立 .py 让 lint / 编辑器能正常工作；逻辑见 helpers/patch-mihomo-config.py
    python3 "$_PROXY_LIB_DIR/helpers/patch-mihomo-config.py" \
        "$_MIHOMO_CFG_DIR/config.yaml" "$_PROXY_PORT"
    success "Config deployed (mixed-port: $_PROXY_PORT, tun disabled)"
}

# -- 私有：选一个可用的代理端口 -----------------------------------------------
# 优先 7890（FlClash 默认，重跑 install 时若 FlClash 已起则被占）；
# 否则在 17890-17899 找空闲端口，避开 clipboard.sh 用的 17080+ 段。
_proxy_find_port() {
    if ! ss -tln 2>/dev/null | grep -q ":${_PROXY_PORT_DEFAULT} "; then
        echo "$_PROXY_PORT_DEFAULT"
        return 0
    fi
    local port
    for port in $(seq 17890 17899); do
        if ! ss -tln 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

# -- 私有：清理上次残留的 mihomo 进程 -----------------------------------------
_proxy_kill_stale() {
    [[ -f "$MIHOMO_PID_FILE" ]] || return 0
    local old_pid
    old_pid="$(cat "$MIHOMO_PID_FILE")"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        warn "Stale mihomo found (PID: $old_pid), stopping it"
        kill "$old_pid" 2>/dev/null || true
        sleep 1
        # SIGKILL fallback：旧进程不响应 TERM 时强杀，否则新 mihomo 启动端口冲突
        kill -9 "$old_pid" 2>/dev/null || true
    fi
    rm -f "$MIHOMO_PID_FILE"
}

# -- 私有：等待端口就绪 -------------------------------------------------------
_proxy_wait_port() {
    local pid="$1" elapsed=0
    while ((elapsed < _PROXY_PORT_TIMEOUT)); do
        sleep 1
        # ((var++)) 当值为 0 时返回 1，配合 set -e 会误判，必须 || true
        ((elapsed++)) || true
        if ! kill -0 "$pid" 2>/dev/null; then
            error "mihomo exited unexpectedly. Last log:"
            tail -20 "$MIHOMO_LOG_FILE" >&2
            return 1
        fi
        # 端口号必须带尾空格，否则 :7890 会被 :78901 之类误命中
        ss -tlnp 2>/dev/null | grep -q ":$_PROXY_PORT " && return 0
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

    # 备份调用方原有 proxy env，proxy_stop 用来还原；只在首次 proxy_start 时
    # save，避免重复调用覆盖原值
    if [[ -z "$_PROXY_ENV_SAVED" ]]; then
        _PROXY_SAVED_HTTP="${http_proxy:-}"
        _PROXY_SAVED_HTTPS="${https_proxy:-}"
        _PROXY_SAVED_ALL="${all_proxy:-}"
        _PROXY_SAVED_NO="${no_proxy:-}"
        _PROXY_ENV_SAVED=1
    fi

    _PROXY_PORT="$(_proxy_find_port)" ||
        die "proxy: no free port in $_PROXY_PORT_DEFAULT or 17890-17899 -- stop occupying processes and retry"
    if [[ "$_PROXY_PORT" != "$_PROXY_PORT_DEFAULT" ]]; then
        warn "Port $_PROXY_PORT_DEFAULT busy, falling back to $_PROXY_PORT"
    fi

    local cfg
    cfg="$(_proxy_locate_config "$repo_dir")"
    info "Using Mihomo config: $cfg"

    _proxy_install_config "$cfg"
    _proxy_kill_stale

    mihomo -d "$_MIHOMO_CFG_DIR" >"$MIHOMO_LOG_FILE" 2>&1 &
    local pid=$!
    # symlink attack 加固：先 rm（避免 PID 文件是 symlink 指向其他文件被覆盖），
    # 再 chmod 600 让 PID 信息不可被其他用户读
    rm -f "$MIHOMO_PID_FILE"
    echo "$pid" >"$MIHOMO_PID_FILE"
    chmod 600 "$MIHOMO_PID_FILE" 2>/dev/null || true
    info "mihomo started (PID: $pid), waiting for port $_PROXY_PORT..."

    _proxy_wait_port "$pid" ||
        die "mihomo failed to start -- check config: $cfg"

    retry 3 5 _proxy_check_internet ||
        die "Proxy port is up but cannot reach internet -- check your nodes"

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
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            if kill "$pid" 2>/dev/null; then
                success "mihomo stopped (PID: $pid)"
            else
                warn "Failed to send TERM to PID $pid"
            fi
            sleep 1
            # SIGKILL fallback：1s 内未退出强杀
            kill -9 "$pid" 2>/dev/null || true
        else
            warn "PID $pid is not running, already stopped"
        fi
        rm -f "$MIHOMO_PID_FILE"
    else
        warn "No PID file found -- mihomo may not be running"
    fi

    # 还原 proxy_start 接管前的 env：原本有值就 export 回去，原本没值才 unset。
    # 避免 user shell 原本设的代理被无差别清掉。
    if [[ -n "$_PROXY_ENV_SAVED" ]]; then
        if [[ -n "$_PROXY_SAVED_HTTP" ]];  then export http_proxy="$_PROXY_SAVED_HTTP";   else unset http_proxy;  fi
        if [[ -n "$_PROXY_SAVED_HTTPS" ]]; then export https_proxy="$_PROXY_SAVED_HTTPS"; else unset https_proxy; fi
        if [[ -n "$_PROXY_SAVED_ALL" ]];   then export all_proxy="$_PROXY_SAVED_ALL";     else unset all_proxy;   fi
        if [[ -n "$_PROXY_SAVED_NO" ]];    then export no_proxy="$_PROXY_SAVED_NO";       else unset no_proxy;    fi
        _PROXY_ENV_SAVED=""
        success "Proxy env restored"
    else
        unset http_proxy https_proxy all_proxy no_proxy
        success "Proxy env vars cleared"
    fi
}
