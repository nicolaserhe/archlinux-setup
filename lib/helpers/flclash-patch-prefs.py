#!/usr/bin/env python3
# =============================================================================
# lib/helpers/flclash-patch-prefs.py -- 改 FlClash shared_preferences.json
#
# 用法: flclash-patch-prefs.py <shared_preferences.json> <profile_id>
#
# 做三件事：
#   1. 激活订阅 profile（currentProfileId = profile_id）
#   2. 开启 autoLaunch / silentLaunch / autoRun（GUI 里的"开机自启/静默启动/自启代理"）
#   3. 注入持久直连规则（patchClashConfig.rule） —— 跨订阅更新仍保留
#
# 持久规则列表（天气组件相关，本机用途明确不走代理）固定写在本脚本里；
# 要加新规则改这里，不该当成可配置项稀释脚本。
# =============================================================================

import json
import sys

PERSISTENT_RULES = [
    "DOMAIN-SUFFIX,open-meteo.com,DIRECT",
    "DOMAIN-SUFFIX,nominatim.openstreetmap.org,DIRECT",
    "DOMAIN,ip-api.com,DIRECT",
]


def patch(prefs_path: str, profile_id: int) -> None:
    with open(prefs_path, encoding="utf-8") as f:
        prefs = json.load(f)

    config = json.loads(prefs["flutter.config"])

    config["currentProfileId"] = profile_id

    app_settings = config.setdefault("appSettingProps", {})
    app_settings["autoLaunch"] = True
    app_settings["silentLaunch"] = True
    app_settings["autoRun"] = True

    existing_rules = config.get("patchClashConfig", {}).get("rule", [])
    merged = list(dict.fromkeys(PERSISTENT_RULES + existing_rules))
    config.setdefault("patchClashConfig", {})["rule"] = merged

    prefs["flutter.config"] = json.dumps(
        config, ensure_ascii=False, separators=(",", ":")
    )

    with open(prefs_path, "w", encoding="utf-8") as f:
        json.dump(prefs, f, ensure_ascii=False, indent=2)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: flclash-patch-prefs.py <shared_preferences.json> <profile_id>",
            file=sys.stderr,
        )
        return 2
    patch(sys.argv[1], int(sys.argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
