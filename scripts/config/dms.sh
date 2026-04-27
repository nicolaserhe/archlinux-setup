#!/usr/bin/env bash
# =============================================================================
# scripts/config/dms.sh -- DankMaterialShell 配置
#
# 资源文件位置（均在 repo 根目录）：
#   config/dms/settings.json     → 通过 python merge 写入 DMS 完整 settings.json
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
# 1. DMS stub kdl 文件（niri dms/colors.kdl 等）
# =============================================================================
header "DMS stub files"
mkdir -p "$HOME/.config/niri/dms"
for _kdl in colors layout alttab binds; do
    if [[ ! -f "$HOME/.config/niri/dms/$_kdl.kdl" ]]; then
        touch "$HOME/.config/niri/dms/$_kdl.kdl"
        success "Created stub: dms/$_kdl.kdl"
    else
        warn "Already exists, skipping: dms/$_kdl.kdl"
    fi
done
unset _kdl

# =============================================================================
# 2. dms setup
# =============================================================================
header "DMS setup"
if command -v dms &>/dev/null; then

    # 配置你想选的菜单项内容（忽略大小写）
    declare -A choices
    choices["privilege"]="sudo" # 多个特权工具选择
    choices["compositor"]="Niri"
    choices["terminal"]="Alacritty"
    choices["systemd"]="Yes"
    choices["deploy"]="y" # y/n 确认

    # 调用 expect
    expect <<'EOF'
spawn dms setup

# 获取外部 Bash choices
array set choices [list \
    privilege "sudo" \
    compositor "Niri" \
    terminal "Alacritty" \
    systemd "Yes" \
    deploy "y" \
]

# 函数：根据选项名匹配编号并返回
proc select_by_name {name} {
    set buffer $expect_out(buffer)
    if {[regexp -nocase {([0-9]+)\)\s*${name}} $buffer -> choice]} {
        return $choice
    } else {
        return ""
    }
}

# 无限循环处理所有菜单，直到 expect eof
while {1} {

    expect {
        eof { break }  ;# 脚本结束
        -re {Choose one.*\[.*\]} {
            # 多个特权工具选择
            set target $choices(privilege)
            set choice [select_by_name $target]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Select compositor:} {
            set target $choices(compositor)
            set choice [select_by_name $target]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Select terminal:} {
            set target $choices(terminal)
            set choice [select_by_name $target]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Use systemd.*} {
            set target $choices(systemd)
            set choice [select_by_name $target]
            if {$choice ne ""} { send "$choice\r" }
        }
        -re {Proceed with deployment\?.*} {
            send "$choices(deploy)\r"
        }
    }
}
expect eof
EOF

    # 检查 expect 返回值
    if [ $? -eq 0 ]; then
        success "dms setup completed"
    else
        warn "dms setup returned a non-zero value -- please log in for the first time and check manually"
    fi

else
    warn "dms command not found -- skipping dms setup, please install and run it manually"
fi

