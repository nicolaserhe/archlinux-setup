#!/usr/bin/env bash
# =============================================================================
# scripts/core/flclash.sh -- FlClash 代理客户端（pacman + 订阅 + 持久规则）
#
# 1. 安装 flclash（pacman archlinuxcn 仓库）
# 2. 把 usb/sub2clash/files/config.yaml 导入为 FlClash 订阅 profile
# 3. 将该 profile 设为激活
# 4. 开启自启/静默启动/自动开核心（appSettingProps）
# 5. 通过 patchClashConfig 注入持久直连规则（跨订阅更新保留）
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- 包安装 -------------------------------------------------------------------
header "FlClash package (pacman)"
pacman_install flclash

FLCLASH_DIR="$HOME/.local/share/com.follow.clash"
PROFILES_DIR="$FLCLASH_DIR/profiles"
DB="$FLCLASH_DIR/database.sqlite"
PREFS="$FLCLASH_DIR/shared_preferences.json"
SRC_YAML="$REPO_DIR/usb/sub2clash/files/config.yaml"

# 检查前置条件
if [[ ! -f "$SRC_YAML" ]]; then
    warn "usb/sub2clash/files/config.yaml not found — run usb/sub2clash/convert.sh first"
    exit 0
fi

if [[ ! -d "$FLCLASH_DIR" ]]; then
    warn "FlClash 数据目录不存在 —— flclash 还没启动过"
    warn "首次跑 install.sh 时 DISPLAY 还没有，flclash GUI 启不起来"
    warn ""
    warn "执行路径："
    warn "  1) 跑完 install.sh 后 reboot 进入 niri"
    warn "  2) FlClash 会自动启动（appSettingProps.autoLaunch）并创建数据目录"
    warn "  3) 在 niri 里重跑：bash $REPO_DIR/scripts/core/flclash.sh"
    warn ""
    warn "本次跳过订阅导入。"
    exit 0
fi

mkdir -p "$PROFILES_DIR"

# =============================================================================
# 1. 生成 profile ID（固定值，幂等）并写入 YAML
# =============================================================================
header "FlClash: import subscription profile"

PROFILE_ID=100000000000000001
PROFILE_YAML="$PROFILES_DIR/${PROFILE_ID}.yaml"

cp "$SRC_YAML" "$PROFILE_YAML"
success "Profile YAML written to $PROFILE_YAML"

# =============================================================================
# 2. 写入 SQLite profiles 表（INSERT OR REPLACE 保证幂等）
# =============================================================================
header "FlClash: update profiles database"

python3 "$REPO_DIR/lib/helpers/flclash-upsert-profile.py" "$DB" "$PROFILE_ID"
success "SQLite updated"

# =============================================================================
# 3. 更新 shared_preferences.json：激活 profile + 注入持久直连规则
#    持久规则列表（天气组件相关）固化在 helper 里。
# =============================================================================
header "FlClash: set active profile and patch rules"

python3 "$REPO_DIR/lib/helpers/flclash-patch-prefs.py" "$PREFS" "$PROFILE_ID"
success "Preferences updated"

# =============================================================================
# 4. 重载 FlClash 核心（如果正在运行）
# =============================================================================
header "FlClash: reload core"

if pkill -HUP -x FlClashCore 2>/dev/null; then
    success "FlClashCore reloaded"
else
    warn "FlClashCore not running, changes will apply on next launch"
fi

success "FlClash done"
