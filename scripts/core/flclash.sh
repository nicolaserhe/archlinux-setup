#!/usr/bin/env bash
# =============================================================================
# scripts/core/flclash.sh -- FlClash 代理客户端（pacman + 订阅 + 持久规则）
#
# 1. 安装 flclash（pacman archlinuxcn 仓库）
# 2. 把 usb/sub2clash/files/config.yaml 导入为 FlClash 订阅 profile
# 3. 将该 profile 设为激活
# 4. 通过 patchClashConfig 注入持久直连规则（跨订阅更新保留）
# =============================================================================

set -euo pipefail

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
    warn "FlClash data dir not found (never launched?), skipping subscription import"
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

NOW_MS=$(date +%s%3N)

python3 - <<EOF
import sqlite3, time

db = sqlite3.connect("$DB")
db.execute("""
    INSERT OR REPLACE INTO profiles
        (id, name, group_, url, updatedAt, type, url2, interval, traffic, enable, proxyGroupSelector, rule, sort)
    VALUES
        ($PROFILE_ID, 'archlinux-setup', '节点选择', '', $NOW_MS, 'standard', NULL, 86400000, '{}', 1, '{}', '[]', 0)
""")
db.commit()
db.close()
print("profiles table updated")
EOF

success "SQLite updated"

# =============================================================================
# 3. 更新 shared_preferences.json：激活 profile + 注入持久直连规则
# =============================================================================
header "FlClash: set active profile and patch rules"

# 天气组件直连规则（订阅更新不影响，通过 patchClashConfig 注入）
WEATHER_RULES='[
    "DOMAIN-SUFFIX,open-meteo.com,DIRECT",
    "DOMAIN-SUFFIX,nominatim.openstreetmap.org,DIRECT",
    "DOMAIN,ip-api.com,DIRECT"
]'

python3 - <<EOF
import json

with open("$PREFS") as f:
    prefs = json.load(f)

config = json.loads(prefs["flutter.config"])

# 激活导入的订阅 profile
config["currentProfileId"] = $PROFILE_ID

# 注入直连规则（追加到已有规则，去重）
existing_rules = config.get("patchClashConfig", {}).get("rule", [])
new_rules = $WEATHER_RULES
merged = list(dict.fromkeys(new_rules + existing_rules))  # new_rules 优先，去重
config.setdefault("patchClashConfig", {})["rule"] = merged

prefs["flutter.config"] = json.dumps(config, ensure_ascii=False, separators=(",", ":"))

with open("$PREFS", "w") as f:
    json.dump(prefs, f, ensure_ascii=False, indent=2)

print("shared_preferences.json updated")
EOF

success "Preferences updated"

# =============================================================================
# 4. 重载 FlClash 核心（如果正在运行）
# =============================================================================
header "FlClash: reload core"

if pgrep -x FlClashCore >/dev/null 2>&1; then
    kill -HUP "$(pgrep -x FlClashCore)"
    success "FlClashCore reloaded"
else
    warn "FlClashCore not running, changes will apply on next launch"
fi

success "FlClash done"
