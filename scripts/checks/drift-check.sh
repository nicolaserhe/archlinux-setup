#!/usr/bin/env bash
# =============================================================================
# scripts/checks/drift-check.sh -- 仓库 ↔ 本机 配置漂移检查
#
# 用法：just drift   （或直接 bash scripts/checks/drift-check.sh）
#
# 和 `just check` 的分工：check 查"仓库自己是否自洽"，新克隆上就能跑；本脚本
# 比的是**仓库 vs 这台机器上已部署的文件**，只能在装过机的用户下跑。所以它
# 不在 `just all` 里 —— 门禁要求"任何克隆上结论确定"，而漂移结论本来就依赖
# 这台机器的状态。
#
# 归属从哪来：扫 scripts/ 下的部署调用点，调用 lib/fs.sh 里哪个 helper 就是
# 哪种归属。没有第二份清单要维护 —— 手写的 config-map.md 已经在这次排查里
# 腐烂过一轮，不能再造一个同类东西。
#
# 结论四类：
#   [DRIFT]   own/merge 文件内容与本机不一致。两个方向都要人看一眼：
#             仓库较新 = 改完没重跑部署；本机较新 = 本机手改，决定是否收回仓库。
#   [MISSING] 该部署的目标在机器上不存在（装漏了 / 被删了）。
#   [OK]      一致。
#   seed 模式不比内容：播种之后归运行时程序所有，它改成什么样都正常，只查在不在。
#
# 退出码：0 无待办；1 有 [DRIFT]/[MISSING]；2 检查本身没跑完整（解析失败）。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"

# 部署 helper 名 → 归属模式。改 lib/fs.sh 的 API 时同步改这里；漏改不会静默 ——
# verify-repo.sh 的第 3 项检查会发现"config/ 下有文件没被任何调用点引用"。
_deploy_fns='copy_config|copy_config_seed|copy_config_merge|copy_config_dir|install_config|install_config_root'

_parse_err=0

