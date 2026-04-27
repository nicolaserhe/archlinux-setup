#!/usr/bin/env bash
# =============================================================================
# scripts/core/boot.sh -- GRUB matter 主题（用户阶段，sudo 提权）
#
# matter (https://github.com/mateosss/matter) 自带安装器 matter.py，会处理：
#   - 拷贝主题到 /boot/grub/themes/Matter/
#   - 修改 /etc/default/grub 的 GRUB_THEME
#   - 调用 grub-mkconfig 重建 grub.cfg
# 我们只需要 sudo 跑 matter.py，无需手动 cp / sed / grub-mkconfig。
#
# 可选 env vars：
#   GRUB_ICONS：自定义图标列表，默认 "linux linux linux cog"（对应本机 menuentry）
#   GRUB_MATTER_1080P_LAYOUT=1：opt-in 1920x1080 显示器布局优化（间距/位置）
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

# 仅在系统装了 grub 时才安装主题；UEFI 直引导（systemd-boot 等）跳过
if ! command_exists grub-mkconfig; then
    warn "grub-mkconfig not found, skipping GRUB theme"
    exit 0
fi

# -- matter 主题安装 ----------------------------------------------------------
# 已经装过则跳过 install：matter.py 不幂等，重复跑会重写 GRUB_THEME 与重建 grub.cfg。
# 1080p layout patch 在 install 之后独立判断（看 theme.txt.bak 是否存在）
if [[ -d /boot/grub/themes/Matter ]]; then
    warn "Matter theme already installed at /boot/grub/themes/Matter, skipping install"
else
    header "GRUB matter theme"

    # matter.py 需要 convert(imagemagick) 把 SVG 转 PNG；imagemagick 在 pacman-base.sh 已装
    _tmpdir="$(mktemp -d /tmp/grub-matter.XXXXXX)"

    git_clone "$_tmpdir/matter" https://github.com/mateosss/matter.git

    # matter.py -i 是"安装主题 + 设置图标"复合命令；
    # 图标顺序对应 grub.cfg 里的 menuentry（本机默认 4 项：Arch x3 + UEFI Firmware）。
    # 机器不同 entry 数也不同 —— 用 GRUB_ICONS 环境变量 override：
    #   GRUB_ICONS="linux cog" bash scripts/core/boot.sh
    # 可选图标见 matter.py 上游（linux/arch/debian/cog/...）。
    GRUB_ICONS="${GRUB_ICONS:-linux linux linux cog}"
    cd "$_tmpdir/matter"
    # shellcheck disable=SC2086 # GRUB_ICONS 必须 word-split 成多个 -i 参数
    sudo python3 matter.py -i $GRUB_ICONS
    success "Matter GRUB theme installed (icons: $GRUB_ICONS)"
fi

# -- 1080p 显示器布局优化（opt-in）-------------------------------------------
# matter 默认布局对 1920x1080 显示器偏稀疏（item_spacing/item_height 较大），
# 长 menuentry 标题（"Advanced options for Arch Linux"）会被宽度截断。
# 字号必须保持 32（matter 只生成字号 32 的 PF2 位图字体，改字号 → GRUB
# fallback 到 Unifont 字宽计算 → 字符叠加）；只调间距/位置/区域宽度。
#
# 幂等：theme.txt.bak 存在视为已 patched，跳过。需要重新 patch（如 matter
# 上游升级后字段值变了）：手动 `sudo rm /boot/grub/themes/Matter/theme.txt.bak`
# 再重跑此脚本。回滚原样：
#   sudo cp /boot/grub/themes/Matter/theme.txt.bak /boot/grub/themes/Matter/theme.txt
if [[ "${GRUB_MATTER_1080P_LAYOUT:-0}" == "1" ]]; then
    _theme=/boot/grub/themes/Matter/theme.txt
    _theme_bak="$_theme.bak"

    if [[ ! -f "$_theme" ]]; then
        warn "1080p layout: $_theme not found, skipping"
    elif [[ -f "$_theme_bak" ]]; then
        warn "1080p layout: $_theme_bak exists, already patched, skipping"
    else
        header "GRUB matter 1080p layout patch"

        # 前置校验：所有要改的字段必须能 grep 到当前值；任一不命中（matter
        # 上游升级改了字段）则整体 abort，避免 sed silent no-op 让用户以为
        # 应用成功了实际没动。theme.txt 通常 644 普通用户可读，sudo 兜底
        # 防止权限收紧。
        _layout_ok=1
        for _pat in \
            '^  icon_width = 72$' \
            '^  icon_height = 72$' \
            '^  item_height = 72$' \
            '^  item_spacing = 36$' \
            '^  left = 36%$' \
            '^  width = 28%$' \
            '^  top = 29%$' \
            '^  top = 82%$' \
            '^  left = 35%$' \
            '^  width = 30%$'
        do
            if ! sudo grep -qE "$_pat" "$_theme"; then
                warn "1080p layout: pattern not found in $_theme: $_pat"
                _layout_ok=0
            fi
        done
        unset _pat

        if ((_layout_ok != 1)); then
            warn "1080p layout: matter theme.txt schema mismatch -- patch skipped"
            warn "  matter upstream may have changed; check tmp/fix-grub-theme.sh history"
        else
            sudo cp -a "$_theme" "$_theme_bak"
            # 改动（保留字号 32 不变，只调间距/位置/区域宽度）：
            #   item_height       72 → 56   菜单项不那么撑
            #   item_spacing      36 → 12   项之间紧凑
            #   icon              72 → 64   略小，配合 item_height
            #   boot_menu left    36% → 20% 菜单左移居中
            #   boot_menu width   28% → 60% 菜单更宽，长标题不截断
            #   boot_menu top     29% → 22% 挪高，留更多空间放选项 + label
            #   label top         82% → 88% 超时提示下移
            #   label left/width  35%/30% → 20%/60% 跟菜单宽度对齐
            sudo sed -i \
                -e 's/^  icon_width = 72$/  icon_width = 64/' \
                -e 's/^  icon_height = 72$/  icon_height = 64/' \
                -e 's/^  item_height = 72$/  item_height = 56/' \
                -e 's/^  item_spacing = 36$/  item_spacing = 12/' \
                -e '/^+ boot_menu {/,/^}/{ s/^  left = 36%$/  left = 20%/; s/^  width = 28%$/  width = 60%/; s/^  top = 29%$/  top = 22%/; }' \
                -e '/^+ label {/,/^}/{ s/^  top = 82%$/  top = 88%/; s/^  left = 35%$/  left = 20%/; s/^  width = 30%$/  width = 60%/; }' \
                "$_theme"
            success "1080p layout applied (backup: $_theme_bak)"
        fi
        unset _layout_ok
    fi
    unset _theme _theme_bak
fi
