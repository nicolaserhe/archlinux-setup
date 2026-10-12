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
#   config/niri/dms/windowrules.kdl → ~/.config/niri/dms/windowrules.kdl（仅首次播种）
#   assets/wallpaper.*           → ~/.local/share/wallpapers/
#   assets/avatar.*              → ~/.local/share/avatars/
#
# 参考文档：https://danklinux.com/docs/dankmaterialshell/
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- DMS 包安装 ---------------------------------------------------------------
# dms-shell: DankMaterialShell 主体（Go backend + 内嵌 Quickshell 前端）。
#            1.6 起 Quickshell UI 编进 /usr/bin/dms，运行时解包到
#            $XDG_RUNTIME_DIR/danklinux-shell/<hash>/；旧的 dms-shell-{niri,hyprland,bin}
#            split 包已被本包 Replaces 吸收，AUR 上现在只剩 dms-shell-git。
# matugen:   Material You 取色引擎（DMS 用它从壁纸生成主题色）
# 两个都在 extra —— 这一行不需要 AUR，也就不会成为 yay 不可用时的失败点。
header "DMS packages"
pacman_install dms-shell matugen

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

# windowrules.kdl 是 DMS 的窗口规则存储本体，不只是 niri 的 include 目标：
# DMS 启动时读它、追加自己的 @id 标记和内置规则（dms-floating-windows）后整体
# 重写。所以走 copy_config_seed —— 只在文件不存在时播种（给全新机器一条 PiP
# 浮动规则），已存在就不碰，否则重跑 install 会抹掉 DMS 的规则状态，下次 DMS
# 启动时把仓库规则当成新规则重新导入一遍。
header "DMS niri windowrules.kdl (seed once)"
copy_config_seed \
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
# 目标路径写全而不走中间变量：漂移检查（just drift）靠调用点的字面量得出
# "部署到哪"，变量形式它解析不了。
#
# config/dms/settings.json 里只放**非默认值**。DMS 落盘走 SettingsStore.toJson()，
# 里面 `if (Util.isDefault(value, SPEC[k].def)) continue` —— 等于 spec 默认值的键
# 它不写。声明成默认值的键因此会在 DMS 下次保存时消失，净效果为零；判断某个键是
# 不是默认值看 Common/settings/SettingsSpec.js 的 `def`。详见 docs/quirks/dms.md。
copy_config_merge \
    "$REPO_DIR/config/dms/settings.json" \
    "$HOME/.config/DankMaterialShell/settings.json"

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

# niri config 块追加；append_block_once（lib/fs.sh）以 marker 子串判断幂等。
# DMS include 段不用整块 append_block_once 是为了避免"看到 colors include 就
# 认为整块已写入"的脆弱假定（DMS 版本演进时增减 include，老 install 重跑要
# 能自动补齐缺失项）。注释头独立 marker，每个 include 各自检测，缺谁补谁。
#
# marker 的选择规则：**必须是我们自己块里独有的串**，最稳的是块首那行注释。
# 这里踩过：hotkey-overlay 段原先拿 'hotkey-overlay' 当 marker，而 niri 上游
# /usr/share/doc/niri/default-config.kdl 里那个词出现 6 次（`// skip-at-startup`
# 是注释掉的），于是任何还用着默认配置的机器上，这里都判定"已存在"→ 静默跳过
# 追加，配置永远不会生效，也不会有任何提示。下面四段的 marker 全部换成各自块首
# 的注释行（上游 config 里出现 0 次，只有我们写过才命中）。
append_block_once "$_niri_cfg" '// DMS configuration file inclusion' <<'NIRI_INC_HEADER'
// DMS configuration file inclusion
NIRI_INC_HEADER

for _inc in colors layout alttab binds windowrules; do
    if grep -qF "include \"dms/${_inc}.kdl\"" "$_niri_cfg"; then
        warn "Already present, skipping: dms/${_inc}.kdl include"
    else
        printf 'include "dms/%s.kdl"\n' "$_inc" >> "$_niri_cfg"
        success "Added niri include: dms/${_inc}.kdl"
    fi
done
unset _inc

append_block_once "$_niri_cfg" '// DMS: Make quickshell wallpaper show on the niri overview layer' <<'NIRI_LAYER'
// DMS: Make quickshell wallpaper show on the niri overview layer
layer-rule {
    match namespace="^quickshell$"
    place-within-backdrop true
}
NIRI_LAYER