# -- 1. 解析部署调用点 --------------------------------------------------------
# 输出 TSV：mode \t src \t dest \t 出处；mode 为 ERR 表示这一行解析失败。
#
# 续行（行尾 \）先拼成一行：多行写法是本仓库的惯例，不拼只能读到截断的参数。
# 整行注释先跳过：注释里写出 helper 名字是正常的（本文件自己就写了），不能当调用点。
# 带 `;;` 的行也跳过：case 分支里会把函数名并列成 `a | b | c)` 这种模式串，
# 那不是调用点（本文件自己就有一处，第一版把它当成了调用点）。
#
# 边界：参数里不能有空格（当前仓库没有这种路径）。有空格会被拆成多个词，该行
# 参数数不足 → 报 ERR 退出。宁可报错，不能静默少检一个文件。
_parse_deploys() {
    local script="$1"
    awk '
        { text = $0 }
        text ~ /^[[:space:]]*#/ { next }
        text ~ /;;/ { next }
        { sub(/[[:space:]]#.*$/, "", text) }
        {
            start = NR
            while (text ~ /\\$/) {
                sub(/\\$/, "", text)
                if ((getline nxt) > 0) { text = text " " nxt } else { break }
            }
            printf "%d\t%s\n", start, text
        }
    ' "$script" |
        while IFS=$'\t' read -r lnum text; do
            read -r -a toks <<<"$text"
            local i fn_idx=-1
            for i in "${!toks[@]}"; do
                if [[ "${toks[$i]}" =~ ^($_deploy_fns)$ ]]; then
                    fn_idx=$i
                    break
                fi
            done
            if ((fn_idx < 0)); then
                # 这一行引用了仓库里的 config/ 文件，却不是任何部署 helper 的调用点
                # —— 就是"裸 cp / install / cat 部署"。
                #
                # 这是本检查唯一的假绿入口：这样部署的文件不会进归属清单，`just drift`
                # 从头到尾看不见它，而它自己一声不响。第一版的兜底是"config/ 下每个
                # 文件都要出现在清单里"，但那只在**替换**掉调用点时有效 —— 文件已由
                # 别处正当地部署过就照样通过（实测：在 keyd.sh 末尾加一行裸 cp 指向
                # 同一个 keyd.conf，旧版一声不吭）。改成看**每个引用点**。
                #
                # 和 verify-repo.sh 第 3 项（config/ 下无引用即死文件）不重叠：那条查
                # "有没有人引用"，构造上就放过裸 cp（裸 cp 也是引用）；这条查"引用在
                # 不在 API 上"，所以它只在 scripts/ 下生效、也不需要覆盖整个文件集。
                # 模式里 \$ 是转义的美元号：要匹配的是源码文本里的字面量 $REPO_DIR，
                # 不是本脚本的变量（写成单引号能匹配，但 shellcheck SC2016 会亮）。
                if [[ "$text" == *"\$REPO_DIR"/config/* || "$text" == *"\${REPO_DIR}"/config/* ]]; then
                    printf 'ERR\t-\t-\t%s:%s config/ 引用不在部署 helper 调用点上（裸 cp/install？）\n' \
                        "$script" "$lnum"
                fi
                continue
            fi

            local fn="${toks[$fn_idx]}" mode
            case "$fn" in
                copy_config | install_config | install_config_root | copy_config_dir) mode="own" ;;
                copy_config_seed) mode="seed" ;;
                copy_config_merge) mode="merge" ;;
            esac

            # 参数 = 函数名之后的所有 token。install_config* 的第 3 个参数是权限位，丢掉。
            local -a args=()
            for ((i = fn_idx + 1; i < ${#toks[@]}; i++)); do
                local a="${toks[$i]}"
                a="${a%\"}" a="${a#\"}" a="${a%\'}" a="${a#\'}"
                args+=("$a")
            done

            if ((${#args[@]} < 2)); then
                printf 'ERR\t-\t-\t%s:%s 参数不足（%s）\n' "$script" "$lnum" "$fn"
                continue
            fi

            printf '%s\t%s\t%s\t%s:%s\n' "$mode" "${args[0]}" "${args[1]}" "$script" "$lnum"
        done
}

# 展开 shell 变量/引号 → 绝对路径。展开不了留 $ 号，由调用方判 ERR ——
# 不猜、不跳过，跳过就是漏检。
_resolve() {
    local p="$1"
    p="${p//\$\{REPO_DIR\}/$REPO_DIR}"
    p="${p//\$REPO_DIR/$REPO_DIR}"
    p="${p//\$\{HOME\}/$HOME}"
    p="${p//\$HOME/$HOME}"
    if [[ "$p" == '~'* ]]; then
        p="$HOME${p#\~}"
    fi
    printf '%s' "$p"
}

# src 是目录（copy_config_dir）时展开成目录内每个文件一对；其余按原样收下。
#
# 扫描范围 = scripts/ 下所有 .sh（不含 scripts/checks/，那些是检查器）**外加
# install.sh**。install.sh 目前不部署任何配置，扫它是堵住"将来在 root 阶段加了
# 部署点却没人比对"这个洞。lib/ 则**不能**扫：helper 的函数体里就写着
# `copy_config "$f" "$dest/$(basename "$f")"` 这种样板，token 会被当成调用点，
# 产出无法解析的 ERR，整个检查会永远 exit 2。
_pairs=()
_parse_err_lines=()
while IFS= read -r _script; do
    while IFS=$'\t' read -r _m _s _d _where; do
        case "$_m" in
            ERR)
                _parse_err_lines+=("$_where")
                continue
                ;;
        esac
        _rs="$(_resolve "$_s")"
        _rd="$(_resolve "$_d")"
        if [[ "$_rs" == *'$'* || "$_rd" == *'$'* ]]; then
            _parse_err_lines+=("$_where 无法解析的路径（src=$_s dest=$_d）")
            continue
        fi
        if [[ -d "$_rs" ]]; then
            _inner=""
            for _inner in "$_rs"/*; do
                [[ -f "$_inner" ]] || continue
                _pairs+=("$_m"$'\t'"${_inner#"$REPO_DIR"/}"$'\t'"$_rd/$(basename "$_inner")")
            done
            continue
        fi
        _pairs+=("$_m"$'\t'"${_rs#"$REPO_DIR"/}"$'\t'"$_rd")
    done < <(_parse_deploys "$_script")
done < <({ find scripts -name '*.sh' -type f -not -path 'scripts/checks/*'; printf '%s\n' install.sh; } | sort)

# 解析失败的行必须让整个检查作废：少检的文件不会出现在结论里，读起来却像"干净"。
# scripts/checks/ 自己的脚本不参与扫描（它们是检查器，不部署配置），
# 第 2 个条件同时兜住"抽取逻辑整个失效"的情况。
if ((${#_parse_err_lines[@]} > 0)); then
    for _l in "${_parse_err_lines[@]}"; do
        printf '[ERR]  部署调用点解析失败：%s\n' "$_l" >&2
    done
    printf '\n[ERR] 解析不完整 —— 漂移结论不予采信\n' >&2
    exit 2
fi

if ((${#_pairs[@]} == 0)); then
    printf '[ERR]  没解析到任何部署调用点 —— 抽取逻辑可能已失效\n' >&2
    exit 2
fi

# -- 1b. 覆盖自检：config/ 下每个文件都要在归属清单里 -------------------------
# _parse_deploys 里的逐引用规则只管 scripts/ 下（那是调用点的所在），这一条补上
# 集合视角：不管文件是被 install.sh、usb/ 还是运行时拼出来的路径部署的，只要它
# 在 config/ 里而不在清单里，就报出来。两条一起把"某类部署静默逃出归属"堵死。
declare -A _in_inventory=()
for _p in "${_pairs[@]}"; do
    IFS=$'\t' read -r _m _s _d <<<"$_p"
    _in_inventory["$_s"]=1
done
_uncovered=0
while IFS= read -r _cf; do
    if [[ -z "${_in_inventory[$_cf]:-}" ]]; then
        printf '[ERR]  config/ 下的文件没走部署 API（归属未知，漂移检查看不见）: %s\n' "$_cf" >&2
        _uncovered=$((_uncovered + 1))
    fi
done < <(find config \( -type f -o -type l \) | sort)
unset _in_inventory _cf
if ((_uncovered > 0)); then
    printf '\n[ERR] 有 %d 个 config/ 文件不在归属清单里 —— 请改用 lib/fs.sh 的部署 helper\n' "$_uncovered" >&2
    exit 2
fi

# -- 2. 比对 ------------------------------------------------------------------
# 同一 (src,dest) 被声明多次时只留第一条，但归属模式不一致要报出来（同一个文件
# 有两种归属，说明调用点写矛盾了）。
declare -A _mode_of=()
_pairs_dedup=()
for _p in "${_pairs[@]}"; do
    IFS=$'\t' read -r _m _s _d <<<"$_p"
    _key="$_s|$_d"
    if [[ -n "${_mode_of[$_key]:-}" ]]; then
        [[ "${_mode_of[$_key]}" == "$_m" ]] ||
            printf '[ERR]  %s 的归属声明矛盾：%s vs %s\n' "$_s" "${_mode_of[$_key]}" "$_m" >&2
        continue
    fi
    _mode_of[$_key]="$_m"
    _pairs_dedup+=("$_p")
done
unset _mode_of

_ok=0 _drift=0 _missing=0 _seed=0 _repo_err=0
_drift_cmds=()

# 按 src 排序输出：调用点在文件里的物理顺序读起来是乱的，同一个应用的配置
# 又分散在 core/ 与 apps/ 两处，排序后至少能按目录成组看。
mapfile -t _pairs_dedup < <(printf '%s\n' "${_pairs_dedup[@]}" | sort -t$'\t' -k2,2)

# $HOME 开头缩成 ~ 只为读起来短。不用 ${dest/#$HOME/~}：bash 在模式替换的
# **替换串**里遇到 ~ 会整条不替换（zsh 不会，本仓库脚本是 bash），实测
# `bash -c 'HOME=/a; d=/a/b; echo "${d/#$HOME/~}"'` 原样输出 /a/b。
_tilde() {
    if [[ "$1" == "$HOME"/* ]]; then
        printf '~%s' "${1#"$HOME"}"
    else
        printf '%s' "$1"
    fi
}

_pair() {
    local verdict="$1" src="$2" dest="$3" note="${4:-}"
    printf '  %-9s %-44s -> %s\n' "$verdict" "$src" "$(_tilde "$dest")" >&2
    [[ -n "$note" ]] && printf '            %s\n' "$note" >&2
    return 0
}

# 时间戳只精确到分钟时，同一分钟内改的两边会显示成一样的时间，"谁较新"就成了
# 假结论（keyd.conf 那种情况：两边相差 13 秒）。所以精确到秒，且相等时明说看不出来。
_own_diff() {
    local src="$1" dest="$2"
    local abs="$REPO_DIR/$src"
    if [[ ! -f "$abs" ]]; then
        _pair "[ERR]" "$src" "$dest" "仓库里没有这个文件"
        _repo_err=$((_repo_err + 1))
        return 0
    fi
    if [[ ! -e "$dest" ]]; then
        _pair "[MISSING]" "$src" "$dest" "本机不存在（没装到 / 被删了）"
        _missing=$((_missing + 1))
        return 0
    fi
    if cmp -s "$abs" "$dest"; then
        _pair "[OK]" "$src" "$dest"
        _ok=$((_ok + 1))
        return 0
    fi
    local ts_s ts_d note
    ts_s="$(date -r "$abs" '+%m-%d %H:%M:%S')"
    ts_d="$(date -r "$dest" '+%m-%d %H:%M:%S')"
    if [[ "$ts_s" == "$ts_d" ]]; then
        note="两边时间戳相同（$ts_s）—— 看不出是谁改的，手工 diff"
    elif [[ "$abs" -nt "$dest" ]]; then
        note="仓库较新（$ts_s vs $ts_d）—— 改完没重跑部署"
    else
        note="本机较新（$ts_d vs $ts_s）—— 本机手改，决定是否收回仓库"
    fi
    _pair "[DRIFT]" "$src" "$dest" "$note"
    _drift=$((_drift + 1))
    # 相对仓库根 + ~ 缩写：这行是要被直接粘进终端跑的，绝对路径太长而且没法读
    _drift_cmds+=("$src  $(_tilde "$dest")")
    return 0
}

printf '\n==> 仓库拥有（own：每次 install 覆盖，不一致即漂移）\n' >&2
for _p in "${_pairs_dedup[@]}"; do
    IFS=$'\t' read -r _m _s _d <<<"$_p"
    [[ "$_m" == "own" ]] && _own_diff "$_s" "$_d"
done

printf '\n==> 仅首次播种（seed：之后归运行时程序，只查在不在）\n' >&2
for _p in "${_pairs_dedup[@]}"; do
    IFS=$'\t' read -r _m _s _d <<<"$_p"
    [[ "$_m" == "seed" ]] || continue
    if [[ ! -e "$_d" ]]; then
        _pair "[MISSING]" "$_s" "$_d" "从未播种过"
        _missing=$((_missing + 1))
        continue
    fi
    _pair "[OK]" "$_s" "$_d"
    _seed=$((_seed + 1))
done

printf '\n==> 共同拥有（merge：仓库只贡献若干键，运行时同时也在写）\n' >&2
for _p in "${_pairs_dedup[@]}"; do
    IFS=$'\t' read -r _m _s _d <<<"$_p"
    [[ "$_m" == "merge" ]] || continue
    if [[ ! -e "$_d" ]]; then
        _pair "[MISSING]" "$_s" "$_d" "本机不存在（merge 没跑过）"
        _missing=$((_missing + 1))
        continue
    fi
    # 比的是**仓库声明的键**，不是整个文件：
    #   - 标量键在本机有、值不同  → [DRIFT]。这类键写进仓库的目的就是"钉住"某个
    #     非默认值（如 lockBeforeSuspend），值被改掉说明钉的失效了 —— 只查键在不在
    #     会给出假绿，而"本机较新"的 own 那套结论在 merge 文件上无法套用。
    #   - 标量键在本机没有        → [INFO]。多是 DMS 按 spec 默认值跳过落盘（见
    #     docs/quirks/dms.md），区分不了"merge 没跑到"和"程序自己丢的"，不计结论。
    #   - list / dict 键不参与判定：list 语义是全量替换，运行时程序本来就会重写
    #     （用户拖个控件就变），比它只会制造噪音。
    #   - 本机多出来的键一律不管 —— 那是运行时拥有的状态。
    _m_drift=""
    _m_info=""
    if command -v python3 >/dev/null 2>&1; then
        while IFS=$'\t' read -r _tag _rest; do
            case "$_tag" in
            DRIFT) _m_drift="${_m_drift}${_m_drift:+；}${_rest}" ;;
            INFO) _m_info="${_m_info}${_m_info:+, }${_rest}" ;;
            NOTE) _m_info="${_m_info}${_m_info:+; }${_rest}" ;;
            esac
        done < <(python3 -I -c '
import json, sys
def scalars(o, p=""):
    out = {}
    for k, v in o.items():
        q = (p + "." + k) if p else k
        if isinstance(v, dict):
            out.update(scalars(v, q))
        elif not isinstance(v, list):
            out[q] = v
    return out
try:
    s = json.load(open(sys.argv[1]))
    d = json.load(open(sys.argv[2]))
except Exception as e:
    print("NOTE\tJSON 解析失败，跳过内容比对：%s" % e)
    sys.exit(0)
# __doc__ 是 merge-json-deep.py 的"设计注释"约定键，不是配置值
s.pop("__doc__", None)
ds = scalars(d)
for k, v in sorted(scalars(s).items()):
    if k not in ds:
        print("INFO\t%s" % k)
    elif ds[k] != v:
        print("DRIFT\t%s: 仓库=%s 本机=%s"
              % (k, json.dumps(v, ensure_ascii=False),
                 json.dumps(ds[k], ensure_ascii=False)))
' "$REPO_DIR/$_s" "$_d")
    fi

    if [[ -n "$_m_drift" ]]; then
        _pair "[DRIFT]" "$_s" "$_d" "仓库声明的键与本机值不同 —— $_m_drift"
        _drift=$((_drift + 1))
    else
        _pair "[OK]" "$_s" "$_d" "仓库声明的标量键都在且值一致"
        _ok=$((_ok + 1))
    fi
    if [[ -n "$_m_info" ]]; then
        printf '            [INFO] 仓库声明的键不在本机文件里（多为默认值不落盘，见 docs/quirks/dms.md）：%s\n' \
            "$_m_info" >&2
    fi
done

# -- 3. 结果 ------------------------------------------------------------------
if ((${#_drift_cmds[@]} > 0)); then
    printf '\n看差异：\n' >&2
    for _l in "${_drift_cmds[@]}"; do
        printf '  diff -u %s\n' "$_l" >&2
    done
fi

printf '\n==> 汇总：一致 %d · 漂移 %d · 缺失 %d · 播种在册 %d\n' \
    "$_ok" "$_drift" "$_missing" "$_seed" >&2

if ((_repo_err > 0)); then
    printf '[ERR] 有部署点指向仓库里不存在的文件（见上面 [ERR] 行）\n' >&2
    exit 2
fi

if ((_drift > 0 || _missing > 0)); then
    printf '[ERR] 有需要处理的漂移（[DRIFT]/[MISSING]）\n' >&2
    exit 1
fi

printf '[OK] 本机已部署的配置与仓库一致\n' >&2
