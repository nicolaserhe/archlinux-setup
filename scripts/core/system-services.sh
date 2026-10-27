#!/usr/bin/env bash
# =============================================================================
# scripts/core/system-services.sh -- Bluetooth / Avahi / 电源管理 / 时间同步
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# bluez:                 Linux 蓝牙协议栈
# bluez-utils:           蓝牙管理命令行工具（bluetoothctl）
# avahi:                 局域网 mDNS/DNS-SD 服务（KDE Connect 设备发现依赖）
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

# -- 时间同步 -----------------------------------------------------------------
# timesyncd 的可执行文件随 systemd 包一起给（不是独立包），但 Arch 装包时**不跑**
# `systemctl preset-all`（/usr/share/libalpm/hooks/ 里没有这样的 hook），所以上游
# 那份写着 `enable systemd-timesyncd.service` 的 preset 从来没被应用过 —— 装完
# 就是 disabled，必须在这里显式 enable。这正是 Ubuntu 与 Arch 的差别所在：那边
# 的 postinst 会应用 preset，所以开箱就是 active。
#
# 不启用它的后果不是「时间慢慢歪」：RTC 自己走时、开机读它、关机时 systemd 再把
# 系统时间写回 RTC，误差被来回搬运，只在单次开机期间累积（晶振 ±20~100 ppm，一天
# 几秒），所以日常完全察觉不到。真正的风险是**一旦某个时刻写错就永远错下去** ——
# 本机实测偏了 73.5 秒（两个独立服务器一致到 2 ms），而 73 秒不可能是 2.6 小时
# 开机时间内攒出来的，说明是装机时 RTC 就写错了。时钟偏差会打挂 TLS 验签与 GPG
# （archlinuxcn keyring 走的就是这条路），以及 TOTP 那类 30 秒窗口的验证。
#
# 与 chrony / ntpd 互斥：timesyncd 检测到它们存在会自己退出。这里是「二选一」的
# 选择结果 —— 台式机长开机、零新包，SNTP 客户端足够。
header "Time sync (systemd-timesyncd)"
install_config_root \
    "$REPO_DIR/config/timesyncd/60-cn-ntp.conf" \
    /etc/systemd/timesyncd.conf.d/60-cn-ntp.conf 644
enable_system_service systemd-timesyncd.service
# 这条服务的收益是立刻的：起来的那一刻就把时钟 step 回正确值（SNTP 客户端不做
# 缓慢 slew）。只 enable 的话要等下次开机，在那之前时钟一直是错的。
start_system_service systemd-timesyncd.service

# -- 包维护定时器 -------------------------------------------------------------
# paccache.timer:       每周跑 `paccache -r`，每个包保留 3 个旧版本 —— 比
#                       `pacman -Sc`（只留当前版本）温和，留出回滚窗口。未安装
#                       包的缓存不在 `-r` 的范围内，需要时手动 `paccache -ruk0`。
# pkgfile-update.timer: 每天刷新 pkgfile 自己的 files 数据库（command-not-found
#                       钩子用）。不启用 pacman-contrib 的 filesdb-refresh.timer：
#                       那是给 `pacman -F` 的第二份数据库，command-not-found
#                       用不到，没必要多存一份。
#
# 只 enable 不 start：timer 由下次开机的 timers.target 拉起；当前这次安装里
# pkgfile 的数据库在下面手动拉一次，command-not-found 立刻可用。
header "Package maintenance timers"
enable_system_service paccache.timer
enable_system_service pkgfile-update.timer

if _as_root pkgfile --update; then
    success "pkgfile database updated"
else
    warn "pkgfile database update failed -- command-not-found uses the old database"
fi

success "System services done"
