#!/usr/bin/env bash
# =============================================================================
# usb/in-chroot.sh -- arch-chroot 内手动执行的收尾脚本
#
# install-base.sh 已把本脚本拷到 /mnt/root/usb-bootstrap/in-chroot.sh，
# 用户 arch-chroot /mnt 后直接 `bash /root/usb-bootstrap/in-chroot.sh` 跑。
#
# 流程：时区 / locale / hostname / hosts / root pw / bootloader / NetworkManager
#
# 零参数，所有需要的信息脚本内完成：
#   - CPU 微码：grep /proc/cpuinfo（arch-chroot 已 bind /proc）自检
#   - bootloader：交互菜单 1=grub / 2=systemd-boot
#   - 根分区路径：仅 systemd-boot 分支才问（grub 不需要）
# =============================================================================

set -euo pipefail

USB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$USB_DIR/lib.sh"

[[ $EUID -eq 0 ]] || die "Run as root inside arch-chroot"

# -- CPU 微码自检（同 install-base.sh，arch-chroot 已 bind /proc）-----------
UCODE=""
if grep -q '^vendor_id.*GenuineIntel' /proc/cpuinfo; then
    UCODE=intel-ucode
elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo; then
    UCODE=amd-ucode
fi
[[ -n "$UCODE" ]] && log "CPU microcode: $UCODE" || warn "Unknown CPU vendor, skipping microcode"

# 交互选 bootloader 编号
echo "Bootloader options:" >&2
echo "  1) grub (default)" >&2
echo "  2) systemd-boot" >&2
read -rp "Select [1-2, Enter=1]: " choice
case "${choice:-1}" in
    1) BOOTLOADER=grub ;;
    2) BOOTLOADER=systemd-boot ;;
    *) die "Invalid choice: $choice" ;;
esac
log "Bootloader: $BOOTLOADER"

# -- 1. 时区 ------------------------------------------------------------------
log "Setting timezone to Asia/Shanghai"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
success "Timezone configured"

# -- 2. locale ----------------------------------------------------------------
log "Configuring locale (en_US.UTF-8 / zh_CN.UTF-8)"
sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(zh_CN\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
success "Locale configured"

# -- 3. hostname + /etc/hosts -------------------------------------------------
hostname=""
while [[ -z "$hostname" ]]; do
    read -rp "Enter hostname: " hostname
    [[ -n "$hostname" ]] || warn "Hostname cannot be empty"
done
echo "$hostname" > /etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    ${hostname}.localdomain    ${hostname}
EOF
success "Hostname set: $hostname"

# -- 4. root 密码 -------------------------------------------------------------
log "Setting root password"
passwd
success "Root password updated"

# -- 5. Bootloader ------------------------------------------------------------
case "$BOOTLOADER" in
systemd-boot)
    log "Installing systemd-boot to /boot"
    bootctl install

    # loader.conf 内联，4 行模板没必要单独成文件
    cat >/boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 3
console-mode max
editor no
EOF

    # 交互问根分区路径（仅 systemd-boot 分支需要；列 lsblk 方便复制）
    echo "Disks/partitions:" >&2
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT >&2
    read -rp "Root partition path (e.g., /dev/sda2 or /dev/nvme0n1p2): " ROOT_DEV
    [[ -b "$ROOT_DEV" ]] || die "Not a block device: $ROOT_DEV"

    ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV")"
    [[ -n "$ROOT_UUID" ]] || die "Could not read UUID of $ROOT_DEV"

    # microcode 必须比 main initramfs **先** load（CPU 在内核早期阶段就读取）
    if [[ -n "$UCODE" ]]; then
        INITRD_BLOCK="initrd  /${UCODE}.img"$'\n'"initrd  /initramfs-linux.img"
    else
        INITRD_BLOCK="initrd  /initramfs-linux.img"
    fi

    cat >/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
${INITRD_BLOCK}
options root=UUID=${ROOT_UUID} rw
EOF

    bootctl list
    success "systemd-boot configured"
    ;;
grub)
    log "Installing GRUB to /boot"
    pacman -S --noconfirm --needed grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    success "GRUB configured"
    ;;
esac

# -- 6. NetworkManager --------------------------------------------------------
log "Enabling NetworkManager"
systemctl enable NetworkManager
success "NetworkManager enabled"

success "In-chroot phase done. exit, umount -R /mnt, reboot."
