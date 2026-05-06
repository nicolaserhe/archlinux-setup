#!/usr/bin/env bash
# =============================================================================
# scripts/config/fcitx.sh -- Fcitx5 + 雾凇拼音
#
# 配置文件源：
#   config/fcitx5/classicui.conf           → ~/.config/fcitx5/conf/classicui.conf
#   config/fcitx5/profile                  → ~/.config/fcitx5/profile
#   config/fcitx5/rime/default.custom.yaml → <rime_dir>/default.custom.yaml
#
# 配色主题由 matugen.sh + dms-matugen-init.service 生成；
# theme.conf 变化时由 fcitx5-theme-reload.path 监视并触发 fcitx5 重启。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 校验 pacman 包已安装 -----------------------------------------------------
header "Fcitx5 packages (verify)"
for _pkg in fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool fcitx5-rime librime; do
    pacman -Qi "$_pkg" &>/dev/null \
        || die "Missing package: $_pkg -- run scripts/packages/pacman.sh first"
done
unset _pkg
success "Fcitx5 packages ready"

# -- Wayland 环境变量 ---------------------------------------------------------
# GTK4 走 Wayland text-input-v3，不再需要 GTK_IM_MODULE；
# GTK3 / Qt5 / X11 仍需要 QT_IM_MODULE / XMODIFIERS
header "Input method env vars"
mkdir -p "$HOME/.config/environment.d"
cat >"$HOME/.config/environment.d/fcitx.conf" <<'EOF'
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
success "Written: ~/.config/environment.d/fcitx.conf"

# -- Flatpak 全局 IM 环境变量 -------------------------------------------------
header "Fcitx5 Flatpak override"
if command_exists flatpak; then
    flatpak override --user \
        --env=QT_IM_MODULE=fcitx \
        --env=XMODIFIERS=@im=fcitx
    success "Flatpak global IM env vars set"
else
    warn "flatpak not found, skipping override"
fi

# matugen 首次运行时若 dms 主题目录不存在会 exit 1，提前创建保险
mkdir -p "$HOME/.local/share/fcitx5/themes/dms"
success "Created: fcitx5/themes/dms (matugen output dir)"

# -- 皮肤与 UI ----------------------------------------------------------------
header "Fcitx5 classicui"
copy_config \
    "$REPO_DIR/config/fcitx5/classicui.conf" \
    "$HOME/.config/fcitx5/conf/classicui.conf"

# -- Profile（预选 Rime）------------------------------------------------------
header "Fcitx5 profile"
copy_config \
    "$REPO_DIR/config/fcitx5/profile" \
    "$HOME/.config/fcitx5/profile"

# -- fcitx5 systemd user service ---------------------------------------------
# niri-session 走 systemd 而不处理 ~/.config/autostart/，所以必须用
# systemd user service 拉起 fcitx5
header "Fcitx5 systemd user service"
mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/fcitx5.service" <<'EOF'
[Unit]
Description=Fcitx5 Input Method
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/fcitx5 --replace --verbose "*"=0
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
success "Written: fcitx5.service"
enable_user_service fcitx5.service

# -- 主题热重载（path unit）---------------------------------------------------
# DMS 换壁纸后 matugen 重新生成 theme.conf，但 fcitx5 不会主动感知变化；
# 用 path unit 监视 theme.conf，文件变化时触发 oneshot service 重启 fcitx5
header "Fcitx5 theme hot-reload (path unit)"
_theme_conf="$HOME/.local/share/fcitx5/themes/dms/theme.conf"

cat >"$HOME/.config/systemd/user/fcitx5-theme-reload.path" <<EOF
[Unit]
Description=Watch fcitx5 DMS theme.conf for matugen changes

[Path]
PathModified=${_theme_conf}
Unit=fcitx5-theme-reload.service

[Install]
WantedBy=graphical-session.target
EOF
success "Written: fcitx5-theme-reload.path"

cat >"$HOME/.config/systemd/user/fcitx5-theme-reload.service" <<'EOF'
[Unit]
Description=Reload fcitx5 after DMS matugen theme update

[Service]
Type=oneshot
# matugen 写文件不是原子的；等 1 秒避免读到半截
ExecStartPre=/bin/sleep 1
ExecStart=/usr/bin/systemctl --user restart fcitx5.service
EOF
success "Written: fcitx5-theme-reload.service"

# .path 文件刚写入，systemctl --user enable 可能因 daemon 未 reload 失败，
# 直接创建 .wants/ 软链最可靠
add_user_service_wants fcitx5-theme-reload.path graphical-session.target
unset _theme_conf

# -- 雾凇拼音 -----------------------------------------------------------------
header "rime-ice"
RIME_DIR="$HOME/.local/share/fcitx5/rime"

(
    set -euo pipefail
    tmp="$(mktemp -d /tmp/rime-ice.XXXXXX)"
    trap 'rm -rf "$tmp"' EXIT

    git_clone "$tmp/rime-ice" https://github.com/iDvel/rime-ice

    rm -rf "$RIME_DIR"
    mkdir -p "$RIME_DIR"
    cp -r "$tmp/rime-ice/." "$RIME_DIR/"
)
success "rime-ice deployed: $RIME_DIR"

header "Rime custom config"
copy_config \
    "$REPO_DIR/config/fcitx5/rime/default.custom.yaml" \
    "$RIME_DIR/default.custom.yaml"

# -- 预编译词库 ---------------------------------------------------------------
header "Rime dictionary build"
if command_exists rime_deployer; then
    info "Building dictionary, please wait..."
    if rime_deployer --build "$RIME_DIR"; then
        success "Dictionary built"
    else
        warn "rime_deployer returned non-zero -- fcitx5 will retry on first launch"
    fi
else
    warn "rime_deployer not found -- dictionary will be built on first fcitx5 launch"
fi

success "Fcitx5 config done"
