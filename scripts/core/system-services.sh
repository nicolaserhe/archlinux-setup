#!/usr/bin/env bash
# =============================================================================
# scripts/core/system-services.sh -- Bluetooth / Avahi / 电源管理
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# bluez:                 Linux 蓝牙协议栈
# bluez-utils:           蓝牙管理命令行工具（bluetoothctl）
# avahi:                 局域网 mDNS/DNS-SD 服务（Valent 设备发现依赖）
# power-profiles-daemon: 电源性能模式管理
header "System service packages"
pacman_install \
    bluez \
    bluez-utils \
    avahi \
    power-profiles-daemon

# -- 启用服务 -----------------------------------------------------------------
header "Bluetooth"
enable_system_service bluetooth.service

header "Avahi"
enable_system_service avahi-daemon.service

header "Power profiles"
enable_system_service power-profiles-daemon.service

success "System services done"
