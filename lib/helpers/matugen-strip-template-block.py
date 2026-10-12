#!/usr/bin/env python3
# =============================================================================
# lib/helpers/matugen-strip-template-block.py -- 切除 matugen config.toml 中
# 指定 [templates.NAME] block，包括前置引言注释 + 一个分隔空行
#
# 用法: matugen-strip-template-block.py <config.toml> "[templates.NAME]"
#
# 用途：dms setup 可能写过同名 entry（指向 DMS 自带模板），仓库要替换它时
# 先切干净再追加自己的版本。回吃 marker 上方紧贴的注释 + 一个分隔空行
# （DMS 写入风格固定如此），但只当这些注释与上一段内容之间有空行隔开
# （或位于文件开头）；否则那是上一个 block 的尾注释，不能吃。
# =============================================================================

import sys
from pathlib import Path


def strip(path: str, marker: str) -> None:
    p = Path(path)
    lines = p.read_text(encoding="utf-8").splitlines()

    start = next((i for i, ln in enumerate(lines) if ln.strip() == marker), None)
    if start is None:
        return

    end = len(lines)
    for i in range(start + 1, len(lines)):
        s = lines[i].lstrip()
        if s.startswith("[") and "]" in s:
            end = i
            break

    probe = start - 1
    while probe >= 0 and lines[probe].lstrip().startswith("#"):
        probe -= 1
    if probe < 0 or lines[probe].strip() == "":
        start = probe + 1
        if start > 0 and lines[start - 1].strip() == "":
            start -= 1

    new = lines[:start] + lines[end:]
    while new and new[-1].strip() == "":
        new.pop()

    p.write_text("\n".join(new) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            'Usage: matugen-strip-template-block.py <config.toml> "[templates.NAME]"',
            file=sys.stderr,
        )
        return 2
    strip(sys.argv[1], sys.argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())
