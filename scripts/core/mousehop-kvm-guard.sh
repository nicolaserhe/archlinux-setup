#!/usr/bin/env bash
# =============================================================================
# scripts/core/mousehop-kvm-guard.sh -- 跟随硬件 KVM 开关的 Mousehop 守卫
#
# 硬件 USB switch 和 Mousehop（走 LAN）是两条互不知情的通路，不处理会出现
# 两种"鼠标不听话"：
#
#   1. 回程误触：Mousehop 把光标交给 Windows 时会把它精确停在右边缘那 1px
#      捕捉面上；硬件切回 Arch 后光标还在原地，往右一推（尤其 Alt 还卡在
#      pressed_keys 里）就又切走了。守卫在设备回来时把光标 warp 到当前输出
#      中心，离边缘约 1280px，正常跨界（按住 Alt 推到边）不受影响。
#   2. 鼠标跑到不属于它的机器：KVM 把设备切给 Windows 后，Windows 那端的
#      Mousehop 仍按自己的屏幕边缘把光标交回 Arch。`mousehop cli deactivate`
#      只销毁本机捕捉面，挡不住入站接力（EmulationEvent::Entered 只查授权
#      指纹，不看客户端是否 active），所以设备不在时必须停整个 daemon。
#
# 本脚本负责：
#   1. 装 Python 守卫到 ~/.local/bin/mousehop-kvm-guard
#   2. 把源文件部署到缓存目录，从 .xml 现场生成 wlr-virtual-pointer 绑定并编译
#      warp helper（生成物不进仓：它跟 libwayland 版本绑定）
#   3. 写 systemd user service（随 graphical-session.target 启停）
#
# 设备 id 写在 guard 的 KVM_DEVICES 里（键盘 258a:013b、鼠标 3554:f50b）；
# 换键盘鼠标要改 guard 源码，并把安装后的副本重装一次。
#
# 已知限制：键盘在 Alt 按住时被 USB 拔掉，niri 不会补发 release，Alt 会卡在
# seat 的 pressed_keys 里；用户态清不掉（虚拟键盘不进 seat 状态），按一下真实
# 键盘的 Alt 即恢复。光标已被居中，所以卡住的 Alt 不再造成误跨界。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- Python 守卫 ---------------------------------------------------------------
header "Mousehop KVM guard"
install_config \
    "$REPO_DIR/config/helpers/mousehop-kvm-guard/mousehop-kvm-guard.py" \
    "$HOME/.local/bin/mousehop-kvm-guard" \
    755

# -- 光标 warp helper ----------------------------------------------------------
# 源文件先按目录部署到缓存目录再编译：生成物（wayland-scanner 的 .c/.h）跟
# libwayland 版本绑定，进仓只会过期，所以仓库只放 .xml 与手写的 center-cursor.c。
# 走 copy_config_dir 而不是裸 cp —— `just drift` 靠部署 helper 识别归属，
# 裸引用 config/ 会被它当解析失败（exit 2）。
header "Mousehop center-cursor helper"
copy_config_dir \
    "$REPO_DIR/config/helpers/mousehop-kvm-guard" \
    "$HOME/.cache/mousehop-kvm-guard"
GUARD_BUILD="$HOME/.cache/mousehop-kvm-guard"

# wayland-scanner 与 wayland-client 头文件都来自 wayland 包（niri 的运行时依赖，
# 这里显式装一遍免得顺序假设）。gcc 来自 base-devel，由 pacman-base.sh 安装。
pacman_install wayland
command_exists gcc || die "gcc not found (base-devel is installed by pacman-base.sh)"
command_exists wayland-scanner || die "wayland-scanner not found (wayland package)"

install -d "$HOME/.local/bin"
wayland-scanner client-header \
    "$GUARD_BUILD/virtual-pointer.xml" "$GUARD_BUILD/virtual-pointer.h"
wayland-scanner private-code \
    "$GUARD_BUILD/virtual-pointer.xml" "$GUARD_BUILD/virtual-pointer.c"
# 不加 -Werror：生成代码的告警随 wayland-scanner 版本变，不该卡住安装。
gcc -O2 -Wall -Wextra -I"$GUARD_BUILD" \
    -o "$HOME/.local/bin/mousehop-center-cursor" \
    "$GUARD_BUILD/center-cursor.c" "$GUARD_BUILD/virtual-pointer.c" \
    -lwayland-client
chmod 755 "$HOME/.local/bin/mousehop-center-cursor"
success "Compiled: ~/.local/bin/mousehop-center-cursor"

# -- systemd user service -----------------------------------------------------
# 独立于 mousehop.service：守卫要在 mousehop 停着的时候也活着，才能把它拉回来。
# BindsTo=graphical-session.target：warp 需要 niri 的 Wayland socket。
header "Mousehop KVM guard systemd user service"
write_user_unit mousehop-kvm-guard.service <<'EOF'
[Unit]
Description=Follows the USB KVM switch: stops/starts mousehop and recenters the cursor
After=graphical-session.target
PartOf=graphical-session.target
BindsTo=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/mousehop-kvm-guard
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF
enable_user_service mousehop-kvm-guard.service

success "Mousehop KVM guard done"
