#!/usr/bin/env bash
# =============================================================================
# scripts/core/pacman-base.sh -- pacman 基础包（root 阶段，install.sh 调用）
#
# 此脚本仅装"通用基础设施"——具体功能模块（compositor / audio / fcitx 等）
# 各自的 pacman/AUR 依赖由对应 core/<name>.sh 在用户阶段安装。
# =============================================================================

set -Eeuo pipefail

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

        # archlinuxcn-keyring 由 archlinuxcn 仓库自己 ship（鸡生蛋），但**不需要**
        # 手动 import key：该包由 felixonmars 的 packager key
        # B5971F2C5C10A9A08C60030F786C63F330D7CB92 签名，而这个 key 随官方
        # archlinux-keyring 一起装在机器上（上面那次 `pacman -Syu` 刚刷新过它），
        # 验签直接过 —— 上游 README 给的也就是 `pacman -Sy && pacman -S
        # archlinuxcn-keyring` 这两条。
        #
        # 老版本按 email UID `pacman-key --recv-keys farseerfc@archlinux.org` 手动
        # 导入：实测该 UID 现在解析到一把 2026-05-06 过期、且已被 disable 的
        # ed25519 key，而且 email 查询本身会命中多把 key（`--lsign-key` 报
        # ambiguous）—— 要么失败要么签错，纯噪音。
        if ! pacman -S --noconfirm archlinuxcn-keyring; then
            error "Failed to install archlinuxcn-keyring"
            error "  It is signed by felixonmars' key, which ships in the official archlinux-keyring."
            error "  Diagnose with: pacman-key --list-keys felixonmars@archlinux.org"
            return 1
        fi
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

# -- 开发工具链 ---------------------------------------------------------------
# clang:       C/C++ 编译器，AUR 包编译依赖（rust -sys binding 等需要）
# bash lint:   shellcheck（仓库根 .shellcheckrc 配置规则集）
#              注意：这行不能写成 "# shellcheck: ..." —— shellcheck 会把
#              行首的 "# shellcheck " 当成指令解析，报 SC1073/SC1072。
header "Dev tools"
pacman_install clang shellcheck

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
# gnome-keyring:      GNOME 密钥环
# loupe:              GTK4 图片查看器
# celluloid:          mpv GTK 前端（视频播放器）
# gnome-calculator:   GTK4 计算器
# gnome-disk-utility: 图形化磁盘管理（格式化/挂载/SMART）
# 不装 gammastep / cliphist：夜间模式与剪贴板历史 DMS 自带
# （`dms ipc call night` / `dms ipc call clipboard`，Mod+V 已绑后者），
# 见 docs/decisions.md。
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
    tesseract \
    tesseract-data-eng \
    tesseract-data-chi_sim \
    wl-clipboard \
    gnome-keyring \
    loupe \
    celluloid \
    gnome-calculator \
    gnome-disk-utility

# -- PAM: fix system-auth ------------------------------------------------------
# Arch 默认 system-auth 有三个坑：
# 1. pam_unix.so 带 try_first_pass nullok —— pam_systemd_home.so（前面模块）可能
#    误设空 token，pam_unix 复用它跳过密码提示 → conversation failed。
#    解决：去掉 try_first_pass nullok，pam_unix 独立弹密码提示。
# 2. pam_systemd_home.so 在 auth 栈但 systemd-homed 未启用 —— [success=2] 可能
#    错误跳过 pam_unix。直接删除该行。
# 3. pam_faillock.so authsucc 是 required，但 auditd 默认不跑 → authsucc 失败
#    导致整个认证回滚（即使密码正确）。改成 optional。
# 4. faillock deny=3 太敏感，无 TTY 后台进程触发 polkit 认证失败是正常的，3 次就
#    锁账户太激进。提到 10 次。
header "PAM fixes"

# 1. pam_unix.so: strip try_first_pass nullok
if grep -q '^auth\s\+.*pam_unix\.so\s\+try_first_pass' /etc/pam.d/system-auth; then
    sed -i 's/^\(auth\s\+.*pam_unix\.so\).*/\1/' /etc/pam.d/system-auth
    success "Removed try_first_pass from pam_unix.so"
else
    success "pam_unix.so already clean"
fi

# 2. Remove pam_systemd_home.so from auth section
if grep -q 'pam_systemd_home\.so' /etc/pam.d/system-auth; then
    sed -i '/^-\?auth\s\+.*pam_systemd_home\.so/d' /etc/pam.d/system-auth
    success "Removed pam_systemd_home.so from auth stack"
else
    success "pam_systemd_home.so already removed from auth"
fi

# 3. pam_faillock.so authsucc: required → optional (auditd not running)
if grep -q '^auth\s\+required\s\+pam_faillock\.so\s\+authsucc' /etc/pam.d/system-auth; then
    sed -i 's/^auth\s\+required\s\+pam_faillock\.so\s\+authsucc/auth       optional                    pam_faillock.so      authsucc/' /etc/pam.d/system-auth
    success "pam_faillock authsucc: required → optional"
else
    success "pam_faillock authsucc already optional"
fi

# 4. Relax faillock deny limit (3 → 10)
sed -i 's/^#\s*deny = 3$/deny = 10/' /etc/security/faillock.conf
if grep -q '^deny = 10' /etc/security/faillock.conf; then
    success "faillock deny set to 10"
else
    warn "faillock deny not updated (unexpected config format)"
fi

success "pacman base done"
