#!/usr/bin/env bash
# =============================================================================
# scripts/config/kdeconnect.sh -- KDE Connect / Valent + DankKDEConnect 插件
#
# DMS 1.4 新增了 Phone Connect 功能（DankKDEConnect 官方插件）：
#   - 在 DankBar 显示手机电量
#   - 接收手机通知、传输文件、同步剪贴板
#   - 使用 Valent（GNOME 系 KDE Connect 实现）作为后端，无 Plasma 依赖
#
# BUG FIX（上一版本）：
#   kdeconnect.sh 在 niri config.kdl 里追加了单独的 environment {} 块，
#   但 dms.sh 已经追加了一个，niri 不允许重复，导致 config parse 失败。
#   修复：SSH_AUTH_SOCK 写入 environment.d（项目已有机制），
#         niri config 只追加 spawn-at-startup，不再新增 environment 块。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

# -- DankKDEConnect 插件 ------------------------------------------------------
header "DankKDEConnect plugin"
_plugins_base="$HOME/.config/DankMaterialShell/plugins"
_kdeconnect_dst="$_plugins_base/DankKDEConnect"

if [[ -d "$_kdeconnect_dst" ]]; then
    warn "DankKDEConnect plugin already installed: $_kdeconnect_dst"
else
    mkdir -p "$_plugins_base"

    (
        set -euo pipefail
        _tmp="$(mktemp -d /tmp/dms-plugins.XXXXXX)"
        trap 'rm -rf "$_tmp"' EXIT

        git_clone "$_tmp/dms-plugins" https://github.com/AvengeMedia/dms-plugins

        if [[ -d "$_tmp/dms-plugins/DankKDEConnect" ]]; then
            cp -r "$_tmp/dms-plugins/DankKDEConnect" "$_kdeconnect_dst"
            success "DankKDEConnect plugin installed: $_kdeconnect_dst"
        else
            warn "DankKDEConnect subdirectory not found, please check the dms-plugins repository structure"
        fi
    )
fi
unset _plugins_base _kdeconnect_dst

# -- SSH_AUTH_SOCK 写入 environment.d -----------------------------------------
# BUG FIX: 不在 niri config.kdl 里新增 environment {} 块（dms.sh 已追加过一个，
# niri 不允许重复）。改用 ~/.config/environment.d/ 设置环境变量，
# systemd 会在用户会话启动时自动加载，所有应用（包括 valent）均可继承。
header "Valent SSH_AUTH_SOCK (environment.d)"
_uid="$(id -u)"
_env_file="$HOME/.config/environment.d/valent.conf"
mkdir -p "$HOME/.config/environment.d"

if [[ -f "$_env_file" ]] && grep -q 'SSH_AUTH_SOCK' "$_env_file"; then
    warn "SSH_AUTH_SOCK already in $_env_file, skipping"
else
    cat >"$_env_file" <<EOF
# Valent / KDE Connect: GCR SSH agent socket（SFTP 文件挂载需要）
SSH_AUTH_SOCK=/run/user/${_uid}/gcr/ssh
EOF
    success "Written: $_env_file"
fi
unset _uid _env_file

# -- Valent spawn-at-startup（niri config）------------------------------------
# 只追加 spawn-at-startup，不新增 environment {} 块，避免 niri parse 报错。
header "Valent niri spawn-at-startup"
_niri_cfg="$HOME/.config/niri/config.kdl"

if [[ ! -f "$_niri_cfg" ]]; then
    mkdir -p "$(dirname "$_niri_cfg")"
    touch "$_niri_cfg"
    warn "niri config does not exist -- created empty file"
fi

if grep -q 'valent' "$_niri_cfg" 2>/dev/null; then
    warn "niri: valent spawn-at-startup already exists, skipping"
else
    cat >>"$_niri_cfg" <<'NIRI_VALENT'

// KDE Connect / Valent: 作为后台 gapplication service 启动
// SSH_AUTH_SOCK 由 environment.d/valent.conf 提供
spawn-at-startup "systemctl" "--user" "import-environment" "SSH_AUTH_SOCK"
spawn-at-startup "valent" "--gapplication-service"
NIRI_VALENT
    success "niri: valent spawn-at-startup appended"
fi
unset _niri_cfg

success "KDE Connect / Valent config done"
info "后续步骤（首次登录后手动完成）："
info "  1. 手机安装 KDE Connect app（Android / iOS 均可）"
info "  2. 打开 DMS Settings → Plugins → Scan for Plugins"
info "  3. 启用 DankKDEConnect，将手机电量 widget 添加到 DankBar layout"
info "  4. 执行 dms restart 重启 shell"
info "  5. 在手机 / 桌面端的 Valent UI 中完成配对"
