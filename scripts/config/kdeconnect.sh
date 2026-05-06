#!/usr/bin/env bash
# =============================================================================
# scripts/config/kdeconnect.sh -- KDE Connect / Valent + DankKDEConnect 插件
#
# DMS 1.4 的 Phone Connect 通过 DankKDEConnect 官方插件 + Valent 后端实现：
#   - DankBar 显示手机电量
#   - 接收手机通知、传输文件、同步剪贴板
#
# SSH_AUTH_SOCK 通过 environment.d 写入：niri config.kdl 中 dms.sh 已经
# 追加过一个 environment {} 块，niri 不允许重复，因此环境变量必须走
# environment.d。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

# -- DankKDEConnect 插件 ------------------------------------------------------
header "DankKDEConnect plugin"
_plugins_dir="$HOME/.config/DankMaterialShell/plugins"
_kdeconnect_dst="$_plugins_dir/DankKDEConnect"

if [[ -d "$_kdeconnect_dst" ]]; then
    warn "DankKDEConnect plugin already installed: $_kdeconnect_dst"
else
    mkdir -p "$_plugins_dir"
    (
        set -euo pipefail
        _tmp="$(mktemp -d /tmp/dms-plugins.XXXXXX)"
        trap 'rm -rf "$_tmp"' EXIT

        git_clone "$_tmp/dms-plugins" https://github.com/AvengeMedia/dms-plugins

        if [[ -d "$_tmp/dms-plugins/DankKDEConnect" ]]; then
            cp -r "$_tmp/dms-plugins/DankKDEConnect" "$_kdeconnect_dst"
            success "DankKDEConnect plugin installed: $_kdeconnect_dst"
        else
            warn "DankKDEConnect subdirectory not found in dms-plugins repo"
        fi
    )
fi
unset _plugins_dir _kdeconnect_dst

# -- SSH_AUTH_SOCK 写入 environment.d -----------------------------------------
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
# 仅追加 spawn-at-startup，不再新增 environment {} 块以免与 dms.sh 冲突
header "Valent niri spawn-at-startup"
_niri_cfg="$HOME/.config/niri/config.kdl"

if [[ ! -f "$_niri_cfg" ]]; then
    mkdir -p "$(dirname "$_niri_cfg")"
    touch "$_niri_cfg"
    warn "niri config does not exist -- created empty file"
fi

if grep -q 'valent' "$_niri_cfg"; then
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
info "  2. 打开 DMS Settings -> Plugins -> Scan for Plugins"
info "  3. 启用 DankKDEConnect，将手机电量 widget 添加到 DankBar layout"
info "  4. 执行 dms restart 重启 shell"
info "  5. 在手机 / 桌面端的 Valent UI 中完成配对"
