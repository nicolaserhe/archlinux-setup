#!/usr/bin/env bash
# =============================================================================
# scripts/packages/pacman.sh -- pacman 官方源软件包（以 root 运行）
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 全量升级 -----------------------------------------------------------------
# BUG FIX: 本地 pacman db 记录的版本可能比镜像实际文件新（镜像未同步），
# 直接 pacman -S 安装时会出现版本 404。先做一次 -Syu 让本地 db 与镜像对齐。
header "System upgrade"
pacman -Syu --noconfirm
success "System upgraded"

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
pacman_install \
    curl \
    less \
    base-devel \
    git \
    python

# -- Editor -------------------------------------------------------------------
header "Editor"
pacman_install neovim

# -- Shell --------------------------------------------------------------------
header "Shell"
pacman_install zsh

# -- CLI tools ----------------------------------------------------------------
header "CLI tools"
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
# xorg-xwayland:           XWayland 服务端（xwayland-satellite 运行时依赖）
# xdg-desktop-portal-gnome: 文件选择器 / 截图 / 屏幕共享等门户（DMS 推荐）
# xdg-desktop-portal-gtk:  GTK 应用后备门户
# greetd:                  轻量登录管理器，替代 gdm
# cava:                    DMS 音频可视化 widget 依赖
# qt6-multimedia-ffmpeg:   DMS 媒体播放支持
# accountsservice:         持久化用户头像 / 配置（DMS 推荐）
pacman_install \
    niri \
    xwayland-satellite \
    xorg-xwayland \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    gnome-keyring \
    greetd \
    alacritty \
    libnotify \
    grim \
    slurp \
    wl-clipboard \
    cliphist \
    cava \
    qt6-multimedia-ffmpeg \
    accountsservice

# -- Bluetooth ----------------------------------------------------------------
header "Bluetooth"
pacman_install bluez bluez-utils

# -- Audio --------------------------------------------------------------------
header "Audio"
pacman_install pipewire pipewire-pulse wireplumber

# -- Multimedia ---------------------------------------------------------------
header "Multimedia"
pacman_install gst-plugins-base gst-plugins-good gst-libav

# -- Fonts --------------------------------------------------------------------
header "Fonts"
pacman_install noto-fonts-cjk

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
# power-profiles-daemon: 电源性能模式管理（DMS 警告消除）
# cups-pk-helper:        打印机 polkit helper（DMS 警告消除）
# kimageformats:         额外图片格式支持 AVIF/HEIF 等（DMS 警告消除）
pacman_install \
    flclash \
    localsend \
    ffmpegthumbnailer \
    gvfs-smb \
    file-roller \
    flatpak \
    power-profiles-daemon \
    cups-pk-helper \
    kimageformats \
    adw-gtk-theme \
    expect

success "pacman packages done"
