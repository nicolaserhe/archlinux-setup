#!/usr/bin/env bash
# =============================================================================
# scripts/core/fcitx.sh -- Fcitx5 + 雾凇拼音
#
# 配置文件源：
#   config/fcitx5/classicui.conf              → ~/.config/fcitx5/conf/classicui.conf
#   config/fcitx5/profile                     → ~/.config/fcitx5/profile
#   config/fcitx5/rime/default.custom.yaml    → <rime_dir>/default.custom.yaml
#   config/autostart/org.fcitx.Fcitx5.desktop → ~/.config/autostart/（屏蔽 XDG autostart）
#
# 配色主题由 matugen 模板生成（输出到 themes/Matugen/）。
# theme.conf 变化时由 fcitx5-theme-reload.path 监视并通过 systemd try-restart fcitx5
# （DMS 模板自带的 post_hook 用 `fcitx5 -r` 会脱离 systemd 跟踪，故走 path unit）。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# fcitx5:            新一代输入法框架
# fcitx5-gtk:        GTK 2/3/4 输入法模块
# fcitx5-qt:         Qt 5/6 输入法模块
# fcitx5-configtool: Fcitx5 图形配置工具
# fcitx5-rime:       RIME 输入法引擎前端（中州韵）
# librime:           RIME 输入法引擎核心库
header "fcitx5 packages"
pacman_install \
    fcitx5 \
    fcitx5-gtk \
    fcitx5-qt \
    fcitx5-configtool \
    fcitx5-rime \
    librime

# -- Wayland 环境变量 ---------------------------------------------------------
# GTK4 / Qt6.8.2+ 都能走 Wayland text-input-v3，所以不设 GTK_IM_MODULE（上游
# fcitx5 wiki 明确写 "Do NOT set GTK_IM_MODULE"，设了反而会把 Gtk2 也带歪）；
# GTK3 / Qt5 / X11（含 XWayland）仍需要 QT_IM_MODULE / XMODIFIERS。
#
# 三个变量各自的角色（https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland）：
#   QT_IM_MODULE=fcitx   Qt5 必需 —— 非 KWin 的合成器没有 Qt5 要的 text-input-v2/v4。
#   QT_IM_MODULES        Qt 6.7+ 才认，给的是"候选顺序"：先试合成器的 wayland
#                        路径（text-input-v3，Qt 6.8.2 起完善），不行退到 fcitx
#                        自带的 im module。上游在 GNOME / Sway 一段给的正是
#                        `QT_IM_MODULES="wayland;fcitx"`，niri 同属"非 KWin"这一类。
#                        它是**回退列表**，所以最坏情况等于现在的行为。
#   XMODIFIERS          XWayland / X11 应用用。
# 改这里要重新登录才生效（environment.d 由 systemd user manager 在会话建立时读）。
header "Input method env vars"
mkdir -p "$HOME/.config/environment.d"
cat >"$HOME/.config/environment.d/fcitx.conf" <<'EOF'
QT_IM_MODULE=fcitx
QT_IM_MODULES=wayland;fcitx
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

# -- 皮肤与 UI ----------------------------------------------------------------
header "Fcitx5 classicui"
copy_config \
    "$REPO_DIR/config/fcitx5/classicui.conf" \
    "$HOME/.config/fcitx5/conf/classicui.conf"

# -- Profile（预选 Rime）------------------------------------------------------
# profile 由 fcitx5 自己写：用户换输入法、调顺序，fcitx5 立刻把整个文件按自己的
# 格式重写一遍（连注释都补上）。我们这份只是"全新机器上预选 Rime"的种子，
# 播种之后归 fcitx5 所有 —— 覆盖它等于每次重跑 install 都把用户的输入法顺序
# 重置回仓库版本。
header "Fcitx5 profile (seed once)"
copy_config_seed \
    "$REPO_DIR/config/fcitx5/profile" \
    "$HOME/.config/fcitx5/profile"

