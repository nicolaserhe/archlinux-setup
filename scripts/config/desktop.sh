#!/usr/bin/env bash
# =============================================================================
# scripts/config/desktop.sh -- Starship / Kanata / greetd / Bluetooth / PipeWire / DMS
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

# -- Kanata -------------------------------------------------------------------
header "Kanata"
copy_config "$REPO_DIR/config/input/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"

mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/kanata.service" <<'EOF'
[Unit]
Description=Kanata keyboard remapper
Documentation=https://github.com/jtroo/kanata

[Service]
Type=simple
ExecStart=/usr/bin/kanata --cfg %h/.config/kanata/kanata.kbd
Restart=on-failure

[Install]
WantedBy=default.target
EOF
success "Written: kanata.service"

# -- Kanata 输入权限 ----------------------------------------------------------
header "Kanata input permissions"

if [[ ! -f /etc/modules-load.d/uinput.conf ]]; then
    echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
    success "Written: /etc/modules-load.d/uinput.conf"
else
    warn "/etc/modules-load.d/uinput.conf already exists, skipping"
fi

_UINPUT_RULE='/etc/udev/rules.d/99-uinput.rules'
if [[ ! -f "$_UINPUT_RULE" ]]; then
    echo 'KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"' |
        sudo tee "$_UINPUT_RULE" >/dev/null
    success "Written: $_UINPUT_RULE"
else
    warn "$_UINPUT_RULE already exists, skipping"
fi
unset _UINPUT_RULE

sudo groupadd -f uinput
for _grp in input uinput; do
    if id -nG "$(whoami)" | grep -qw "$_grp"; then
        warn "Already in group $_grp, skipping"
    else
        sudo usermod -aG "$_grp" "$(whoami)"
        success "Added $(whoami) to group $_grp (re-login to apply)"
    fi
done
unset _grp

# -- greetd -------------------------------------------------------------------
header "greetd"

sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd niri-session --time --remember --asterisks"
user = "greeter"
EOF
success "Written: /etc/greetd/config.toml"

switch_display_manager greetd.service

# -- Bluetooth ----------------------------------------------------------------
header "Bluetooth"
enable_system_service bluetooth.service

# -- Power profiles -----------------------------------------------------------
header "Power profiles"
enable_system_service power-profiles-daemon.service

# -- systemd user daemon-reload -----------------------------------------------
header "systemd user daemon-reload"
systemctl --user daemon-reload 2>/dev/null &&
    success "systemd user daemon reloaded" ||
    warn "systemd --user daemon-reload failed (no live session?)"

# -- PipeWire -----------------------------------------------------------------
header "PipeWire"
for _svc in pipewire pipewire-pulse wireplumber; do
    enable_user_service "$_svc.service"
done
unset _svc

# -- Kanata enable ------------------------------------------------------------
header "Kanata enable"
enable_user_service kanata.service

# -- GTK 动态取色 -------------------------------------------------------------
# BUG FIX: adw-gtk-theme 已由 pacman.sh 安装，但 Nautilus 等 GTK 应用若没有通过
# gsettings 把主题切换到 adw-gtk3-dark，则 DMS 生成的 dank-colors.css 无法生效。
# 同时预先写入 @import 兜底规则，DMS gtkThemingEnabled=true 会在首次运行时把这两个
# 文件替换成真正指向 dank-colors.css 的 symlink。
# 修复：niri 是非 GNOME 环境，settings.ini 才是 GTK 原生配置方式，不依赖 D-Bus
header "GTK dynamic theming"
for _gtkv in gtk-3.0 gtk-4.0; do
    _gtkd="$HOME/.config/$_gtkv"
    mkdir -p "$_gtkd"
    # settings.ini 由 GTK 直接读取，不经 D-Bus，niri session 下正确做法
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

    # BUG FIX: DMS gtkThemingEnabled=true 运行时会创建 gtk.css -> dank-colors.css
    # 的软链接，但首次登录前该链接不存在，GTK 应用无法加载动态配色。
    # 此处预先创建软链接，DMS 运行后会原地覆盖（幂等）。
    ln -sf dank-colors.css "$_gtkd/gtk.css"
    success "Created symlink: $_gtkd/gtk.css -> dank-colors.css"
done
unset _gtkv _gtkd

# -- Alacritty ----------------------------------------------------------------
header "Alacritty"
mkdir -p "$HOME/.config/alacritty"
copy_config "$REPO_DIR/config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# -- DMS ----------------------------------------------------------------------
bash "$REPO_DIR/scripts/config/dms.sh"

success "Desktop config done"
