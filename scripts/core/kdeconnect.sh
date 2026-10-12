#!/usr/bin/env bash
# =============================================================================
# scripts/core/kdeconnect.sh -- KDE Connect (kdeconnectd) + DankKDEConnect 插件
#
# 后端选型：上游 KDE Connect，不用 Valent。
#   - kdeconnect 在官方仓库、随 KDE Gear 稳定发版；Valent 是 AUR 的 alpha 软件
#     （1.0.0.alpha.x），协议层 CVE 也只在 alpha 通道修
#   - DankKDEConnect 插件两种后端都支持（services/KDEConnectService.qml），
#     换后端不丢功能
#
# 启动路径：包自带 /etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop，
# 而 niri.service 带 Wants=xdg-desktop-autostart.target，systemd 的
# xdg-autostart-generator 会据此生成受管的
# app-org.kde.kdeconnect.daemon@autostart.service。
# 所以这里既不写 niri spawn-at-startup，也不自建 unit —— 少一条拉起路径就少一个
# 重复实例的来源（同 fcitx5 那次的教训，见 docs/quirks/input-and-fonts.md）。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 包安装 -------------------------------------------------------------------
# kdeconnect:      KDE Connect 守护进程 + kdeconnect-cli
# sshfs:           kdeconnect 的可选依赖，「浏览设备文件」（SFTP）需要。但它只是
#                  客户端 —— 对端得自己提供 SFTP 服务端；Windows 版 KDE Connect
#                  不提供，对 win 这类对端该功能不可用（见 docs/quirks/kdeconnect.md）
# nautilus-python: nautilus 加载 Python 扩展的桥。右键 Send to device 由
#                  kdeconnect 自带的 /usr/share/nautilus-python/extensions/
#                  kdeconnect-share.py 提供，没有这个桥就不加载
header "KDE Connect packages"
pacman_install kdeconnect sshfs nautilus-python

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

success "KDE Connect done"
