#!/usr/bin/env bash
# =============================================================================
# usb/install-base.sh -- live ISO 内的"无脑"部分：镜像源 + pacstrap + 拷脚本
#
# 前置条件（**手动**完成，避免脚本误格式化盘）：
#   1. 启动 live ISO、联网
#   2. 用 cfdisk / sfdisk 分区
#   3. mkfs.fat / mkfs.ext4 格式化
#   4. mount 根分区到 /mnt、EFI 到 /mnt/boot
#
# 然后跑：bash usb/install-base.sh （会自动写 /etc/fstab）
#
# 跑完后还需要手动：
#   arch-chroot /mnt
#   bash /root/usb-bootstrap/in-chroot.sh   # 交互问 bootloader（systemd-boot 时再问根分区）
#   exit && umount -R /mnt && reboot
# =============================================================================

set -euo pipefail

USB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$USB_DIR/lib.sh"

[[ $EUID -eq 0 ]] || die "Run as root in live ISO"
mountpoint -q /mnt || die "/mnt is not mounted. Partition + mkfs + mount manually first."

# -- 镜像源（清华/中科大/阿里 prepend 到现有 mirrorlist 上面）-----------------
log "Prepending CN mirrors to /etc/pacman.d/mirrorlist"
{
    cat <<'EOF'
# 清华大学
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
# 中国科学技术大学
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
# 阿里云
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch
EOF
    cat /etc/pacman.d/mirrorlist
} >/tmp/mirrorlist.merged
mv /tmp/mirrorlist.merged /etc/pacman.d/mirrorlist
pacman -Syy

# -- CPU 微码（Intel/AMD 自动选）---------------------------------------------
UCODE=""
if grep -q '^vendor_id.*GenuineIntel' /proc/cpuinfo; then
    UCODE=intel-ucode
elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo; then
    UCODE=amd-ucode
fi
[[ -n "$UCODE" ]] && log "CPU microcode: $UCODE" || warn "Unknown CPU vendor, skipping microcode"

# -- pacstrap（最小集 + 微码）-------------------------------------------------
log "Running pacstrap (this takes a few minutes)"
pacstrap /mnt base linux linux-firmware networkmanager vim ${UCODE:-}

# -- fstab（genfstab 读 /proc/mounts 写入 UUID 条目）-------------------------
# 守一下幂等：已写过 UUID 条目就跳过，避免重跑时把 fstab 翻倍
if grep -q '^UUID=' /mnt/etc/fstab 2>/dev/null; then
    warn "fstab already has UUID entries, skipping genfstab"
else
    log "Generating /etc/fstab"
    genfstab -U /mnt >>/mnt/etc/fstab
fi

# -- 拷 chroot 阶段需要的脚本到 /mnt/root/usb-bootstrap/ ----------------------
log "Copying chroot scripts to /mnt/root/usb-bootstrap/"
mkdir -p /mnt/root/usb-bootstrap
cp "$USB_DIR/in-chroot.sh" "$USB_DIR/lib.sh" /mnt/root/usb-bootstrap/

success "Base done. Next steps (manual):"
echo
echo "  arch-chroot /mnt"
echo "  bash /root/usb-bootstrap/in-chroot.sh"
echo "  # in-chroot.sh prompts for bootloader (1=grub, 2=systemd-boot, Enter=1)"
echo "  # systemd-boot branch also prompts for root partition path (grub does not need it)"
echo "  exit && umount -R /mnt && reboot"
