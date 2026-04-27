#!/usr/bin/env bash
# =============================================================================
# scripts/core/matugen.sh -- matugen 模板部署
#
# 只负责把 config/matugen/ 下的模板和配置追加部署到目标位置；
# 不直接执行 matugen，由首次登录的 dms-matugen-init.service 触发。
#
# 新增动态配色应用：
#   1. 在 config/matugen/templates/ 下新增 <app>.tera
#   2. 在下方追加对应的 _set_template 调用（会覆盖 DMS 同名 entry）
#
# 必须在 dms.sh 之后运行：dms setup 已经把 config.toml 创建好并写入 DMS
# 自带的 [templates.*]，本脚本只对其中需要自定义的部分做 set 覆盖。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

_MATUGEN_CFG="$HOME/.config/matugen/config.toml"

# _set_template <name> <comment> <input> <output>
# 强制让我们的 [templates.<name>] 生效：dms setup 可能已写入同名 entry
# （指向 DMS 自带模板），先把整个旧 block 切掉再追加我们的版本。
# 这样无论 DMS 默认改成什么，只要我们配了 _set_template，最终都用仓库里的模板。
_set_template() {
    local name="$1" comment="$2" input="$3" output="$4"
    local marker="[templates.${name}]"

    if grep -qF "$marker" "$_MATUGEN_CFG"; then
        # 切除原 block：marker 行 + 中间所有内容，直到下一个 [section] 或 EOF。
        # 同时回吃 marker 上方紧贴的注释 + 一个分隔空行（DMS 写入风格固定如此）。
        python3 - "$_MATUGEN_CFG" "$marker" <<'PYEOF'
import sys
from pathlib import Path

path, marker = sys.argv[1], sys.argv[2]
lines = Path(path).read_text(encoding="utf-8").splitlines()

start = next((i for i, ln in enumerate(lines) if ln.strip() == marker), None)
if start is None:
    sys.exit(0)

end = len(lines)
for i in range(start + 1, len(lines)):
    s = lines[i].lstrip()
    if s.startswith("[") and "]" in s:
        end = i
        break

# 回吃 block 之前的注释 + 一个空行，但只当这些注释是"引言式"——也就是
# 它们与上一段内容之间有空行隔开（或位于文件开头）；否则那是上一个 block
# 的尾注释，不能吃。
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

Path(path).write_text("\n".join(new) + "\n", encoding="utf-8")
PYEOF
        info "Removed existing [templates.${name}] block"
    fi

    cat >>"$_MATUGEN_CFG" <<EOF

# ${comment}
${marker}
input_path  = "${input}"
output_path = "${output}"
EOF
    success "Set $name template in: $_MATUGEN_CFG"
}

# -- 模板文件 -----------------------------------------------------------------
# 仓库 ship 自己的模板而不依赖 dms setup：v1.4.6 的 dms setup 已经不再
# deploy 完整模板集（仅写 config.toml），如果还信赖 DMS 的 fcitx5-theme.conf
# 这种文件存在，会出现 config.toml 指向不存在路径、matugen 静默 skip 的诡异
# bug（fcitx5 主题文件永远不生成）。
header "matugen templates"
mkdir -p "$HOME/.config/matugen/templates"
for tpl in "$REPO_DIR/config/matugen/templates/"*.tera; do
    [[ -f "$tpl" ]] || continue
    copy_config "$tpl" "$HOME/.config/matugen/templates/$(basename "$tpl")"
done

# -- config.toml：保留 DMS 写入的内容，按需 set 我们的模板 --------------------
# dms setup 已生成 config.toml（含 DMS 自身的多个 [templates.*]），完整保留；
# 我们用 _set_template 把要自定义的 entry 强制覆盖成仓库版本。
header "matugen config (set)"
if [[ ! -f "$_MATUGEN_CFG" ]]; then
    mkdir -p "$(dirname "$_MATUGEN_CFG")"
    cat >"$_MATUGEN_CFG" <<'EOF'
[config]
reload_apps = false
EOF
    success "Created: $_MATUGEN_CFG"
fi

_set_template fcitx5 \
    "fcitx5 候选框主题（DMS v1.4.6 不再 deploy 自带模板，必须自己 ship）" \
    "$HOME/.config/matugen/templates/fcitx5.tera" \
    "$HOME/.local/share/fcitx5/themes/Matugen/theme.conf"

_set_template starship \
    "starship 提示符动态配色（首次登录时由 matugen 生成）" \
    "$HOME/.config/matugen/templates/starship.tera" \
    "$HOME/.config/starship.toml"

success "matugen done"
