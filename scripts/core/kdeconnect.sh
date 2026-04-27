#!/usr/bin/env bash
# =============================================================================
# scripts/core/kdeconnect.sh -- KDE Connect / Valent + DankKDEConnect 插件
#
# DMS 的 Phone Connect 通过 DankKDEConnect 社区插件 + Valent 后端实现：
#   - DankBar 显示手机电量
#   - 接收手机通知、传输文件、同步剪贴板
#
# niri config.kdl 的写入（Valent spawn-at-startup）已统一由 dms.sh 处理，
# 本脚本只负责包安装、插件部署和 environment.d 配置。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 包安装 -------------------------------------------------------------------
# valent:           KDE Connect 的 GNOME/GTK 实现，DankKDEConnect 插件后端
# nautilus-python:  nautilus 加载 Python 扩展的桥，供下面的右键发送扩展用
header "KDE Connect packages"
aur_install valent
pacman_install nautilus-python

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
        # install.sh _cleanup 清理 /tmp/dms-plugins.*
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

# -- Nautilus 右键 'Send to <device>' 扩展 -----------------------------------
header "Nautilus right-click Valent send"
_ext_dir="$HOME/.local/share/nautilus-python/extensions"
mkdir -p "$_ext_dir"
cp "$REPO_DIR/config/helpers/valent-send/valent_send.py" "$_ext_dir/valent_send.py"
success "Deployed: $_ext_dir/valent_send.py"
info "Run 'nautilus -q' once to reload extensions (扩展只在 nautilus 启动时加载)"
unset _ext_dir

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

success "KDE Connect / Valent done"
