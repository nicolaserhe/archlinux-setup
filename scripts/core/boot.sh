#!/usr/bin/env bash
# =============================================================================
# scripts/core/boot.sh -- GRUB matter 主题（用户阶段，sudo 提权）
#
# matter (https://github.com/mateosss/matter) 自带安装器 matter.py，会处理：
#   - 拷贝主题到 /boot/grub/themes/Matter/
#   - 修改 /etc/default/grub 的 GRUB_THEME
#   - 调用 grub-mkconfig 重建 grub.cfg
# 我们只需要 sudo 跑 matter.py，无需手动 cp / sed / grub-mkconfig。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

# 仅在系统装了 grub 时才安装主题；UEFI 直引导（systemd-boot 等）跳过
if ! command_exists grub-mkconfig; then
    warn "grub-mkconfig not found, skipping GRUB theme"
    exit 0
fi

# 已经装过则跳过：matter.py 不幂等，重复跑会重写 GRUB_THEME 与重建 grub.cfg
if [[ -d /boot/grub/themes/Matter ]]; then
    warn "Matter theme already installed at /boot/grub/themes/Matter, skipping"
    exit 0
fi

header "GRUB matter theme"

# matter.py 需要 convert(imagemagick) 把 SVG 转 PNG；imagemagick 在 01-pacman-base.sh 已装
_tmpdir="$(mktemp -d /tmp/grub-matter.XXXXXX)"

git_clone "$_tmpdir/matter" https://github.com/mateosss/matter.git

# matter.py -i 是"安装主题 + 设置图标"复合命令；
# 图标顺序对应 /etc/default/grub 里的菜单项（本机 4 项：Arch x3 + UEFI Firmware）
cd "$_tmpdir/matter"
sudo python3 matter.py -i linux linux linux cog
success "Matter GRUB theme installed (and grub.cfg rebuilt)"
