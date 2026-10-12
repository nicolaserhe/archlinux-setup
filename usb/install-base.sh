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

set -Eeuo pipefail

USB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$USB_DIR/lib.sh"

[[ $EUID -eq 0 ]] || die "Run as root in live ISO"
mountpoint -q /mnt || die "/mnt is not mounted. Partition + mkfs + mount manually first."

# -- 时钟（pacman 验签的前提）--------------------------------------------------
# live ISO 的时钟来自主板 RTC，可能已经偏了几十秒到几分钟。偏多了 pacman 会报
# "invalid or corrupted package (PGP signature)" —— 那不是包坏了，是时钟不对。
# 所以放在 pacstrap 之前，而且要在镜像源之前（同一把钥匙要走 keyring 校验）。
# 装完的系统由 scripts/core/system-services.sh 启用 systemd-timesyncd 接管。
log "NTP: enabling in live environment"
# 用仓库里那份国内 NTP 列表，不用 live 环境自带的默认值：默认 NTP= 是空的，只剩
# FallbackNTP 的 arch pool，在国内经常超时 —— 而这步失败恰恰会把 pacstrap 验签交给
# 一个可能偏了几分钟的时钟。跟已装系统部署的是同一个文件，只有一处真源。
_ntp_conf="$(cd "$USB_DIR/.." && pwd)/config/timesyncd/60-cn-ntp.conf"
if [[ -f "$_ntp_conf" ]]; then
    install -Dm644 "$_ntp_conf" /etc/systemd/timesyncd.conf.d/60-cn-ntp.conf
else
    warn "NTP: repo drop-in not found, falling back to the live environment defaults"
fi
unset _ntp_conf
timedatectl set-ntp true
for _ in {1..15}; do
    [[ "$(timedatectl show -p NTPSynchronized --value)" == "yes" ]] && break
    sleep 1
done
if [[ "$(timedatectl show -p NTPSynchronized --value)" == "yes" ]]; then
    log "NTP: clock synchronized"
else
    warn "NTP: not synchronized yet -- if pacstrap reports PGP signature errors, fix the clock first"
fi
unset _

# -- 镜像源（清华/中科大/阿里 prepend 到现有 mirrorlist 上面）-----------------
# 幂等守卫：与 fstab/archlinuxcn 同样的模式，避免中途失败重跑时把 CN mirror
# 翻倍写入
if grep -q 'mirrors.tuna.tsinghua.edu.cn' /etc/pacman.d/mirrorlist; then
    warn "CN mirrors already in mirrorlist, skipping prepend"
else
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
fi
pacman -Syy

# -- CPU 微码（Intel/AMD 自动选）---------------------------------------------
UCODE=""
if grep -q '^vendor_id.*GenuineIntel' /proc/cpuinfo; then
    UCODE=intel-ucode
elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo; then
    UCODE=amd-ucode
fi
if [[ -n "$UCODE" ]]; then
    log "CPU microcode: $UCODE"
else
    warn "Unknown CPU vendor, skipping microcode"
fi

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