# =============================================================================
# 3. DMS settings.json
#
#    dms setup 已生成含完整字段的 settings.json。
#    直接覆盖会丢失 DMS 自身的其他字段，导致 DMS 行为异常。
#    用 python 将 config/dms/settings.json 中的少量自定义值 merge 进去，
#    其余字段保持 DMS 生成的默认值不变。
#    若 dms setup 未能生成文件（首次安装 dms 未就绪），则直接复制作为兜底。
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
# 仅删除注释字段，其余原样保留再覆盖自定义值
overrides.pop("__doc__", None)
data.update(overrides)
with open(dest_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PYEOF
    success "DMS settings merged: $_dms_settings"
else
    # dms setup 未生成文件（dms 尚未安装或 setup 失败），直接复制作为兜底
    copy_config \
        "$REPO_DIR/config/dms/settings.json" \
        "$_dms_settings"
    warn "DMS settings copied as-is (dms setup may not have run yet)"
fi
unset _dms_settings

# =============================================================================
# 4. DMS environment variables
#    source: config/dms/environment.conf
#    dest:   ~/.config/environment.d/90-dms.conf
#
#    按 DMS 官方推荐放在 environment.d，由 systemd 在所有用户会话中加载。
#    修改后需注销重登才生效。
# =============================================================================
header "DMS environment (90-dms.conf)"
mkdir -p "$HOME/.config/environment.d"
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

_DMS_INCLUDES='include "dms/colors.kdl"
include "dms/layout.kdl"
include "dms/alttab.kdl"
include "dms/binds.kdl"'

if grep -qF 'include "dms/colors.kdl"' "$_niri_cfg"; then
    warn "niri: DMS include directive already exists, skipping"
else
    printf '\n// DMS configuration file inclusion\n%s\n' "$_DMS_INCLUDES" >>"$_niri_cfg"
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

unset _niri_cfg _DMS_INCLUDES

# =============================================================================
# 6. 绑定 dms.service 到 niri.service
# =============================================================================
header "DMS service binding"
ensure_xdg_runtime_dir
if systemctl --user add-wants niri.service dms 2>/dev/null; then
    success "DMS has been bound to niri.service via systemd wants"
else
    warn "systemctl --user add-wants failed -- please run manually:"
    warn "  systemctl --user add-wants niri.service dms"
fi

# =============================================================================
# 7. 壁纸
#    source: assets/wallpaper.{jpg,jpeg,png,webp}（取第一个）
#    dest:   ~/.local/share/wallpapers/
# =============================================================================
header "DMS wallpaper + matugen"

_find_asset() {
    local dir="$1" pattern="$2"
    find "$dir" -maxdepth 1 \( \
        -iname "*.jpg" -o -iname "*.jpeg" \
        -o -iname "*.png" -o -iname "*.webp" \
        \) -name "$pattern" 2>/dev/null | sort | head -1
}

_dms_wallpaper=""
if [[ -n "${WALLPAPER:-}" && -f "$WALLPAPER" ]]; then
    _dms_wallpaper="$WALLPAPER"
    info "Wallpaper from WALLPAPER env: $_dms_wallpaper"
else
    _dms_wallpaper="$(_find_asset "$REPO_DIR/assets" "wallpaper.*")"
fi

_wallpaper_dest=""
if [[ -z "$_dms_wallpaper" ]]; then
    die "Wallpaper not found -- add assets/wallpaper.jpg (or .png) to the repo"
else
    mkdir -p "$HOME/.local/share/wallpapers"
    _wallpaper_dest="$HOME/.local/share/wallpapers/$(basename "$_dms_wallpaper")"
    cp "$_dms_wallpaper" "$_wallpaper_dest"
    success "Wallpaper copied: $_wallpaper_dest"

    mkdir -p "$HOME/.local/state/DankMaterialShell"
    cat >"$HOME/.local/state/DankMaterialShell/session.json" <<EOF
{
  "wallpaperPath": "${_wallpaper_dest}",
  "wallpaperFillMode": "PreserveAspectCrop"
}
EOF
    success "Written: DMS session.json (wallpaper: $_wallpaper_dest)"

    # matugen one-shot 服务（首次 niri 登录后自动运行，然后自我禁用）
    # ExecStartPre：在 matugen 运行前创建 fcitx5 主题目录。
    # ExecStartPost(1)：重启 fcitx5 使新生成的 theme.conf 立即生效。
    #   前缀 `-` 表示忽略失败（fcitx5 未运行时不影响后续步骤）。
    # ExecStartPost(2)：服务自我禁用，避免重复执行。
    if command -v dms &>/dev/null; then
        mkdir -p "$HOME/.config/systemd/user"
        cat >"$HOME/.config/systemd/user/dms-matugen-init.service" <<EOF
[Unit]
Description=DMS matugen initial color scheme generation
After=graphical-session.target dms.service
Wants=dms.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/mkdir -p %h/.local/share/fcitx5/themes/dms
# BUG FIX: dms matugen generate 需要 --state-dir，否则报错 "state-dir is required"
# 用 systemd specifier %h 展开 home 目录，避免硬编码路径
ExecStart=/usr/bin/dms matugen generate --state-dir %h/.local/state/DankMaterialShell --value ${_wallpaper_dest}
ExecStartPost=-/usr/bin/systemctl --user restart fcitx5.service
ExecStartPost=/usr/bin/systemctl --user disable dms-matugen-init.service
RemainAfterExit=no

[Install]
WantedBy=graphical-session.target
EOF
        _wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
        mkdir -p "$_wants_dir"
        ln -sf "$HOME/.config/systemd/user/dms-matugen-init.service" \
            "$_wants_dir/dms-matugen-init.service"
        success "DMS matugen will run automatically on first niri login"
        unset _wants_dir
    else
        warn "dms not found -- skipping matugen service"
    fi
fi

# =============================================================================
# 8. 头像
#    source: assets/avatar.{png,jpg,jpeg,gif,webp}
#    dest:   ~/.local/share/avatars/ + AccountsService
# =============================================================================
header "DMS profile picture"

_avatar_src="$(_find_asset "$REPO_DIR/assets" "avatar.*")"

_avatar_dest=""
if [[ -z "$_avatar_src" ]]; then
    die "Avatar not found -- add assets/avatar.png (or .jpg) to the repo"
else
    mkdir -p "$HOME/.local/share/avatars"
    _avatar_dest="$HOME/.local/share/avatars/$(basename "$_avatar_src")"
    cp "$_avatar_src" "$_avatar_dest"
    success "Avatar copied: $_avatar_dest"

    # AccountsService 注册（DMS 从这里读取头像路径）
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
fi

# =============================================================================
# 9. dms-initial-settings：首次登录用 IPC 刷新头像显示
# =============================================================================
header "DMS initial settings IPC service"
if [[ -n "$_avatar_dest" ]]; then
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
    _wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
    mkdir -p "$_wants_dir"
    ln -sf "$HOME/.config/systemd/user/dms-initial-settings.service" \
        "$_wants_dir/dms-initial-settings.service"
    success "DMS profile IPC refresh scheduled for first niri login"
    unset _wants_dir
else
    warn "No avatar -- skipping dms-initial-settings.service"
fi

unset _dms_wallpaper _avatar_src _avatar_dest _wallpaper_dest
success "DMS config done"

# 注意：~/.local/share/fcitx5/themes/dms/ 目录由 fcitx.sh 在安装阶段创建。
# fcitx5 不会因为主题目录存在但 theme.conf 缺失而崩溃，只会 fallback 到默认主题。
# dms-matugen-init.service 的 ExecStartPre 保留为幂等保险。
