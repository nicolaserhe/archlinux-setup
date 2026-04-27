# Arch Linux 安装手册

---

## 准备工作

### 下载 ISO

[https://archlinux.org/download/](https://archlinux.org/download/)

### 制作启动盘

```bash
dd if=archlinux.iso of=/dev/sdX bs=4M conv=fsync oflag=direct status=progress
```

> Note：`/dev/sdX` 代表 U 盘设备，请勿误写为系统硬盘。

---

## 联网

### 有线网络

插入网线后通常可直接联网，验证连通性：

```bash
ping archlinux.org
```

### Wi-Fi

```bash
iwctl
device list
station <device> scan
station <device> get-networks
station <device> connect "WiFi名称"
exit
```

---

## 设置时间

```bash
timedatectl set-ntp true
```

---

## 磁盘分区

### 查看磁盘

```bash
lsblk
```

通过输出确认目标磁盘名称，例如 `/dev/sda` 或 `/dev/nvme0n1`，下文以 `/dev/xxx` 代指。

### 确认磁盘分区表类型为 GPT

cfdisk 无法在运行中切换分区表类型。如果磁盘当前是 MBR/DOS 格式，需要先用 parted 将其转换为 GPT，**此操作会清除磁盘上的所有数据**。

查看当前分区表类型：

```bash
parted /dev/xxx print
```

输出中 `Partition Table:` 一行若显示 `msdos`，则需要执行转换；若已是 `gpt` 可跳过此步。

转换为 GPT：

```bash
parted /dev/xxx mklabel gpt
```

### 使用 cfdisk 分区（UEFI + GPT）

```bash
cfdisk /dev/xxx
```

推荐分区方案：

| 分区 | 类型 | 建议大小 | 挂载点 |
|------|------|----------|--------|
| EFI 系统分区 | EFI System | 512 MiB | `/boot` |
| 根分区 | Linux filesystem | 剩余全部空间 | `/` |

> EFI 分区供引导程序使用，根分区用于安装 Arch Linux 主体系统。

---

## 格式化分区

### EFI 分区

```bash
mkfs.fat -F 32 <EFI 分区>
```

### 根分区

```bash
mkfs.ext4 <ROOT 分区>
```

---

## 挂载分区

```bash
mount <ROOT 分区> /mnt
mkdir -p /mnt/boot
mount <EFI 分区> /mnt/boot
```

---

## 安装系统

### 配置国内镜像源（加快下载速度）

编辑 `/etc/pacman.d/mirrorlist`，在文件最顶部插入以下内容：

```
# 清华大学
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
# 中国科学技术大学
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
# 阿里云
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch
```

刷新 pacman 数据库：

```bash
pacman -Syy
```

### 安装基础系统
 
**必要软件包**（缺少任一系统将无法正常运行）：
 
```bash
pacstrap /mnt base linux linux-firmware
```
 
| 包名 | 说明 |
|------|------|
| `base` | Arch Linux 核心基础包组 |
| `linux` | Linux 内核 |
| `linux-firmware` | 硬件固件（网卡、显卡等驱动所需） |
 
```bash
pacstrap /mnt networkmanager vim
```
 
| 包名 | 说明 |
|------|------|
| `networkmanager` | 网络管理工具，缺少则重启后无法联网 |
| `vim` | 文本编辑器，进入新系统后需要编辑配置文件 |

---

## 系统配置

### 生成 fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

> 此命令会将当前挂载信息（含 UUID）写入新系统的 `/etc/fstab`，供开机时自动挂载分区使用。

### 进入新系统

```bash
arch-chroot /mnt
```

---

### 设置时区

```bash
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
```

---

### 设置语言

编辑 `/etc/locale.gen`，取消以下两行的注释：

```
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
```

生成 locale：

```bash
locale-gen
```

设置系统默认语言：

```bash
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

---

### 设置主机名

```bash
echo "<hostname>" > /etc/hostname
```

编辑 `/etc/hosts`，写入以下内容（将 `<hostname>` 替换为实际主机名）：

```
127.0.0.1   localhost
::1         localhost
127.0.1.1   <hostname>.localdomain <hostname>
```

---

### 设置 root 密码

```bash
passwd
```

---

## 安装引导程序（systemd-boot）

> ⚠️ 此步骤不可跳过，否则重启后系统无法启动。

### 安装 systemd-boot 到 EFI 分区

```bash
bootctl install
```

### 配置引导加载器

编辑 `/boot/loader/loader.conf`，写入：

```
default arch.conf
timeout 3
console-mode max
editor no
```

### 创建启动条目

首先获取根分区的 UUID：

```bash
blkid -s UUID -o value <ROOT 分区>
```

将输出的 UUID 记下，然后创建 `/boot/loader/entries/arch.conf`，写入以下内容（将 `<UUID>` 替换为上一步得到的值）：

```
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=<UUID> rw
```

### 验证配置

```bash
bootctl list
```

确认输出中包含 `Arch Linux` 条目即为成功。

---

## 安装引导程序（GRUB，可选）

> 如果你已使用 systemd-boot，跳过本节。二者选其一即可，**不要同时安装**。
>
> GRUB 功能更全面，适合需要多系统引导或偏好图形化引导菜单的场景。

### 安装所需软件包

```bash
pacman -S grub efibootmgr
```

| 包名 | 说明 |
|------|------|
| `grub` | GRUB 引导程序本体 |
| `efibootmgr` | 用于向 UEFI 固件写入启动项，UEFI 模式下必须安装 |

如果需要双系统，额外安装：

```bash
pacman -S os-prober
```

### 将 GRUB 安装到 EFI 分区

```bash
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
```

| 参数 | 说明 |
|------|------|
| `--target=x86_64-efi` | 指定目标平台为 64 位 UEFI |
| `--efi-directory=/boot` | EFI 分区的挂载点 |
| `--bootloader-id=GRUB` | 在 UEFI 固件中显示的引导项名称，可自定义 |

### 生成 GRUB 配置文件

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

> 此命令会自动探测已安装的系统内核并生成启动菜单。若安装了 `os-prober`，还会自动检测其他操作系统并将其加入菜单。

#### 启用 os-prober（双系统时）

默认情况下 `os-prober` 在生成配置时不会自动运行，需要先编辑 `/etc/default/grub`，取消以下行的注释（或手动添加）：

```
GRUB_DISABLE_OS_PROBER=false
```

然后重新执行 `grub-mkconfig`。

### 验证配置

```bash
cat /boot/grub/grub.cfg | grep menuentry
```

输出中应包含类似 `menuentry 'Arch Linux'` 的条目，确认生成成功。

---

## 启用网络服务

在重启前启用 NetworkManager，确保进入系统后可以正常联网：

```bash
systemctl enable NetworkManager
```

---

## 退出并重启

```bash
exit
reboot
```

重启后拔出 U 盘，系统应能正常进入 Arch Linux。
