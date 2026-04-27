#!/usr/bin/env bash
# =============================================================================
# lib/svc.sh -- systemd 服务管理助手
#
# 注意：enable_system_service / switch_display_manager 需要 root 权限；
#       在普通用户脚本中通过 sudo 调用，在 root 脚本中直接执行。
#       这里统一使用 sudo，在 root 环境下 sudo 是无操作的（PAM 透传）。
#
# 依赖：lib/utils.sh（ensure_xdg_runtime_dir）
# =============================================================================

[[ -n "${_SVC_LOADED:-}" ]] && return 0
_SVC_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/svc.sh" >&2
    return 1
}

# enable_system_service <unit> -- 启用系统级服务（需要 root / sudo）
enable_system_service() {
    local svc="$1"
    if systemctl is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    else
        sudo systemctl enable "$svc" \
            && success "$svc enabled" \
            || warn "$svc could not be enabled"
    fi
}

# enable_user_service <unit> -- 启用用户级服务
enable_user_service() {
    local svc="$1"
    ensure_xdg_runtime_dir
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    else
        systemctl --user enable "$svc" 2>/dev/null \
            && success "$svc enabled" \
            || warn "$svc could not be enabled (no systemd user session?)"
    fi
}

# add_user_service_wants <unit> <wanted-by-unit>
# 直接创建 .wants/ 软链接，不依赖活跃的 D-Bus 会话。
# 按优先级搜索 unit 文件：用户配置目录 > 包安装目录。
add_user_service_wants() {
    local unit="$1" wanted_by="$2"
    local wants_dir="$HOME/.config/systemd/user/${wanted_by}.wants"
    local unit_path="" dir

    local -a search_dirs=(
        "$HOME/.config/systemd/user"
        "$HOME/.local/share/systemd/user"
        /etc/systemd/user
        /usr/lib/systemd/user
        /usr/local/lib/systemd/user
    )
    for dir in "${search_dirs[@]}"; do
        if [[ -f "$dir/$unit" ]]; then
            unit_path="$dir/$unit"
            break
        fi
    done

    if [[ -z "$unit_path" ]]; then
        warn "Unit file not found: $unit"
        warn "  $unit will NOT be linked to ${wanted_by}.wants/ -- enable manually after first login"
        return 0
    fi

    mkdir -p "$wants_dir"
    ln -sf "$unit_path" "$wants_dir/$unit"
    success "Linked $unit -> ${wanted_by}.wants/"
}

# switch_display_manager <unit> -- 切换显示管理器
switch_display_manager() {
    local svc="$1"
    sudo rm -f /etc/systemd/system/display-manager.service
    enable_system_service "$svc"
}
