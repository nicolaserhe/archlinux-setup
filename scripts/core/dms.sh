#!/usr/bin/env bash
# =============================================================================
# scripts/core/dms.sh -- DankMaterialShell 桌面 shell
#
# 资源文件：
#   config/dms/settings.json     → merge 进 ~/.config/DankMaterialShell/settings.json
#   config/dms/environment.conf  → ~/.config/environment.d/90-dms.conf
#   config/dms/portals.conf      → ~/.config/xdg-desktop-portal/portals.conf
#   config/dms/xdpw.conf         → ~/.config/xdg-desktop-portal-wlr/config
#   config/niri/dms/binds.kdl    → ~/.config/niri/dms/binds.kdl
#   config/niri/dms/windowrules.kdl → ~/.config/niri/dms/windowrules.kdl
#   assets/wallpaper.*           → ~/.local/share/wallpapers/
#   assets/avatar.*              → ~/.local/share/avatars/
#
# 参考文档：https://danklinux.com/docs/dankmaterialshell/
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- DMS 包安装 ---------------------------------------------------------------
# dms-shell-niri: DankMaterialShell 主体（Go backend + Quickshell 前端）
# matugen:        Material You 取色引擎（DMS 用它从壁纸生成主题色）
header "DMS packages (AUR)"
aur_install dms-shell-niri matugen

# =============================================================================
# 1. DMS include 引用的 kdl 文件
# =============================================================================
# - colors / layout / alttab：niri 仅需文件存在（让 include 不报错），内容由
#   DMS 自己写（colors）或空着即可（layout/alttab DMS 不一定填）
# - binds：dms setup v1.4.6+ 不再填，仓库 ship 一份默认（DMS IPC 优先）
header "DMS stub files (colors/layout/alttab)"
mkdir -p "$HOME/.config/niri/dms"
for _kdl in colors layout alttab; do
    if [[ -f "$HOME/.config/niri/dms/$_kdl.kdl" ]]; then
        warn "Already exists, skipping: dms/$_kdl.kdl"
    else
        touch "$HOME/.config/niri/dms/$_kdl.kdl"
        success "Created stub: dms/$_kdl.kdl"
    fi
done
unset _kdl

header "DMS niri binds.kdl"
copy_config \
    "$REPO_DIR/config/niri/dms/binds.kdl" \
    "$HOME/.config/niri/dms/binds.kdl"

header "DMS niri windowrules.kdl"
copy_config \
    "$REPO_DIR/config/niri/dms/windowrules.kdl" \
    "$HOME/.config/niri/dms/windowrules.kdl"

# =============================================================================
# 2. dms setup（通过 expect 自动应答交互菜单）
# =============================================================================
header "DMS setup"
if command_exists dms; then
    if expect "$REPO_DIR/scripts/core/helpers/dms-setup.exp"; then
        success "dms setup completed"
    else
        warn "dms setup returned non-zero -- please verify manually after first login"
    fi
else
    warn "dms command not found -- skipping dms setup, please install and run manually"
fi

# =============================================================================
# 3. DMS settings.json（保留 dms setup 默认值，merge 自定义字段）
# =============================================================================
header "DMS settings.json"
_dms_settings="$HOME/.config/DankMaterialShell/settings.json"
mkdir -p "$HOME/.config/DankMaterialShell"

if [[ -f "$_dms_settings" ]]; then
    python3 - "$_dms_settings" "$REPO_DIR/config/dms/settings.json" <<'PYEOF'
import sys, json

def deep_merge(dst, src):
    """嵌套 dict 递归合并；非 dict 值按 src 覆盖。
    list 直接整体覆盖（DMS 的 controlCenterWidgets 等数组语义是"全量替换"）。"""
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            deep_merge(dst[k], v)
        else:
            dst[k] = v

dest_path, src_path = sys.argv[1], sys.argv[2]
with open(dest_path, encoding="utf-8") as f:
    data = json.load(f)
with open(src_path, encoding="utf-8") as f:
    overrides = json.load(f)
overrides.pop("__doc__", None)
deep_merge(data, overrides)
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
# 4. DMS 环境变量 + Portal 配置
# =============================================================================
header "DMS environment (90-dms.conf)"
copy_config \
    "$REPO_DIR/config/dms/environment.conf" \
    "$HOME/.config/environment.d/90-dms.conf"

header "XDG portal config (portals.conf)"
copy_config \
    "$REPO_DIR/config/dms/portals.conf" \
    "$HOME/.config/xdg-desktop-portal/portals.conf"
copy_config \
    "$REPO_DIR/config/dms/xdpw.conf" \
    "$HOME/.config/xdg-desktop-portal-wlr/config"

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
include "dms/windowrules.kdl"
NIRI_INCLUDE
    success "niri: DMS include directive added"
fi

# windowrules.kdl include（v1.4.6+ 新加；初始 include 块已含，但老安装需补）
if grep -qF 'include "dms/windowrules.kdl"' "$_niri_cfg"; then
    warn "niri: windowrules include already exists, skipping"
else
    echo 'include "dms/windowrules.kdl"' >>"$_niri_cfg"
    success "niri: windowrules include added"
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

# Valent spawn-at-startup（集中在此，避免 kdeconnect.sh 也写 config.kdl）
# SSH_AUTH_SOCK 通过 environment.d/valent.conf 注入，不能加进上面的 environment{}
# 块——niri 不允许同名顶层块重复出现。
if grep -q 'hotkey-overlay' "$_niri_cfg"; then
    warn "niri: hotkey-overlay block already exists, skipping"
