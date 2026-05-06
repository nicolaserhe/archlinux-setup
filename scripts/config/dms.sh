#!/usr/bin/env bash
# =============================================================================
# scripts/config/dms.sh -- DankMaterialShell 配置
#
# 资源文件：
#   config/dms/settings.json     → merge 进 ~/.config/DankMaterialShell/settings.json
#   config/dms/environment.conf  → ~/.config/environment.d/90-dms.conf
#   assets/wallpaper.*           → ~/.local/share/wallpapers/
#   assets/avatar.*              → ~/.local/share/avatars/
#
# 参考文档：https://danklinux.com/docs/dankmaterialshell/
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

# =============================================================================
# 1. DMS stub kdl 文件（niri include 引用，必须先存在以免 niri parse 失败）
# =============================================================================
header "DMS stub files"
mkdir -p "$HOME/.config/niri/dms"
for _kdl in colors layout alttab binds; do
    if [[ -f "$HOME/.config/niri/dms/$_kdl.kdl" ]]; then
        warn "Already exists, skipping: dms/$_kdl.kdl"
    else
        touch "$HOME/.config/niri/dms/$_kdl.kdl"
        success "Created stub: dms/$_kdl.kdl"
    fi
done
unset _kdl

# =============================================================================
# 2. dms setup（通过 expect 自动应答交互菜单）
# =============================================================================
header "DMS setup"
if command_exists dms; then
    if expect <<'EOF'
spawn dms setup

# 内嵌默认应答；新选项可在此追加
array set choices [list \
    privilege "sudo" \
    compositor "Niri" \
    terminal "Alacritty" \
    systemd "Yes" \
    deploy "y" \
]

# 在 expect 缓冲区中按选项名匹配编号；
# Tcl 中花括号会阻止变量替换，必须用双引号 + 反斜杠转义来构造正则
proc select_by_name {name} {
    set buffer $expect_out(buffer)
    set re "(\[0-9\]+)\\)\\s*$name"
    if {[regexp -nocase $re $buffer -> choice]} {
        return $choice
    }
    return ""
}

while {1} {
    expect {
        eof { break }
        -re {Choose one.*\[.*\]} {
            set choice [select_by_name $choices(privilege)]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Select compositor:} {
            set choice [select_by_name $choices(compositor)]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Select terminal:} {
            set choice [select_by_name $choices(terminal)]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Use systemd.*} {
            set choice [select_by_name $choices(systemd)]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Proceed with deployment\?.*} {
            send "$choices(deploy)\r"
        }
    }
}
EOF
    then
        success "dms setup completed"
    else
        warn "dms setup returned non-zero -- please verify manually after first login"
    fi
else
    warn "dms command not found -- skipping dms setup, please install and run manually"
fi

# =============================================================================
# 3. DMS settings.json
#
# dms setup 已生成含完整字段的 settings.json，整体覆盖会丢失 DMS 默认值；
# 用 python 把 config/dms/settings.json 中的少量自定义值 merge 进去。
# 若 dms setup 未生成文件（首次 dms 不可用），则直接复制作为兜底。
# =============================================================================
header "DMS settings.json"
_dms_settings="$HOME/.config/DankMaterialShell/settings.json"
mkdir -p "$HOME/.config/DankMaterialShell"

if [[ -f "$_dms_settings" ]]; then
    python3 - "$_dms_settings" "$REPO_DIR/config/dms/settings.json" <<'PYEOF'
import sys, json
dest_path, src_path = sys.argv[1], sys.argv[2]
with open(dest_path, encoding="utf-8") as f:
    data = json.load(f)
with open(src_path, encoding="utf-8") as f:
    overrides = json.load(f)
