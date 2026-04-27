#!/bin/bash

# 确保脚本以 root 身份执行
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# 设置时区
echo "Setting timezone to Shanghai..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

# 配置语言环境 (locale)
echo "Configuring locale..."
# 注释掉原有的 locale 配置并添加新的配置
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf

# 设置主机名
echo "Setting hostname..."
read -p "Enter your hostname: " hostname
echo "$hostname" >/etc/hostname

# 配置 /etc/hosts
echo "Configuring /etc/hosts..."
cat <<EOF >/etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    $hostname.localdomain    $hostname
EOF

# 设置 root 密码
echo "Setting root password..."
passwd
