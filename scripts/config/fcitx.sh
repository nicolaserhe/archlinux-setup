#!/usr/bin/env bash
# =============================================================================
# scripts/config/fcitx.sh -- Fcitx5 + 雾凇拼音配置
#
# 配置文件源：
#   config/fcitx5/classicui.conf           → ~/.config/fcitx5/conf/classicui.conf
#   config/fcitx5/profile                  → ~/.config/fcitx5/profile
#   config/fcitx5/rime/default.custom.yaml → <rime_dir>/default.custom.yaml
#
# 配色主题由 matugen.sh + dms-matugen-init.service 负责生成。
# 动态热重载由 fcitx5-theme-reload.path 监视 theme.conf 变化后自动重启 fcitx5。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 校验 pacman 包已安装 -----------------------------------------------------
header "Fcitx5 packages (verify)"
for pkg in fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool fcitx5-rime librime; do
    pacman -Qi "$pkg" &>/dev/null ||
        die "Missing package: $pkg -- run scripts/packages/pacman.sh first"
done
success "Fcitx5 packages ready"

# -- Wayland 环境变量 ---------------------------------------------------------
# GTK_IM_MODULE 在 GTK4 下已废弃，GTK4 走 Wayland text-input-v3 协议，不需要此变量。
# GTK3 / Qt5 / X11 应用仍需要下列变量。
header "Input method env vars"
mkdir -p "$HOME/.config/environment.d"
cat >"$HOME/.config/environment.d/fcitx.conf" <<'EOF'
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
success "Written: ~/.config/environment.d/fcitx.conf"

# -- Flatpak 全局 IM 环境变量 -------------------------------------------------
header "Fcitx5 Flatpak override"
if command -v flatpak &>/dev/null; then
    flatpak override --user \
        --env=QT_IM_MODULE=fcitx \
        --env=XMODIFIERS=@im=fcitx
    success "Flatpak global IM env vars set"
else
    warn "flatpak not found, skipping override"
fi

# -- 提前创建 fcitx5 dms 主题目录（避免 matugen 首次运行时因目录不存在而 exit 1）
mkdir -p "$HOME/.local/share/fcitx5/themes/dms"
success "Created: fcitx5/themes/dms (matugen output dir)"

# -- 皮肤与 UI ----------------------------------------------------------------
header "Fcitx5 classicui"
mkdir -p "$HOME/.config/fcitx5/conf"
copy_config \
    "$REPO_DIR/config/fcitx5/classicui.conf" \
    "$HOME/.config/fcitx5/conf/classicui.conf"

# -- Profile（预选 Rime）------------------------------------------------------
header "Fcitx5 profile"
copy_config \
    "$REPO_DIR/config/fcitx5/profile" \
    "$HOME/.config/fcitx5/profile"

# -- Systemd user service -----------------------------------------------------
# niri-session 走 systemd，不处理 XDG autostart（~/.config/autostart/），
# 必须用 systemd user service 来拉起 fcitx5。
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

# -- BUG FIX: 动态主题热重载 --------------------------------------------------
# 问题：dms-matugen-init.service 在首次登录时重启了 fcitx5，但此后每次换壁纸
#       DMS 重新生成 theme.conf 后，fcitx5 不会自动感知文件变化、不会热重载。
# 修复：用 systemd path unit 监视 theme.conf，文件有变化时触发 oneshot service
#       重启 fcitx5，使新配色立即生效。
header "Fcitx5 theme hot-reload (path unit)"
_fcitx_theme_conf="$HOME/.local/share/fcitx5/themes/dms/theme.conf"

cat >"$HOME/.config/systemd/user/fcitx5-theme-reload.path" <<EOF
[Unit]
Description=Watch fcitx5 DMS theme.conf for matugen changes

[Path]
PathModified=${_fcitx_theme_conf}
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
# 稍等 1 秒确保 matugen 已完整写入 theme.conf
ExecStartPre=/bin/sleep 1
ExecStart=/usr/bin/systemctl --user restart fcitx5.service
EOF
success "Written: fcitx5-theme-reload.service"

# 使用 add_user_service_wants 而非 enable_user_service：
# path unit 的 .path 文件刚由本脚本写入，enable_user_service 调用 systemctl --user enable
# 可能因 daemon 未 reload 而找不到 unit；直接创建 .wants/ symlink 更可靠。
_wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
mkdir -p "$_wants_dir"
ln -sf "$HOME/.config/systemd/user/fcitx5-theme-reload.path" \
    "$_wants_dir/fcitx5-theme-reload.path"
success "Linked: fcitx5-theme-reload.path -> graphical-session.target.wants/"
unset _fcitx_theme_conf _wants_dir

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

# -- default.custom.yaml ------------------------------------------------------
header "Rime custom config"
copy_config \
    "$REPO_DIR/config/fcitx5/rime/default.custom.yaml" \
    "$RIME_DIR/default.custom.yaml"

# -- 预编译词库 ---------------------------------------------------------------
header "Rime dictionary build"
if command_exists rime_deployer; then
    info "Building dictionary, please wait..."
    rime_deployer --build "$RIME_DIR" &&
        success "Dictionary built" ||
        warn "rime_deployer returned non-zero -- fcitx5 will retry on first launch"
else
    warn "rime_deployer not found -- dictionary will be built on first fcitx5 launch"
fi

success "Fcitx5 config done"
