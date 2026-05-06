#!/usr/bin/env python3
# =============================================================================
# lib/helpers/patch-mihomo-config.py -- 修补 Clash YAML 让 mihomo 以非特权用户启动
#
# 用法: patch-mihomo-config.py <config.yaml> <mixed-port>
#
# 设计取舍：
#   - 不引入 PyYAML，原文行级 regex 改写，避免重格式化用户配置
#   - tun 段需要 CAP_NET_ADMIN，bootstrap 期没有特权 → 整段删除
#   - redir/tproxy 端口同样要 root → 注释掉，不删除以保留用户原配
# =============================================================================

import re
import sys


def patch(text: str, port: str) -> str:
    if not re.search(r"^mixed-port\s*:", text, re.M):
        text = f"mixed-port: {port}\n" + text
    text = re.sub(r"^tun\s*:.*?(?=^\S|\Z)", "", text, flags=re.M | re.S)
    text = re.sub(
        r"^(redir-port|tproxy-port)\s*:.*",
        r"# \g<0>  # disabled: requires root",
        text,
        flags=re.M,
    )
    return text


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: patch-mihomo-config.py <config.yaml> <mixed-port>", file=sys.stderr)
        return 2

    path, port = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(patch(text, port))
    return 0


if __name__ == "__main__":
    sys.exit(main())