append_block_once "$_niri_cfg" '// DMS / Wayland environment variables' <<'NIRI_ENV'
// DMS / Wayland environment variables
environment {
    XDG_CURRENT_DESKTOP "niri"
    QT_QPA_PLATFORM "wayland"
    ELECTRON_OZONE_PLATFORM_HINT "auto"
    QT_QPA_PLATFORMTHEME "gtk3"
    QT_QPA_PLATFORMTHEME_QT6 "gtk3"
}
NIRI_ENV

append_block_once "$_niri_cfg" '// 禁用开机自动弹出的快捷键说明浮层' <<'NIRI_HOTKEY'
// 禁用开机自动弹出的快捷键说明浮层
hotkey-overlay {
    skip-at-startup
}
NIRI_HOTKEY

# KDE Connect 不需要往 niri config 里写 spawn-at-startup：kdeconnectd 的启动走
# 包自带的 XDG autostart（见 kdeconnect.sh）。

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

# 不需要 matugen one-shot：DMS 启动时自己就从 session.json 的壁纸生成整套主题
# （journal: "Processing theme: image <wallpaper>" → "Running matugen image with
# dank16 injection"），换壁纸时再由它自己的 watcher 触发。fcitx5 重载另走
# fcitx5-theme-reload.path（fcitx.sh 创建）监视 theme.conf、
# systemctl --user try-restart fcitx5.service 触发。
# （不要再补一个 one-shot service 干这活：DMS 1.6 起纯冗余，理由见 docs/quirks/dms.md。）

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
# 不吞 sudo 错误：之前 2>/dev/null 让 sudo 失败时也走 else 分支，但用户看不到
# 真原因（无权限 / sudo 未配）。
if _as_root mkdir -p "$_acct_dir"; then
    if [[ -f "$_acct_file" ]]; then
        # 用 awk 全量重写而非 sed：路径含 `&` `\` 等特殊字符时 sed 转义复杂；
        # awk 通过 -v 传变量字面量化，无转义陷阱
        _as_root awk -v icon="$_avatar_dest" '
            BEGIN { handled = 0 }
            /^Icon=/  { print "Icon=" icon; handled = 1; next }
            /^\[User\]/ && !handled { print; print "Icon=" icon; handled = 1; next }
            { print }
            END { if (!handled) { print "[User]"; print "Icon=" icon } }
        ' "$_acct_file" | _as_root tee "$_acct_file.tmp" >/dev/null
        _as_root mv "$_acct_file.tmp" "$_acct_file"
    else
        printf '[User]\nIcon=%s\n' "$_avatar_dest" |
            _as_root tee "$_acct_file" >/dev/null
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
#
# 历史上这里还写过 `settings set gtkThemingEnabled true`（理由是该设置会被 DMS
# 启动时重置回 false）。DMS 1.6 已删掉这个设置 —— 二进制里 0 处引用，
# `dms ipc settings dump` 的 17 个键里也没有；GTK 取色改为原生生成
# ~/.config/gtk-{3,4}.0/dank-colors.css（每次登录重写）。留着不但多余，
# 还会让全新机器上的 unit 失败 —— IPC 写未知键报错 → ExecStartPost 不跑 →
# 每次登录重试一次。
# =============================================================================
header "DMS initial settings IPC service"
write_user_unit dms-initial-settings.service <<EOF
[Unit]
Description=DMS initial settings IPC writes (first login)
After=dms.service graphical-session.target

[Service]
Type=oneshot
# 不加 ExecStartPre=sleep：dms.service 是 Type=dbus，systemd 等到
# org.freedesktop.Notifications 在 session bus 注册才认为 ready；
# After=dms.service 已经保证 ipc 通道可用。
ExecStart=/usr/bin/dms ipc profile setImage "${_avatar_dest}"
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
# adw-gtk-theme 由 pacman-base.sh 安装，但 GTK 应用必须显式指定 adw-gtk3-dark
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

    # 预先创建 gtk.css -> dank-colors.css 软链；DMS 原生生成 dank-colors.css
    # 时会原地覆盖（幂等），覆盖前 GTK 应用已可加载动态配色
    ln -sf dank-colors.css "$_gtkd/gtk.css"
    success "Created symlink: $_gtkd/gtk.css -> dank-colors.css"
done
unset _gtkv _gtkd

success "DMS done"
