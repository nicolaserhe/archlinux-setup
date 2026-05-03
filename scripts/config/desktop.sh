#!/usr/bin/env bash
# =============================================================================
# scripts/config/desktop.sh -- Starship / Kanata / greetd / Bluetooth / PipeWire / DMS
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

# -- Starship -----------------------------------------------------------------
header "Starship"
copy_config "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"

# -- Kanata -------------------------------------------------------------------
header "Kanata"
copy_config "$REPO_DIR/config/kanata.kbd" "$HOME/.config/kanata/kanata.kbd"

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

# -- Kanata input permissions -------------------------------------------------
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

sudo groupadd -f uinput
for _grp in input uinput; do
    if id -nG "$(whoami)" | grep -qw "$_grp"; then
        warn "Already in group $_grp, skipping"
    else
        sudo usermod -aG "$_grp" "$(whoami)"
        success "Added $(whoami) to group $_grp (re-login to apply)"
    fi
done
unset _grp _UINPUT_RULE

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

# -- DankMaterialShell --------------------------------------------------------
header "DankMaterialShell"
yes | dms setup &&
    success "dms setup done" ||
    warn "dms setup returned non-zero -- check manually"
add_user_service_wants dms.service niri.service

# -- niri include DMS 配置文件 ------------------------------------------------
# dms setup 会把颜色/布局/按键等写到 ~/.config/niri/dms/*.kdl，
# 但不会自动在 config.kdl 里 include 它们，需要手动注入。
header "niri DMS includes"
_niri_cfg="$HOME/.config/niri/config.kdl"
_dms_dir="$HOME/.config/niri/dms"
if [[ -f "$_niri_cfg" && -d "$_dms_dir" ]]; then
    for _kdl in "$_dms_dir"/*.kdl; do
        _fname="$(basename "$_kdl")"
        if ! grep -qF "dms/$_fname" "$_niri_cfg"; then
            echo "include \"$_dms_dir/$_fname\"" >>"$_niri_cfg"
            success "niri: included dms/$_fname"
        else
            warn "niri: dms/$_fname already included, skipping"
        fi
    done
else
    warn "niri config or dms dir not found -- skipping"
fi
unset _niri_cfg _dms_dir _kdl _fname

# -- Alacritty 字体修补 + DMS 取色 import ------------------------------------
# DMS 完全管理 Alacritty 主题/颜色，默认生成 dank-theme.toml，
# 但 alacritty.toml 默认 import 的是 dracula.toml，需要替换。
header "Alacritty font patch"
_alacritty_cfg="$HOME/.config/alacritty/alacritty.toml"
if [[ -f "$_alacritty_cfg" ]]; then
    # 将默认 dracula.toml import 替换为 DMS 壁纸取色的 dank-theme.toml
    if grep -q 'dracula\.toml' "$_alacritty_cfg"; then
        sed -i 's|dracula\.toml|dank-theme.toml|g' "$_alacritty_cfg"
        success "Alacritty import switched to dank-theme.toml"
    elif ! grep -q 'dank-theme' "$_alacritty_cfg"; then
        sed -i "1s|^|general.import = [\"~/.config/alacritty/dank-theme.toml\"]\n\n|" "$_alacritty_cfg"
        success "Alacritty dank-theme import added"
    else
        warn "dank-theme import already present, skipping"
    fi

    # 字体补丁
    if grep -q '^\[font\]' "$_alacritty_cfg"; then
        sed -i \
            -e '/^\[font\]/,/^\[/{s|^normal\s*=.*|normal = { family = "Maple Mono NL NF CN" }|}' \
            -e '/^\[font\]/,/^\[/{s|^size\s*=.*|size = 15|}' \
            "$_alacritty_cfg"
    else
        printf '\n[font]\nnormal = { family = "Maple Mono NL NF CN" }\nsize = 15\n' \
            >>"$_alacritty_cfg"
    fi
    success "Alacritty font patched"
else
    warn "Alacritty config not found -- skipping font patch"
fi
unset _alacritty_cfg

success "Desktop config done"
