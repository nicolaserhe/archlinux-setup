#!/usr/bin/env bash
# =============================================================================
# scripts/checks/verify-repo.sh -- 仓库自检（只读，不碰系统）
#
# 用法：just check   （或直接 bash scripts/checks/verify-repo.sh）
#
# 起因：fcitx.sh 引用 config/autostart/org.fcitx.Fcitx5.desktop，而该目录当时
# 没纳入 git —— 本地跑没事（文件在），新克隆会在 copy_config 处直接 die，
# 整个 user-phase 中断。这类错误只有真去装一台新机器才会暴露。
#
# 两项检查：
#   1. scripts/ 与 lib/ 中出现的每个字面量 $REPO_DIR/<path> 在仓库中真实存在
#   2. config/ 与 assets/ 下的文件都已被 git 跟踪（.gitignore 排除的不算错）
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"

_fail=0

# -- 1. $REPO_DIR/<path> 引用完整性 -------------------------------------------
printf '\n==> 引用完整性（REPO_DIR 下的路径引用）\n' >&2

# 只取字面量：正则遇 ( 即停 —— 那是运行时拼接的，静态查不了。
# 变量名外面套不套花括号在 shell 里完全等价（.shellcheckrc 里写明仓库是混合风格），
# 所以两种写法都得抽：install.sh:189 引 user-phase.sh 用的就是花括号那种，
# 漏了它等于漏掉整个安装主流程的入口。
# 注意：别在注释里把完整模式当"例子"写出来 —— 本脚本自己的注释会被自己抽出来
# 当引用，然后报一个根本不存在的路径（前两版注释各踩了一次）。
# 下面这行本身没事：模式里的 $ 是 \$ 转义的，自己匹配不到自己。
#
# 已知边界：字符类不含空格，所以路径里带空格时会被截断到第一个空格，校验的是
# 截断后的那个路径（可能假绿也可能假红）。当前仓库没有带空格的路径；真要支持，
# 得把空格并进字符类，代价是注释里"变量后接斜杠再接一串散文"的写法会被整段
# 当成引用来报错 —— 两种误判权衡下来先保持现状，真遇到带空格的路径再处理。
# （本条注释第一版就把那种散文写了出来，结果自己多抽出一条引用 —— 现场演示。）
# shellcheck disable=SC2016 # 模式里的 $ 是字面量，故意不展开
_ref_pat='\$\{?REPO_DIR\}?/[A-Za-z0-9_./-]+'

# 运行时输出目录：脚本往里写日志和临时产物，不是部署源，跑之前当然不存在。
# 只排除这两个前缀，不按白名单放过整个前缀 —— 否则 usb/、scripts/ 下的真错会被掩盖。
# 结尾的 (/|$) 不能省：install.sh 里有 `mkdir -p "$REPO_DIR/log"`，抽出来的是不带
# 斜杠的 "log"，只写 ^(log|tmp)/ 会把它判成缺失 —— 全新克隆上直接假红。
_skip_pat='^(log|tmp)(/|$)'

# 判定"是不是**本仓库**的 git 工作树"。三条都不能省：
#   1. 不能写成 `git rev-parse ... && _in_git=1`：git 因任何原因失败（不在 PATH、
#      仓库损坏、属主变了触发 dubious ownership）都会让 _in_git 静默留 0，
#      于是所有 git 判定被跳过，门禁照常报绿。
#   2. 只判 is-inside-work-tree 还不够：仓库被丢进**别人的**仓库里（解包到某项目
#      子目录）也返回 true，那时用的是父仓库的索引和 .gitignore，结论全是错的。
#   3. 最要紧的是：git 检查没真的跑，就**不能报 OK**。跑不起来的门禁报"通过"比
#      报错危险得多 —— `cp -r` 掉 .git 的树正是最容易藏"本机有、新克隆缺"的场景。
_in_git=0
_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || _toplevel=""
if [[ -n "$_toplevel" && "$_toplevel" == "$(pwd -P)" ]]; then
    _in_git=1
else
    printf '[ERR]  不是本仓库的 git 工作树（git 顶层: %s），git 相关检查无法执行\n' \
        "${_toplevel:-<无>}" >&2
    _fail=1
fi
unset _toplevel

