#!/usr/bin/env bash
# =============================================================================
# scripts/config/matugen.sh -- matugen 模板部署
#
# 只负责把 config/matugen/ 下的模板和配置追加部署到目标位置；
# 不直接执行 matugen，由首次登录的 dms-matugen-init.service 触发。
#
# 新增动态配色应用：
#   1. 在 config/matugen/templates/ 下新增 <app>.tera
#   2. 在下方追加对应的 _append_template 调用
#
# 必须在 desktop.sh（含 dms setup）之后运行：
# config.toml 使用追加模式，不覆盖 DMS 已生成的配置。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

_MATUGEN_CFG="$HOME/.config/matugen/config.toml"

# _append_template <name> <comment> <input> <output>
# 用 [templates.<name>] header 作为幂等 marker（dms setup 写入的 header 风格相同）
_append_template() {
    local name="$1" comment="$2" input="$3" output="$4"
    local marker="[templates.${name}]"

    if grep -qF "$marker" "$_MATUGEN_CFG"; then
        warn "$name template already in matugen config, skipping"
        return 0
    fi

    cat >>"$_MATUGEN_CFG" <<EOF

# ${comment}
${marker}
input_path  = "${input}"
output_path = "${output}"
EOF
    success "Added $name template to: $_MATUGEN_CFG"
}

# -- 模板文件 -----------------------------------------------------------------
header "matugen templates"
mkdir -p "$HOME/.config/matugen/templates"
for tpl in "$REPO_DIR/config/matugen/templates/"*.tera; do
    [[ -f "$tpl" ]] || continue
    copy_config "$tpl" "$HOME/.config/matugen/templates/$(basename "$tpl")"
done

# -- config.toml：追加而非覆盖 ------------------------------------------------
# dms setup 可能已生成 config.toml（含 DMS 自身的取色模板），完整保留它，
# 仅追加我们需要的 template 条目。
header "matugen config (append)"
if [[ ! -f "$_MATUGEN_CFG" ]]; then
    mkdir -p "$(dirname "$_MATUGEN_CFG")"
    cat >"$_MATUGEN_CFG" <<'EOF'
[config]
reload_apps = false
EOF
    success "Created: $_MATUGEN_CFG"
fi

_append_template fcitx5 \
    "fcitx5 候选框主题（首次登录时由 matugen 生成，theme.conf 变化时由 path unit 触发热重载）" \
    "$HOME/.config/matugen/templates/fcitx5.tera" \
    "$HOME/.local/share/fcitx5/themes/dms/theme.conf"

_append_template starship \
    "starship 提示符动态配色（首次登录时由 matugen 生成）" \
    "$HOME/.config/matugen/templates/starship.tera" \
    "$HOME/.config/starship.toml"

# 注：~/.local/share/fcitx5/themes/dms/ 由 dms-matugen-init.service 的
# ExecStartPre 在 matugen 实际运行前创建，避免安装阶段的空目录让 fcitx5 误识别。
success "matugen config done"