else
    cat >>"$_niri_cfg" <<'NIRI_HOTKEY'

// 禁用开机自动弹出的快捷键说明浮层
hotkey-overlay {
    skip-at-startup
}
NIRI_HOTKEY
    success "niri: hotkey-overlay skip-at-startup added"
fi

if grep -q 'valent' "$_niri_cfg"; then
    warn "niri: valent spawn-at-startup already exists, skipping"
else
    cat >>"$_niri_cfg" <<'NIRI_VALENT'

// KDE Connect / Valent: 作为后台 gapplication service 启动
// SSH_AUTH_SOCK 由 environment.d/valent.conf 提供
spawn-at-startup "systemctl" "--user" "import-environment" "SSH_AUTH_SOCK"
spawn-at-startup "valent" "--gapplication-service"
NIRI_VALENT
    success "niri: valent spawn-at-startup appended"
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
# 后续换壁纸时由 DMS 自身的 watcher 触发 matugen；fcitx5 重启则由
# fcitx5-theme-reload.path（fcitx.sh 创建）监视 theme.conf 触发。
if command_exists dms; then
    mkdir -p "$HOME/.config/systemd/user"
    cat >"$HOME/.config/systemd/user/dms-matugen-init.service" <<EOF
[Unit]
Description=DMS matugen initial color scheme generation
After=graphical-session.target dms.service dms-initial-settings.service
Wants=dms.service

[Service]
Type=oneshot
SuccessExitStatus=2
# v1.4.6+ 起 --shell-dir 是必填；pacman 装的 dms-shell 这个值固定是
# /usr/share/quickshell/dms（dms.service 自己起 quickshell 时用的也是它）
ExecStart=/usr/bin/dms matugen generate --shell-dir /usr/share/quickshell/dms --state-dir %h/.local/state/DankMaterialShell --config-dir %h/.config/DankMaterialShell --value ${_wallpaper_dest}
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
        printf '[User]\nIcon=%s\n' "$_avatar_dest" |
            sudo tee "$_acct_file" >/dev/null
    fi
    success "AccountsService avatar set: $_avatar_dest"
else
    warn "Cannot write AccountsService -- IPC service will handle it on first login"
fi
unset _acct_dir _acct_file

# =============================================================================
# 9. dms-initial-settings：首次登录用 IPC 强制写入需要 DMS runtime 介入的设置
#
# - profile setImage：刷新头像（settings.json 不直接驱动）
# - settings set gtkThemingEnabled true：DMS 启动时会把 settings.json 里 merge
#   进去的 true 重置回 false（推测是 runtime 校验失败），故必须在 DMS 跑起来后
#   通过 IPC 反复写入，保证 GTK 应用能跟随 matugen 颜色刷新 dank-colors.css。
# =============================================================================
header "DMS initial settings IPC service"
mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/dms-initial-settings.service" <<EOF
[Unit]
Description=DMS initial settings IPC writes (first login)
After=dms.service graphical-session.target
Before=dms-matugen-init.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/dms ipc settings set gtkThemingEnabled true
ExecStart=/usr/bin/dms ipc profile setImage ${_avatar_dest}
ExecStartPost=/usr/bin/systemctl --user disable dms-initial-settings.service
RemainAfterExit=no

[Install]
WantedBy=graphical-session.target
EOF
add_user_service_wants dms-initial-settings.service graphical-session.target
success "DMS initial-settings IPC scheduled for first niri login"

unset _wallpaper_src _wallpaper_dest _avatar_src _avatar_dest

# =============================================================================
# 10. GTK 动态取色
#
# adw-gtk-theme 由 01-pacman-base.sh 安装，但 GTK 应用必须显式指定 adw-gtk3-dark
# 才会加载 DMS 生成的 dank-colors.css。niri 是非 GNOME 环境，settings.ini
# 由 GTK 直接读取，不依赖 D-Bus / gsettings，是最可靠的方案。
# =============================================================================
header "GTK dynamic theming"
for _gtkv in gtk-3.0 gtk-4.0; do
    _gtkd="$HOME/.config/$_gtkv"
    mkdir -p "$_gtkd"
    if [[ ! -f "$_gtkd/settings.ini" ]]; then
        cat >"$_gtkd/settings.ini" <<'GTKINI'
[Settings]
gtk-theme-name = adw-gtk3-dark
gtk-application-prefer-dark-theme = 1
GTKINI
        success "Created $_gtkd/settings.ini"
    elif ! grep -q 'gtk-theme-name' "$_gtkd/settings.ini"; then
        sed -i '/^\[Settings\]/a gtk-theme-name = adw-gtk3-dark' "$_gtkd/settings.ini"
        success "Updated $_gtkd/settings.ini: gtk-theme-name = adw-gtk3-dark"
    else
        warn "$_gtkd/settings.ini: gtk-theme-name already set, skipping"
    fi

    # 预先创建 gtk.css -> dank-colors.css 软链；DMS gtkThemingEnabled=true
    # 首次运行时会原地覆盖（幂等），覆盖前 GTK 应用已可加载动态配色
    ln -sf dank-colors.css "$_gtkd/gtk.css"
    success "Created symlink: $_gtkd/gtk.css -> dank-colors.css"
done
unset _gtkv _gtkd

success "DMS done"
