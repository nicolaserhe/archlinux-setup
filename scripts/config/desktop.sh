#!/usr/bin/env bash
# =============================================================================
# scripts/config/desktop.sh -- Starship / Alacritty / Kanata / greetd / Bluetooth / PipeWire
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

# -- Starship -----------------------------------------------------------------
header "Starship"
copy_config "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"

# -- Alacritty ----------------------------------------------------------------
header "Alacritty"
copy_config "$REPO_DIR/config/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

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

systemctl --user daemon-reload 2>/dev/null || true
enable_user_service kanata.service

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
# 使用 greetd + tuigreet 替代 GDM，完全隔离 GNOME 组件。
# greetd 不会自动拉入 gnome-shell，是 niri 的推荐登录管理器。
header "greetd"

sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
# niri-session 由 niri 包提供，负责启动合成器并正确导出 WAYLAND_DISPLAY 等变量
command = "tuigreet --cmd niri-session --time --remember --asterisks"
user = "greeter"
EOF
success "Written: /etc/greetd/config.toml"

switch_display_manager greetd.service

# -- Bluetooth ----------------------------------------------------------------
header "Bluetooth"
enable_system_service bluetooth.service

# -- PipeWire -----------------------------------------------------------------
header "PipeWire"
for _svc in pipewire pipewire-pulse wireplumber; do
    enable_user_service "$_svc.service"
done
unset _svc

success "Desktop config done"
