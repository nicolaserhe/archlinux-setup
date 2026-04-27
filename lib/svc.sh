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

# -- 写 user systemd unit / drop-in（stdin → 文件） --------------------------
#
# write_user_unit <unit-name>            < heredoc
# write_user_dropin <unit-name> <file>   < heredoc
#
# 收敛"mkdir + cat > 路径"重复模式。所有 user-level systemd unit 都在
# ~/.config/systemd/user/，drop-in 在 <unit>.d/<file>。
#
# 注意：写完 unit 不自动 daemon-reload 也不 enable —— 调用方自己控制
# （某些场景需要批量写完一次性 reload）

write_user_unit() {
    local name="$1"
    [[ -n "$name" ]] || die "write_user_unit: name is empty"
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"
    cat > "$unit_dir/$name"
    success "Written: ~/.config/systemd/user/$name"
}

write_user_dropin() {
    local unit="$1" name="$2"
    [[ -n "$unit" ]] || die "write_user_dropin: unit is empty"
    [[ -n "$name" ]] || die "write_user_dropin: dropin name is empty"
    local dir="$HOME/.config/systemd/user/$unit.d"
    mkdir -p "$dir"
    cat > "$dir/$name"
    success "Written: ~/.config/systemd/user/$unit.d/$name"
}

# -- 切换显示管理器 -----------------------------------------------------------
switch_display_manager() {
    local svc="$1"
    sudo rm -f /etc/systemd/system/display-manager.service
    enable_system_service "$svc"
}
