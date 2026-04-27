#!/usr/bin/env bash
# =============================================================================
# scripts/core/01-pacman-base.sh -- pacman 基础包（root 阶段，install.sh 调用）
#
# 此脚本仅装"通用基础设施"——具体功能模块（compositor / audio / fcitx 等）
# 各自的 pacman/AUR 依赖由对应 core/<name>.sh 在用户阶段安装。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 全量升级 -----------------------------------------------------------------
# 本地 pacman db 记录的版本可能比镜像实际文件新（镜像未同步），
# 直接 pacman -S 安装会出现 404；先 -Syu 让本地 db 与镜像对齐
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

    if [[ -f /var/lib/pacman/sync/archlinuxcn.db ]]; then
        success "archlinuxcn database already present"
    else
        info "archlinuxcn database missing, syncing..."
        pacman -Sy --noconfirm
        pacman -S --noconfirm archlinuxcn-keyring
        success "archlinuxcn database synced"
    fi
}

header "archlinuxcn"
_setup_archlinuxcn

# -- Base ---------------------------------------------------------------------
# curl / wget:  HTTP 命令行下载工具
# less:         分页查看文本
# base-devel:   编译工具链（gcc、make、pkgconf 等），AUR 构建必需
# git:          版本控制
# python:       Python 运行时
# expect:       自动化交互式命令行程序的脚本工具，setup 脚本依赖
# man-db:       man 手册页查看器（man 命令本身）
# man-pages:    Linux 系统调用与 C 库英文手册集（man 2/3 节）
# imagemagick:  图片处理（convert 等），system boot 的 GRUB matter 主题依赖
# zip / unzip:  压缩解压
# usbutils:     USB 设备诊断（lsusb）
# lsof:         列出进程打开的文件（调试端口占用等）
header "Base dependencies"
pacman_install \
    curl \
    wget \
    less \
    base-devel \
    git \
    python \
    expect \
    man-db \
    man-pages \
    imagemagick \
    zip \
    unzip \
    7zip \
    usbutils \
    lsof \
    gdu

# -- 多媒体（基础体验）-------------------------------------------------------
# gst-plugins-base/good + gst-libav: GStreamer 核心
# qt6-multimedia-ffmpeg:    Qt6 多媒体后端
# ffmpegthumbnailer:        视频缩略图
# kimageformats:            AVIF/HEIF 等额外图片格式支持
# cava:                     音频可视化 widget
header "Multimedia"
pacman_install \
    gst-plugins-base \
    gst-plugins-good \
    gst-libav \
    qt6-multimedia-ffmpeg \
    ffmpegthumbnailer \
    kimageformats \
    cava

# -- 开发语言 -----------------------------------------------------------------
header "Dev languages"
pacman_install go rust nodejs npm

# -- System services 基础 -----------------------------------------------------
# cups-pk-helper:        打印机 polkit helper
# flatpak:               通用 Linux 应用沙箱打包框架
# gvfs-smb:              GVFS SMB/Windows 网络共享挂载支持
# accountsservice:       持久化用户头像与账户配置（DMS 头像依赖）
# polkit-gnome:          polkit 认证代理（GUI 应用提权弹密码框）
header "System service basics"
pacman_install \
    cups-pk-helper \
    flatpak \
    gvfs-smb \
    accountsservice \
    polkit-gnome

# -- 基础桌面应用 -------------------------------------------------------------
# nautilus:           文件管理器（DMS 不自带）
# gpu-screen-recorder: 硬件编码屏幕录制（VAAPI/NVENC，CPU 占用 1-3%）
# localsend:          局域网跨平台文件传输工具
# file-roller:        GNOME 归档管理器（图形化解压缩）
# adw-gtk-theme:      Adwaita GTK 3/4 主题，让 GTK 应用风格统一
# libreoffice-fresh:  办公套件（Writer / Calc / Impress）
# libnotify:          桌面通知客户端库（notify-send 命令）
# grim / slurp:       Wayland 截图工具（DMS 的 `dms screenshot` 底层依赖）
# wl-clipboard:       Wayland 剪贴板读写工具（wl-copy / wl-paste）
# cliphist:           剪贴板历史管理器
# gnome-keyring:      GNOME 密钥环
# loupe:              GTK4 图片查看器
# celluloid:          mpv GTK 前端（视频播放器）
# gnome-calculator:   GTK4 计算器
# gnome-disk-utility: 图形化磁盘管理（格式化/挂载/SMART）
header "Base desktop apps"
pacman_install \
    nautilus \
    gpu-screen-recorder \
    localsend \
    file-roller \
    adw-gtk-theme \
    libreoffice-fresh \
    libnotify \
    grim \
    slurp \
    wl-clipboard \
    cliphist \
    gnome-keyring \
    loupe \
    celluloid \
    gnome-calculator \
    gnome-disk-utility \
    gammastep

success "pacman base done"