# -- 自定义 rime 状态图标 -----------------------------------------------------
# fcitx5 实际请求的图标名是 org.fcitx.Fcitx5.fcitx_rime_*.svg（完整前缀），
# fcitx_rime_*.svg 只是系统里指向它的软链接。必须同时部署两种名字才能覆盖。
header "Fcitx5 custom rime icons"
_icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$_icon_dir"
for _svg in "$REPO_DIR/assets/icons/"fcitx_rime_*.svg; do
    [[ -f "$_svg" ]] || continue
    _base="$(basename "$_svg")"
    cp "$_svg" "$_icon_dir/$_base"
    cp "$_svg" "$_icon_dir/org.fcitx.Fcitx5.$_base"
    success "Deployed icon: $_base + org.fcitx.Fcitx5.$_base"
done
# 更新 hicolor 图标缓存，否则 GTK 托盘不会识别新图标。
# 用户级 hicolor 默认没有 index.theme；不写就让 gtk-update-icon-cache 加 -t
# (--ignore-theme-index)，但 -t 会生成空 cache（只有 header），GTK 优先读 cache
# 找不到任何图标 → 托盘图标完全显示不出来。所以补一份最小 index.theme，
# 让 gtk-update-icon-cache 正常生成完整的 cache。
_hicolor_root="$_icon_dir/../../.."
if [[ ! -f "$_hicolor_root/index.theme" ]]; then
    cat >"$_hicolor_root/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme (user)
Hidden=true
Directories=scalable/apps

[scalable/apps]
Size=128
MinSize=8
MaxSize=512
Type=Scalable
EOF
    success "Wrote user-level hicolor index.theme"
fi
gtk-update-icon-cache -f "$_hicolor_root"
success "Icon cache updated"
unset _svg _base _icon_dir _hicolor_root

# -- fcitx5 systemd user service ---------------------------------------------
# 用 systemd user service 拉起 fcitx5（而非依赖 XDG autostart）：这样 fcitx5 受
# systemd 跟踪，theme-reload 才能用 systemctl --user 管它。
#
# 注意 niri 并不"不处理 autostart" —— niri.service 带
# `Wants=xdg-desktop-autostart.target`，systemd 的 xdg-autostart-generator 仍会从
# /etc/xdg/autostart/org.fcitx.Fcitx5.desktop 生成 app-org.fcitx.Fcitx5@autostart.service
# （ExecStart=:/usr/bin/fcitx5，PartOf=graphical-session.target）。
# 两个实例同时起，撞上 --replace 会互相 SIGTERM；会话重启时演变成 restart 风暴，
# 最后 unit 停在 inactive，而 on-failure 不覆盖干净退出 → 输入法彻底消失。
# 所以下面额外部署一份 Hidden=true 的用户级覆盖把 autostart 那条屏蔽掉。
header "Fcitx5 systemd user service"
write_user_unit fcitx5.service <<'EOF'
[Unit]
Description=Fcitx5 Input Method
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
# default=3：留 Warn/Error。原来写 "*"=0 把日志全关了，主实例在 journal 里
# 一行都没有，故障时无从排查。（"*" 与 default 是同一个槽位，后写的赢，
# 所以 "*=0,default=3" 与 "default=3" 等价 —— 直接写 default=3。）
ExecStart=/usr/bin/fcitx5 --replace --verbose "default=3"
# always（不是 on-failure）：被 SIGTERM 或干净退出后也要拉回来。
# on-failure 只覆盖非零退出，正是上次"unit 停在 inactive 不再重启"的原因。
# 副作用：托盘/`fcitx5-remote -e` 主动退出也会在 3s 后被拉回 —— 想真停就用
# `systemctl --user stop fcitx5.service`（systemd 发起的 stop 不触发 Restart）。
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
enable_user_service fcitx5.service

# enable_user_service 失败（无 systemd user session）时只 warn、不建 wants 链。
# 而 XDG autostart 这条兜底即将被下面屏蔽 —— 屏蔽后就只剩这一条启动路径了，
# 所以照 path unit 的做法补一次软链，避免"enable 失败 = 输入法永不启动"。
add_user_service_wants fcitx5.service graphical-session.target