_checked=0
_skipped=0
_skipped_list=()
# 不限 scripts/ 和 lib/ —— install.sh、config/greetd/、usb/ 里也有 $REPO_DIR 引用。
# 但只扫 shell 类文件：$REPO_DIR 是 shell 变量，只有这类文件里才可能是真引用，
# 扫全类型会把文档注释里的示例（如 .shellcheckrc 第 12 行那个）误判成缺失。
# tmp/ 是 .gitignore 掉的一次性脚本，引用的路径本来就不保证存在。
mapfile -t _refs < <(
    grep -rhoE --include='*.sh' --include='*.exp' \
        --exclude-dir=.git --exclude-dir=tmp "$_ref_pat" . | sort -u
)
for _ref in "${_refs[@]}"; do
    _rel="${_ref#\$REPO_DIR/}"
    _rel="${_rel#\$\{REPO_DIR\}/}"
    _rel="${_rel%/}" # 引用可能带尾斜杠（glob 展开出来的），校验时去掉
    if [[ "$_rel" =~ $_skip_pat ]]; then
        _skipped=$((_skipped + 1))
        _skipped_list+=("$_rel")
        continue
    fi
    # 跑出仓库根的引用（../foo、绝对路径）不是"未纳入 git"，是引用本身无效；
    # 而且 git 会为它打印 fatal，混在正常输出里容易被当噪音忽略。
    if [[ "$_rel" == /* || "$_rel" == ".." || "$_rel" == ../* || "$_rel" == */../* || "$_rel" == */.. ]]; then
        printf '[ERR]  引用的路径跑出了仓库根: %s\n' "$_rel" >&2
        _fail=1
        continue
    fi
    # 被 .gitignore 排除的是"用户自备 / 运行期产物"（如 usb/sub2clash/files 下的转换
    # 输入），仓库不负责交付，新克隆本来就没有 —— 引用它不算错。
    # 2>/dev/null：check-ignore 的 -q 只管退出码，路径非法时照样往 stderr 喷 fatal。
    if ((_in_git)) && git check-ignore -q -- "$_rel" 2>/dev/null; then
        _skipped=$((_skipped + 1))
        _skipped_list+=("$_rel")
        continue
    fi
    _checked=$((_checked + 1))
    # 关键：判"入没入 git"，而不是判"磁盘上在不在"。磁盘 -e 只证明**本机**有，
    # 未纳入 git 的文件在新克隆里同样会缺 —— 那正是本门禁要抓的错（fcitx autostart 那次），
    # 用 -e 判它会全绿放过去。
    if ((_in_git)) && ! git ls-files --error-unmatch -- "$_rel" >/dev/null 2>&1; then
        printf '[ERR]  引用的路径未纳入 git（新克隆会缺失）: %s\n' "$_rel" >&2
        _fail=1
        continue
    fi
    # -L 也要收：指向仓库外的软链是合法交付物，-e 对断链为假会误报成"不存在"。
    # 第 2 段只查 git 不查磁盘，两段标准在这里对齐。
    if [[ ! -e "$_rel" && ! -L "$_rel" ]]; then
        printf '[ERR]  脚本引用了不存在的路径: %s\n' "$_rel" >&2
        _fail=1
    fi
done

# 抽不出任何引用说明上面那条 grep 的 include/正则坏了，是脚本自身故障而非仓库干净。
# lint.sh 对 files==0 有同样的守卫。
if ((_checked == 0)); then
    printf '[ERR]  没解析到任何引用 —— 抽取模式可能已失效\n' >&2
    _fail=1
fi

printf '        检查了 %d 个引用（另有 %d 个运行时/用户自备路径已跳过）\n' \
    "$_checked" "$_skipped" >&2

# 逐条列出跳过项。跳过是"按 .gitignore 判定"，而 gitignore 的反向规则 `!` 在父目录
# 被排除时是无效的（git 就是这么规定的）—— 万一有人写了 `!xxx/keep.conf` 指望它入库，
# 这里能一眼看出那条引用其实没被校验，而不是静默放过。
for _s in "${_skipped_list[@]}"; do
    printf '        [INFO] 未校验（运行时/用户自备）: %s\n' "$_s" >&2
done
unset _s _skipped_list

# -- 2. config/ 与 assets/ 是否已纳入 git -------------------------------------
printf '\n==> git 跟踪状态（config/ assets/）\n' >&2

if ((_in_git == 0)); then
    printf '[SKIP] 不是本仓库的 git 工作树，跳过（上面已有 [ERR]，整体仍判失败）\n' >&2
else
    _tracked=0
    # -type l 也要收：config/ 下指向别处的符号链接同样是"仓库内容"，
    # 只 -type f 会让未跟踪的链接整个豁免。
    # 不加 2>/dev/null —— config/ 不存在时 find 的报错要看得见，不能吞掉。
    while IFS= read -r _f; do
        # .gitignore 明确排除的文件不是错误
        if git check-ignore -q -- "$_f"; then
            continue
        fi
        _tracked=$((_tracked + 1))
        if ! git ls-files --error-unmatch -- "$_f" >/dev/null 2>&1; then
            printf '[ERR]  文件未纳入 git: %s\n' "$_f" >&2
            _fail=1
        fi
    done < <(find config assets \( -type f -o -type l \) | sort)

    # 0 文件说明根本没扫到 config/assets（改名、缺目录、权限被拒）——
    # 这时第 2 项等于没查，不能算通过。跟第 1 项的 _checked==0 守卫同一标准。
    if ((_tracked == 0)); then
        printf '[ERR]  config/ assets/ 下没查到任何文件，第 2 项未实际生效\n' >&2
        _fail=1
    fi

    printf '        检查了 %d 个文件\n' "$_tracked" >&2
fi

# -- 结果 ---------------------------------------------------------------------
if [[ $_fail -eq 0 ]]; then
    printf '\n[OK] 仓库自检通过\n' >&2
else
    printf '\n[ERR] 仓库自检失败（见上面 [ERR] 行）\n' >&2
fi

exit "$_fail"
