#!/usr/bin/env bash
# =============================================================================
# scripts/packages/pacman.sh -- pacman 官方源软件包（以 root 运行）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

# -- archlinuxcn 源 -----------------------------------------------------------
_setup_archlinuxcn() {
    if grep -q '^\[archlinuxcn\]' /etc/pacman.conf; then
        warn "archlinuxcn repo already in pacman.conf, skipping write"
    else
        info "Adding archlinuxcn repo"
        tee -a /etc/pacman.conf >/dev/null <<'EOF'

[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/$arch
Server = https://repo.huaweicloud.com/archlinuxcn/$arch
EOF
    fi

    # 无论配置是否已存在，数据库文件可能从未下载，总是检查并同步
    local db_file="/var/lib/pacman/sync/archlinuxcn.db"
    if [[ ! -f "$db_file" ]]; then
        info "archlinuxcn database missing, syncing..."
        pacman -Sy --noconfirm
        pacman -S --noconfirm archlinuxcn-keyring
        success "archlinuxcn database synced"
    else
        success "archlinuxcn database already present"
    fi
}

header "archlinuxcn"
_setup_archlinuxcn

# -- Base ---------------------------------------------------------------------
header "Base dependencies"
# curl:       脚本内用于验证代理连通性
# less:       分页阅读器
# base-devel: AUR 构建必须（gcc / make / pkg-config 等）
# git:        克隆插件 / AUR 源码
# python:     proxy.sh 中用 python3 修补 mihomo 配置（显式声明，不靠隐式依赖）
pacman_install \
    curl \
    less \
    base-devel \
    git \
    python

# -- Editor -------------------------------------------------------------------
header "Editor"
# neovim: 主编辑器（.zshrc 中 EDITOR=nvim，alacritty / shell 均依赖）
pacman_install \
    neovim

# -- Shell --------------------------------------------------------------------
header "Shell"
pacman_install \
    zsh

# -- CLI tools ----------------------------------------------------------------
header "CLI tools"
# lsd:       替代 ls
# starship:  跨 shell 提示符
# duf:       替代 df
# fd:        替代 find
# zoxide:    智能 cd
# fzf:       模糊搜索
# ripgrep:   替代 grep
# bat:       替代 cat，语法高亮
# tldr:      简化版 man
# fastfetch: 系统信息展示
pacman_install \
    lsd \
    starship \
    duf \
    fd \
    zoxide \
    fzf \
    ripgrep \
    bat \
    tldr \
    fastfetch

# -- Desktop / Wayland --------------------------------------------------------
header "Desktop / Wayland"
# niri:                    基于 smithay 的平铺式 Wayland 合成器
# xwayland-satellite:      让 X11 应用在 niri 下独立运行，无需内置 XWayland
# xorg-xwayland:           XWayland 服务端，xwayland-satellite 的运行时依赖（显式声明）
# xdg-desktop-portal:      portal 框架基础包
# xdg-desktop-portal-gtk:  文件选择器 / 通知等门户；
#                          不安装 xdg-desktop-portal-gnome，避免拉入 gnome-shell
# gnome-keyring:           密钥环（SSH / GPG / 浏览器密码）
# greetd:                  轻量登录管理器，替代 gdm，不依赖 GNOME 组件
# fuzzel:                  Wayland 原生应用启动器
# alacritty:               GPU 加速终端
# libnotify:               notify-send，发送桌面通知
# mako:                    Wayland 通知守护进程
# grim:                    Wayland 截图工具
# slurp:                   鼠标框选屏幕区域，配合 grim 使用
# wl-clipboard:            Wayland 剪贴板命令行工具
# cliphist:                剪贴板历史管理
pacman_install \
    niri \
    xwayland-satellite \
    xorg-xwayland \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    gnome-keyring \
    greetd \
    fuzzel \
    alacritty \
    libnotify \
    mako \
    grim \
    slurp \
    wl-clipboard \
    cliphist

# -- Bluetooth ----------------------------------------------------------------
header "Bluetooth"
pacman_install \
    bluez \
    bluez-utils \
    blueman

# -- Audio --------------------------------------------------------------------
header "Audio"
# pipewire / pipewire-pulse / wireplumber: 现代音频栈，替代 PulseAudio
pacman_install \
    pipewire \
    pipewire-pulse \
    wireplumber

# -- Multimedia ---------------------------------------------------------------
header "Multimedia"
pacman_install \
    gst-plugins-base \
    gst-plugins-good \
    gst-libav

# -- Fonts --------------------------------------------------------------------
header "Fonts"
# noto-fonts-cjk: 中日韩字体，防止方块乱码
# （Maple Mono NL NF CN 在 aur.sh 中安装）
pacman_install \
    noto-fonts-cjk

# -- Fcitx5 -------------------------------------------------------------------
header "Fcitx5"
pacman_install \
    fcitx5 \
    fcitx5-gtk \
    fcitx5-qt \
    fcitx5-configtool \
    fcitx5-rime \
    librime

# -- Apps ---------------------------------------------------------------------
header "Apps"
# flclash:           Clash Meta 图形客户端
# localsend:         局域网文件互传
# ffmpegthumbnailer: 视频缩略图
# gvfs-smb:          挂载 Windows 共享目录
# file-roller:       归档管理器
# flatpak:           沙盒应用运行时
pacman_install \
    flclash \
    localsend \
    ffmpegthumbnailer \
    gvfs-smb \
    file-roller \
    flatpak

success "pacman packages done"