overrides.pop("__doc__", None)
data.update(overrides)
with open(dest_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
    success "DMS settings merged: $_dms_settings"
else
    copy_config "$REPO_DIR/config/dms/settings.json" "$_dms_settings"
    warn "DMS settings copied as-is (dms setup may not have run yet)"
fi
unset _dms_settings

# =============================================================================
# 4. DMS 环境变量
# 按 DMS 官方推荐放在 environment.d，systemd 在所有用户会话中加载
# =============================================================================
header "DMS environment (90-dms.conf)"
copy_config \
    "$REPO_DIR/config/dms/environment.conf" \
    "$HOME/.config/environment.d/90-dms.conf"

# =============================================================================
# 5. 修补 niri config.kdl
# =============================================================================
header "DMS niri config"
_niri_cfg="$HOME/.config/niri/config.kdl"

if [[ ! -f "$_niri_cfg" ]]; then
    mkdir -p "$(dirname "$_niri_cfg")"
    touch "$_niri_cfg"
    warn "niri config does not exist -- created empty file"
fi

if grep -qF 'include "dms/colors.kdl"' "$_niri_cfg"; then
    warn "niri: DMS include directive already exists, skipping"
else
    cat >>"$_niri_cfg" <<'NIRI_INCLUDE'

// DMS configuration file inclusion
include "dms/colors.kdl"
include "dms/layout.kdl"
include "dms/alttab.kdl"
include "dms/binds.kdl"
NIRI_INCLUDE
    success "niri: DMS include directive added"
fi

if grep -q "quickshell" "$_niri_cfg"; then
    warn "niri: quickshell layer-rule already exists, skipping"
else
    cat >>"$_niri_cfg" <<'NIRI_LAYER'

// DMS: Make quickshell wallpaper show on the niri overview layer
layer-rule {
    match namespace="^quickshell$"
    place-within-backdrop true
}
NIRI_LAYER
    success "niri: quickshell layer-rule added"
fi

if grep -q 'XDG_CURRENT_DESKTOP' "$_niri_cfg"; then
    warn "niri: environment block already exists, skipping"
else
    cat >>"$_niri_cfg" <<'NIRI_ENV'

// DMS / Wayland environment variables
environment {
    XDG_CURRENT_DESKTOP "niri"
    QT_QPA_PLATFORM "wayland"
    ELECTRON_OZONE_PLATFORM_HINT "auto"
    QT_QPA_PLATFORMTHEME "gtk3"
    QT_QPA_PLATFORMTHEME_QT6 "gtk3"
}
NIRI_ENV
    success "niri: environment block added"
fi
unset _niri_cfg

# =============================================================================
# 6. 绑定 dms 到 niri.service
# =============================================================================
header "DMS service binding"
ensure_xdg_runtime_dir
if systemctl --user add-wants niri.service dms 2>/dev/null; then
    success "DMS bound to niri.service via systemd wants"
else
    warn "systemctl --user add-wants failed -- run manually:"
    warn "  systemctl --user add-wants niri.service dms"
fi

# =============================================================================
# 7. 壁纸 + matugen 首次登录初始化
# =============================================================================
header "DMS wallpaper + matugen"

_wallpaper_src=""
if [[ -n "${WALLPAPER:-}" && -f "$WALLPAPER" ]]; then
    _wallpaper_src="$WALLPAPER"
    info "Wallpaper from WALLPAPER env: $_wallpaper_src"
else
    _wallpaper_src="$(find_asset "$REPO_DIR/assets" "wallpaper.*")"
fi
[[ -n "$_wallpaper_src" ]] || die "Wallpaper not found -- add assets/wallpaper.jpg (or .png) to the repo"

mkdir -p "$HOME/.local/share/wallpapers"
_wallpaper_dest="$HOME/.local/share/wallpapers/$(basename "$_wallpaper_src")"
cp "$_wallpaper_src" "$_wallpaper_dest"
success "Wallpaper copied: $_wallpaper_dest"

mkdir -p "$HOME/.local/state/DankMaterialShell"
cat >"$HOME/.local/state/DankMaterialShell/session.json" <<EOF
{
  "wallpaperPath": "${_wallpaper_dest}",
  "wallpaperFillMode": "PreserveAspectCrop"
}
EOF
success "Written: DMS session.json"

# matugen one-shot：首次 niri 登录后跑一次，跑完自我禁用，避免重复执行。
# ExecStartPre 创建 fcitx5 主题目录；ExecStartPost(1) 重启 fcitx5 让 theme.conf
# 立即生效（前缀 - 表示忽略失败）；ExecStartPost(2) 自我 disable。
if command_exists dms; then
    mkdir -p "$HOME/.config/systemd/user"
    cat >"$HOME/.config/systemd/user/dms-matugen-init.service" <<EOF
[Unit]
Description=DMS matugen initial color scheme generation
After=graphical-session.target dms.service
Wants=dms.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/mkdir -p %h/.local/share/fcitx5/themes/dms
ExecStart=/usr/bin/dms matugen generate --state-dir %h/.local/state/DankMaterialShell --value ${_wallpaper_dest}
ExecStartPost=-/usr/bin/systemctl --user restart fcitx5.service
ExecStartPost=/usr/bin/systemctl --user disable dms-matugen-init.service
RemainAfterExit=no

[Install]
WantedBy=graphical-session.target
EOF
    add_user_service_wants dms-matugen-init.service graphical-session.target
    success "DMS matugen will run automatically on first niri login"
else
    warn "dms not found -- skipping matugen service"
fi

# =============================================================================
# 8. 头像 + AccountsService
# =============================================================================
header "DMS profile picture"

_avatar_src="$(find_asset "$REPO_DIR/assets" "avatar.*")"
[[ -n "$_avatar_src" ]] || die "Avatar not found -- add assets/avatar.png (or .jpg) to the repo"

mkdir -p "$HOME/.local/share/avatars"
_avatar_dest="$HOME/.local/share/avatars/$(basename "$_avatar_src")"
cp "$_avatar_src" "$_avatar_dest"
success "Avatar copied: $_avatar_dest"

# AccountsService 是 DMS 读取头像路径的 IPC 入口
_acct_dir="/var/lib/AccountsService/users"
_acct_file="$_acct_dir/$(whoami)"
if sudo mkdir -p "$_acct_dir" 2>/dev/null; then
    if [[ -f "$_acct_file" ]]; then
        if grep -q '^Icon=' "$_acct_file"; then
            sudo sed -i "s|^Icon=.*|Icon=${_avatar_dest}|" "$_acct_file"
        else
            sudo sed -i '/^\[User\]/a '"Icon=${_avatar_dest}" "$_acct_file"
        fi
    else
        printf '[User]\nIcon=%s\n' "$_avatar_dest" \
            | sudo tee "$_acct_file" >/dev/null
    fi
    success "AccountsService avatar set: $_avatar_dest"
else
    warn "Cannot write AccountsService -- IPC service will handle it on first login"
fi
unset _acct_dir _acct_file

# =============================================================================
# 9. dms-initial-settings：首次登录用 IPC 刷新头像显示
# =============================================================================
header "DMS initial settings IPC service"
mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/dms-initial-settings.service" <<EOF
[Unit]
Description=DMS initial profile picture IPC refresh (first login)
After=dms.service graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/dms ipc call profile setImage ${_avatar_dest}
ExecStartPost=/usr/bin/systemctl --user disable dms-initial-settings.service
RemainAfterExit=no

[Install]
WantedBy=graphical-session.target
EOF
add_user_service_wants dms-initial-settings.service graphical-session.target
success "DMS profile IPC refresh scheduled for first niri login"

unset _wallpaper_src _wallpaper_dest _avatar_src _avatar_dest
success "DMS config done"

# 注：~/.local/share/fcitx5/themes/dms/ 由 fcitx.sh 在安装阶段创建。
# 即使 theme.conf 缺失，fcitx5 也会 fallback 到默认主题，不会崩溃。
