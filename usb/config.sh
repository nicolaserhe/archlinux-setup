#!/usr/bin/env bash
# =============================================================================
# usb/config.sh -- 新系统首次启动后的最小化 chroot 配置
#
# 在 arch-chroot /mnt 后执行，完成时区 / locale / 主机名 / hosts / root 密码。
# 与本仓库的桌面安装流程解耦：本脚本只覆盖 README 中"系统配置"章节的步骤。
# =============================================================================

set -euo pipefail

USB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$USB_DIR/lib.sh"

# -- 前置检查 -----------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Please run as root inside arch-chroot"

# -- 时区 ---------------------------------------------------------------------
log "Setting timezone to Asia/Shanghai"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
success "Timezone configured"

# -- locale -------------------------------------------------------------------
log "Configuring locale (en_US.UTF-8 / zh_CN.UTF-8)"
sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(zh_CN\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
success "Locale configured"

# -- 主机名 + hosts -----------------------------------------------------------
hostname=""
while [[ -z "$hostname" ]]; do
    read -rp "Enter hostname: " hostname
    [[ -n "$hostname" ]] || warn "Hostname cannot be empty"
done
echo "$hostname" > /etc/hostname
success "Hostname set: $hostname"

cat >/etc/hosts <<EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    ${hostname}.localdomain    ${hostname}
EOF
success "/etc/hosts written"

# -- root 密码 ----------------------------------------------------------------
log "Setting root password"
passwd
success "Root password updated"
