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
#   - allow-lan 强制 false：bootstrap 只服务本机，详见 _patch_allow_lan
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


def _patch_allow_lan(text: str) -> str:
    """把 allow-lan 强制改成 false —— bootstrap 期只服务本机。

    订阅模板几乎都带 `allow-lan: true`（给路由器 / 多设备场景用），而 mihomo 的
    默认 bind-address 是 "*"：两者一叠加，HTTP/SOCKS 端口就监听 0.0.0.0，且这套
    配置里没有 secret/authentication —— 同网段任何设备都能直接白嫖这条代理（用
    你的出口 IP 和订阅流量）。安装窗口有十几分钟（AUR / Flatpak 下载全走它），
    本机在这段时间里通常还没有防火墙，所以这是个实打实的暴露面。

    持久态不受影响：FlClash 用自己的运行配置（显式 allow-lan: false），跟这里
    改的 ~/.config/mihomo/config.yaml 不是同一份。
    """
    if re.search(r"^allow-lan\s*:", text, re.M):
        return re.sub(
            r"^allow-lan\s*:.*$",
            "allow-lan: false  # bootstrap: 只监听回环，见 patch-mihomo-config.py",
            text,
            flags=re.M,
        )
    return "allow-lan: false  # bootstrap: 只监听回环\n" + text


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
    # subconverter 输出格式变更或自定义模板可能拿不到这两个锚点；str.replace
    # 找不到时静默返回原 text，造成"装完 claude.ai 实际没走美国节点"的隐式
    # 失败。提前 warn 让用户在 install log 里能发现。
    if "rules:" not in text:
        print(
            "warn: 'rules:' anchor missing, skipping US fallback group injection",
            file=sys.stderr,
        )
        return text
    text = text.replace("rules:", group_block + "rules:", 1)

    rule = "  - DOMAIN-SUFFIX,claude.ai,\U0001f1fa\U0001f1f8 美国节点\n"
    if "  - MATCH," not in text:
        print(
            "warn: '  - MATCH,' anchor missing, skipping claude.ai rule injection",
            file=sys.stderr,
        )
        return text
    text = text.replace("  - MATCH,", rule + "  - MATCH,", 1)
    return text


def patch(text: str, port: str) -> str:
    text = _patch_mixed_port(text, port)
    text = _patch_tun(text)
    text = _patch_allow_lan(text)
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
