#!/usr/bin/env bash
# =============================================================================
# scripts/config/matugen.sh -- matugen 模板部署
#
# 负责把 config/matugen/ 下的所有模板和配置部署到对应位置。
# 不负责执行 matugen（由首次登录时的 dms-matugen-init.service 触发）。
#
# 新增应用动态配色步骤：
#   1. 在 config/matugen/templates/ 下新增 <app>.tera
#   2. 在下方追加对应的 [templates.<app>] 条目即可
#
# 注意：本脚本在 desktop.sh（含 dms setup）之后运行。
#       config.toml 使用追加模式，不覆盖 DMS 已生成的配置，
#       避免破坏 DMS 自身的取色模板管线。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

# -- 模板文件 -----------------------------------------------------------------
header "matugen templates"
mkdir -p "$HOME/.config/matugen/templates"
for tpl in "$REPO_DIR/config/matugen/templates/"*.tera; do
    [[ -f "$tpl" ]] || continue
    copy_config "$tpl" "$HOME/.config/matugen/templates/$(basename "$tpl")"
done

# -- config.toml：追加而非覆盖 ------------------------------------------------
# dms setup 可能已经生成了自己的 matugen config.toml（含 DMS 自身的取色模板）。
# 这里只追加我们需要的 template 条目，完整保留 DMS 的配置。
header "matugen config (append)"
_cfg="$HOME/.config/matugen/config.toml"

if [[ ! -f "$_cfg" ]]; then
    # dms setup 未生成 config.toml，手动创建基础版本
    mkdir -p "$(dirname "$_cfg")"
    cat >"$_cfg" <<'EOF'
[config]
reload_apps = false
EOF
    success "Created: $_cfg"
fi

# BUG FIX: 原来检查 '[config.templates.fcitx5]' 但追加的是 '[templates.fcitx5]'，
# 导致检查永远为 false，每次运行都会重复追加。现在检查与追加的 header 保持一致。

# 追加 fcitx5 模板条目（幂等）
if ! grep -qF '[templates.fcitx5]' "$_cfg"; then
    cat >>"$_cfg" <<EOF

# fcitx5 候选框主题（由 matugen 在首次登录时生成，换壁纸时自动更新）
# 更新后由 fcitx5-theme-reload.path 触发 fcitx5 热重载
[templates.fcitx5]
input_path  = "$HOME/.config/matugen/templates/fcitx5.tera"
output_path = "$HOME/.local/share/fcitx5/themes/dms/theme.conf"
EOF
    success "Added fcitx5 template to: $_cfg"
else
    warn "fcitx5 template already in matugen config, skipping"
fi

# 追加 starship 模板条目（幂等）
if ! grep -qF '[templates.starship]' "$_cfg"; then
    cat >>"$_cfg" <<EOF

# starship 提示符动态配色（由 matugen 在首次登录时生成）
[templates.starship]
input_path  = "$HOME/.config/matugen/templates/starship.tera"
output_path  = "$HOME/.config/starship.toml"
EOF
    success "Added starship template to: $_cfg"
else
    warn "starship template already in matugen config, skipping"
fi

# 注意：~/.local/share/fcitx5/themes/dms/ 目录不在此处创建。
# 该目录由 dms-matugen-init.service 的 ExecStartPre 在首次登录时、
# matugen 实际运行前一刻创建，避免安装阶段出现空目录导致 fcitx5 崩溃。
unset _cfg
success "matugen config done"
