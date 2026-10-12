#!/usr/bin/env python3
# =============================================================================
# lib/helpers/merge-json-deep.py -- deep-merge src JSON into dst JSON (in-place)
#
# 用法: merge-json-deep.py <dst.json> <src.json>
#
# 嵌套 dict 递归合并；非 dict 值按 src 覆盖；list 整体替换（保留 DMS 等
# 应用的"数组语义是全量替换"约定）。src 顶层 "__doc__" key 被忽略 —— 只为给
# 仓库 config 文件留一个放设计说明的位置（当前无文件使用；留着是因为一旦有人
# 用上，写进目标设置里的就是一段注释文字，而不是被静默丢掉）。
#
# 写回是原子的（同目录临时文件 + os.replace）。目标文件是运行时程序自己的状态
# 文件（`~/.config/DankMaterialShell/settings.json`），那个程序随时可能也在写
# 它；原地 open(w) 会先截断，中途出错或断电留下的就是空/半截 JSON，DMS 下次
# 启动直接读不出来。os.replace 在同一文件系统上是原子的（所以临时文件必须建在
# 目标目录里，不能落 /tmp）。
# =============================================================================

import json
import os
import sys
import tempfile


def deep_merge(dst: dict, src: dict) -> None:
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            deep_merge(dst[k], v)
        else:
            dst[k] = v


def load_object(path: str) -> dict:
    """读一个 JSON 文件并断言顶层是 object。

    顶层是 list/scalar 时 deep_merge 会以 AttributeError 崩在深处，报错信息
    完全指不到是哪个文件坏了；在这里就换成一句能读的话。
    """
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: top-level JSON value is a {type(data).__name__}, expected an object")
    return data


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: merge-json-deep.py <dst.json> <src.json>", file=sys.stderr)
        return 2

    dst_path, src_path = sys.argv[1], sys.argv[2]

    # JSONDecodeError / UnicodeDecodeError 都是 ValueError 的子类
    try:
        data = load_object(dst_path)
        overrides = load_object(src_path)
    except (OSError, ValueError) as e:
        print(f"merge-json-deep.py: {e}", file=sys.stderr)
        return 1

    overrides.pop("__doc__", None)
    deep_merge(data, overrides)

    dst_dir = os.path.dirname(os.path.abspath(dst_path))
    dst_mode = os.stat(dst_path).st_mode & 0o7777
    fd, tmp_path = tempfile.mkstemp(dir=dst_dir, prefix=".merge-json-deep.", suffix=".tmp")
    try:
        # 权限跟随原文件：重写一个文件不该顺手改掉它的权限位（mkstemp 给的是 0600）
        os.chmod(tmp_path, dst_mode)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, dst_path)
    except BaseException:
        # 失败路径不能留垃圾文件；正常路径下 tmp_path 已被 replace 吃掉
        os.unlink(tmp_path)
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main())
