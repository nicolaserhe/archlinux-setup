#!/usr/bin/env python3
# =============================================================================
# lib/helpers/flclash-upsert-profile.py -- 在 FlClash SQLite 写入订阅 profile
#
# 用法: flclash-upsert-profile.py <database.sqlite> <profile_id>
#
# INSERT OR REPLACE 保证幂等。profile name 固定 "archlinux-setup" 便于在
# FlClash UI 识别。updatedAt 用当前毫秒时间戳。
# =============================================================================

import sqlite3
import sys
import time


def upsert(db_path: str, profile_id: int) -> None:
    now_ms = int(time.time() * 1000)
    db = sqlite3.connect(db_path)
    try:
        db.execute(
            """
            INSERT OR REPLACE INTO profiles
                (id, name, group_, url, updatedAt, type, url2, interval,
                 traffic, enable, proxyGroupSelector, rule, sort)
            VALUES
                (?, 'archlinux-setup', '节点选择', '', ?, 'standard',
                 NULL, 86400000, '{}', 1, '{}', '[]', 0)
            """,
            (profile_id, now_ms),
        )
        db.commit()
    finally:
        db.close()


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: flclash-upsert-profile.py <database.sqlite> <profile_id>",
            file=sys.stderr,
        )
        return 2
    upsert(sys.argv[1], int(sys.argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
