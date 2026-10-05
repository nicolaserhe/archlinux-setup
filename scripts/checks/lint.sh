#!/usr/bin/env bash
# =============================================================================
# scripts/checks/lint.sh -- 静态分析门禁（shellcheck + bash -n）
#
# 用法：just lint   （或直接 bash scripts/checks/lint.sh）
#
# 覆盖面：仓库里所有"归仓库管"的 shell 脚本，含 install.sh、config/、usb/、scripts/apps/。
# 用 `git ls-files -co --exclude-standard` 而不是手写目录列表 —— 它自动跟随
# .gitignore（tmp/ 下的一次性脚本不进门禁），也不会随目录结构调整而漏掉新目录。
# -c 已跟踪 + -o 未跟踪，所以刚写好、还没 git add 的脚本也会被检查。
#
# 按 shebang 判定，不按 *.sh 后缀：config/helpers/ 下的 brightness / git-health /
# gsr-toggle 是部署到 ~/.local/bin 直接跑的 bash 脚本，没有 .sh 后缀，只看后缀会
# 整类漏检（那三个被 shell.sh 用 install 部署出去，出错就是用户登录后 command not found）。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"

# 只在**本仓库**的 git 工作树里跑。原来有个 find 兜底分支，但它绕开 .gitignore，
# 会把 tmp/、log/、__pycache__ 里的东西一并送进 shellcheck —— 同一棵树，.git 在不在
# 会得出不同结论。跑不起来的门禁该报错，而不是换一套规则继续跑。
# 用 --show-toplevel 而不是 --is-inside-work-tree：后者在"仓库被塞进别人仓库的
# 子目录"时也返回 true，那样扫的是父仓库的索引。
_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || _toplevel=""
if [[ -z "$_toplevel" || "$_toplevel" != "$(pwd -P)" ]]; then
    printf '[ERR]  不是本仓库的 git 工作树（git 顶层: %s），无法确定检查范围\n' \
        "${_toplevel:-<无>}" >&2
    exit 1
fi
unset _toplevel

# 全程 -z / -d ''：git 默认把非 ASCII 文件名 C-quote 成 "scripts/\346..." 这种
# 带引号和八进制转义的字符串（core.quotePath 默认 true），按行读会拿到一个
# 磁盘上不存在的路径，然后被静默跳过 —— 中文名脚本整个漏检且门禁报绿。
mapfile -t -d '' _candidates < <(git ls-files -z -co --exclude-standard)

mapfile -t -d '' files < <(
    for _f in "${_candidates[@]}"; do
        # 已跟踪但工作区被删（rm 了没 git add）：送进 shellcheck 会硬报错。
        # 那是重构中途的正常状态，不是缺陷，交给 git status 呈现。
        [[ -e "$_f" ]] || continue
        case "$_f" in
            *.sh)
                printf '%s\0' "$_f"
                continue
                ;;
        esac
        # read -n 128 兜住二进制文件和超长首行：只看首行、只取前 128 字节。
        # 读失败（空文件 / 无换行结尾）会返回非 0，忽略即可，_shebang 保持空串。
        _shebang=""
        IFS= read -r -n 128 _shebang <"$_f" || true
        # 收 bash 与 POSIX sh 系（sh/dash/ash/ksh）。.shellcheckrc 全局设了
        # shell=bash，POSIX 脚本也按 bash 方言查 —— 方言更宽，真语法错照样抓得到。
        # python/expect 等不收。
        case "$_shebang" in
            '#!'*bash* | '#!'*'/sh'* | '#!'*'/dash'* | '#!'*'/ash'* | '#!'*'/ksh'* | '#!'*'env sh'*)
                printf '%s\0' "$_f"
                ;;
        esac
    done | sort -z -u
)

if [[ ${#files[@]} -eq 0 ]]; then
    printf '[ERR]  没找到任何 shell 脚本，收集逻辑本身有问题\n' >&2
    exit 1
fi

printf '==> shellcheck（%d 个文件）\n' "${#files[@]}" >&2
shellcheck "${files[@]}"

printf '==> bash -n 语法检查\n' >&2
for _f in "${files[@]}"; do
    bash -n "$_f"
done

printf '[OK] lint 通过（shellcheck + bash -n）\n' >&2
