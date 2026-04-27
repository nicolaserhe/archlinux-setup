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
#   - claude.ai 走 fallback 组优先选美国节点，全部不可用时回退到自动选择
# =============================================================================

import re
import sys


def _patch_mixed_port(text: str, port: str) -> str:
    if not re.search(r"^mixed-port\s*:", text, re.M):
        text = f"mixed-port: {port}\n" + text
    return text


def _patch_tun(text: str) -> str:
    return re.sub(r"^tun\s*:.*?(?=^\S|\Z)", "", text, flags=re.M | re.S)


def _patch_privileged_ports(text: str) -> str:
    return re.sub(
        r"^(redir-port|tproxy-port)\s*:.*",
        r"# \g<0>  # disabled: requires root",
        text,
        flags=re.M,
    )


def _patch_us_group_and_claude_rule(text: str) -> str:
    """自动添加 🇺🇸 美国节点 fallback 组 + claude.ai 走美国规则。

    fallback 优先选美国节点，全部不可用时回退到 ♻️ 自动选择。
    对代理连接而言 DNS 由远程节点解析，本地 hosts 无必要且可能干扰。
    """
    us_nodes = sorted(
        {
            m.group()
            for m in re.finditer(r"美国[^,\s}\"]+(?:-GPT)?", text)
            if m.group() != "美国节点"
        }
    )
    if not us_nodes:
        return text

    group_lines = [
        "  - name: \U0001f1fa\U0001f1f8 美国节点",
        "    type: fallback",
        "    url: http://www.gstatic.com/generate_204",
        "    interval: 300",
        "    proxies:",
    ]
    for n in us_nodes:
        group_lines.append(f"      - {n}")
    group_lines.append("      - ♻️ 自动选择")

    group_block = "\n".join(group_lines) + "\n"
    text = text.replace("rules:", group_block + "rules:", 1)

    rule = "  - DOMAIN-SUFFIX,claude.ai,\U0001f1fa\U0001f1f8 美国节点\n"
    text = text.replace("  - MATCH,", rule + "  - MATCH,", 1)
    return text


def patch(text: str, port: str) -> str:
    text = _patch_mixed_port(text, port)
    text = _patch_tun(text)
    text = _patch_privileged_ports(text)
    text = _patch_us_group_and_claude_rule(text)
    return text


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: patch-mihomo-config.py <config.yaml> <mixed-port>", file=sys.stderr
        )
        return 2

    path, port = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(patch(text, port))
    return 0


if __name__ == "__main__":
    sys.exit(main())
