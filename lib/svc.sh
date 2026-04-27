#!/usr/bin/env bash
# =============================================================================
# lib/svc.sh -- systemd 服务管理助手
#
# 系统级操作统一通过 sudo 调用：root 环境下 sudo 是 PAM 透传，普通用户脚本
# 中通过临时 NOPASSWD 规则免交互。
#
# 依赖：lib/utils.sh
# =============================================================================

[[ -n "${_SVC_LOADED:-}" ]] && return 0
_SVC_LOADED=1

[[ -n "${_UTILS_LOADED:-}" ]] || {
    echo "[ERR] source lib/utils.sh before lib/svc.sh" >&2
    return 1
}

# -- 系统服务 -----------------------------------------------------------------
enable_system_service() {
    local svc="$1"
    if systemctl is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    elif sudo systemctl enable "$svc"; then
        success "$svc enabled"
    else
        warn "$svc could not be enabled"
    fi
}

# -- 用户服务 -----------------------------------------------------------------
enable_user_service() {
    local svc="$1"
    ensure_xdg_runtime_dir
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        warn "$svc already enabled, skipping"
    elif systemctl --user enable "$svc" 2>/dev/null; then
        success "$svc enabled"
    else
        warn "$svc could not be enabled (no systemd user session?)"
    fi
}

# -- 直接创建 .wants/ 软链接 --------------------------------------------------
# 适用于 .path / 刚写入但尚未 daemon-reload 的 unit：
# 此时 systemctl --user enable 可能因找不到 unit 文件而失败，软链接更可靠。
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
        warn "Unit file not found: $unit -- enable manually after first login"
        return 0
    fi

    mkdir -p "$wants_dir"
    ln -sf "$unit_path" "$wants_dir/$unit"
    success "Linked $unit -> ${wanted_by}.wants/"
}

# -- 切换显示管理器 -----------------------------------------------------------
switch_display_manager() {
    local svc="$1"
    sudo rm -f /etc/systemd/system/display-manager.service
    enable_system_service "$svc"
}
