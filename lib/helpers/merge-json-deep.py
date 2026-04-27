#!/usr/bin/env python3
# =============================================================================
# lib/helpers/merge-json-deep.py -- deep-merge src JSON into dst JSON (in-place)
#
# 用法: merge-json-deep.py <dst.json> <src.json>
#
# 嵌套 dict 递归合并；非 dict 值按 src 覆盖；list 整体替换（保留 DMS 等
# 应用的"数组语义是全量替换"约定）。src 顶层 "__doc__" key 被忽略
# （仓库 config 文件用它放设计说明，不该污染目标设置）。
# =============================================================================

import json
import sys


def deep_merge(dst: dict, src: dict) -> None:
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            deep_merge(dst[k], v)
        else:
            dst[k] = v


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: merge-json-deep.py <dst.json> <src.json>", file=sys.stderr)
        return 2

    dst_path, src_path = sys.argv[1], sys.argv[2]

    with open(dst_path, encoding="utf-8") as f:
        data = json.load(f)
    with open(src_path, encoding="utf-8") as f:
        overrides = json.load(f)

    overrides.pop("__doc__", None)
    deep_merge(data, overrides)

    with open(dst_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