# -- 屏蔽 XDG autostart 的重复拉起 --------------------------------------------
# 用户级 autostart 文件按 basename 覆盖系统级，Hidden=true 让 generator 直接跳过。
# 改完要 daemon-reload，否则 generator 仍用着旧快照。
header "Suppress duplicate XDG autostart entry"
copy_config \
    "$REPO_DIR/config/autostart/org.fcitx.Fcitx5.desktop" \
    "$HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
systemctl --user daemon-reload || warn "daemon-reload failed; re-login to apply"

# -- 主题热重载（path unit）---------------------------------------------------
# DMS 换壁纸后 matugen 重新生成 theme.conf，但 fcitx5 不会主动感知变化；
# 用 path unit 监视 theme.conf，文件变化时触发 oneshot service 重启 fcitx5
header "Fcitx5 theme hot-reload (path unit)"
_theme_conf="$HOME/.local/share/fcitx5/themes/Matugen/theme.conf"

write_user_unit fcitx5-theme-reload.path <<EOF
[Unit]
Description=Watch fcitx5 DMS theme.conf for matugen changes

[Path]
PathModified=${_theme_conf}
Unit=fcitx5-theme-reload.service

[Install]
WantedBy=graphical-session.target
EOF

write_user_unit fcitx5-theme-reload.service <<'EOF'
[Unit]
Description=Reload fcitx5 after DMS matugen theme update

[Service]
Type=oneshot
# matugen 写文件不是原子的；等 1 秒避免读到半截
ExecStartPre=/bin/sleep 1
# try-restart（不是 restart）：unit 没在跑（inactive/failed）时就什么都不做。
# 这样主题变更不会把一个本不该在跑的 fcitx5 提前拉起来 —— 它下次正常启动时
# 本来就会读到新的 theme.conf。
# 注意：try-restart 对 active 或 activating 的 unit 都会真的重启，所以它**不**
# 能防止 matugen 连写多次 theme.conf 带来的反复重启；那由上面的 sleep 1 吸收。
ExecStart=/usr/bin/systemctl --user try-restart fcitx5.service
EOF

# .path 文件刚写入，systemctl --user enable 可能因 daemon 未 reload 失败，
# 直接创建 .wants/ 软链最可靠
add_user_service_wants fcitx5-theme-reload.path graphical-session.target
unset _theme_conf

# -- 雾凇拼音 -----------------------------------------------------------------
# 装 archlinuxcn 的包（pkgbase `rime-ice-git` 的 split package），不从 GitHub
# clone。上游 README 那套是给手工装的，搬进自动化安装会带出一串问题：词库得从
# /tmp 拷进用户目录、重跑一次那句 `rm -rf` 就把用户词频（`*.userdb`）清光、
# 更新只能靠自建 timer 里一句 `git pull`。包管理版把词库装进 /usr/share/rime-data
# （rime 的 shared data dir，fcitx5-rime 从这里读），用户目录只剩用户自己的东西
# —— 三件事一起消失：升级交给 pacman，用户数据没人碰，timer 退休。
#
# 变体必须和下面 default.custom.yaml 的 schema_list 对上（flypy = 小鹤双拼）；
# 各变体包互相 conflicts，装错变体得先卸。
header "rime-ice"
pacman_install rime-ice-double-pinyin-flypy-git
success "rime-ice installed: /usr/share/rime-data"

header "Rime custom config"
# 目标路径写全而不复用变量：漂移检查（just drift）靠调用点的字面量
# 得出"部署到哪"，变量形式它解析不了。
copy_config \
    "$REPO_DIR/config/fcitx5/rime/default.custom.yaml" \
    "$HOME/.local/share/fcitx5/rime/default.custom.yaml"

# 词库编译：上游包已在 /usr/share/rime-data/build/ 带好预编译 .bin，用户目录
# 那份由 fcitx5 首次启动自己 deploy（只编译用户词典，很快）。install 阶段再跑
# 一遍 rime_deployer 只是把同样的活干两次。

success "fcitx5 done"
