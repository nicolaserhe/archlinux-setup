#!/usr/bin/env bash
# =============================================================================
# scripts/config/desktop.sh -- Kanata / greetd / Bluetooth / PipeWire / GTK / DMS
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

# 私有：用 sudo + tee 原子写入 root 拥有的文件，已存在则跳过
_sudo_write_if_absent() {
    local path="$1" content="$2"
    if [[ -f "$path" ]]; then
        warn "$path already exists, skipping"
    else
        sudo mkdir -p "$(dirname "$path")"
        printf '%s\n' "$content" | sudo tee "$path" >/dev/null
        success "Written: $path"
    fi
}

# -- Kanata 配置 --------------------------------------------------------------
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

_sudo_write_if_absent /etc/modules-load.d/uinput.conf "uinput"

_sudo_write_if_absent /etc/udev/rules.d/99-uinput.rules \
    'KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"'

sudo groupadd -f uinput
_user="$(whoami)"
for _grp in input uinput; do
    add_user_to_group "$_user" "$_grp"
done
unset _user _grp

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

# -- systemd user daemon-reload ----------------------------------------------
header "systemd user daemon-reload"
if systemctl --user daemon-reload 2>/dev/null; then
    success "systemd user daemon reloaded"
else
    warn "systemd --user daemon-reload failed (no live session?)"
fi

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
# adw-gtk-theme 由 pacman.sh 安装，但 GTK 应用必须显式指定 adw-gtk3-dark
# 才会加载 DMS 生成的 dank-colors.css。niri 是非 GNOME 环境，settings.ini
# 由 GTK 直接读取，不依赖 D-Bus / gsettings，是最可靠的方案。
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

# -- Alacritty ----------------------------------------------------------------
header "Alacritty"
copy_config \
    "$REPO_DIR/config/alacritty/alacritty.toml" \
    "$HOME/.config/alacritty/alacritty.toml"

# -- DMS ----------------------------------------------------------------------
bash "$REPO_DIR/scripts/config/dms.sh"

success "Desktop config done"
