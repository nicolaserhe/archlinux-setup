# DMS (DankMaterialShell) quirks

Go backend (`/usr/sbin/dms`) + Quickshell frontend (`/usr/share/quickshell/dms`)，Unix socket 通信。上游文档：https://danklinux.com/docs/dankmaterialshell。

## Key commands

| Command | Purpose |
|---|---|
| `dms setup` | 生成初始 `~/.config/matugen/config.toml`。交互菜单 —— `dms.sh` 用 `expect` 驱动（见 `scripts/core/helpers/dms-setup.exp`） |
| `dms ipc <target> <fn> [args]` | Runtime 控制。**不要用 `dms ipc call ...`** —— v1.4.6+ 拒绝（`Target not found`） |
| `dms matugen generate --shell-dir /usr/share/quickshell/dms --state-dir <state> --config-dir <config> --value <wallpaper>` | 同步 matugen 运行。**v1.4.6+ `--shell-dir` 和 `--config-dir` 都必填**。wallpaper path 必须用 `~/.local/share/wallpapers/` —— `dms ipc profile getImage` 返回的是头像不是壁纸，会出错色 |
| `dms screenshot` | Wayland 截图（依赖 `grim`+`slurp`） |

## Provides / does NOT provide

- **Provides**：notifications · system tray · screenshot · GTK CSS auto-gen（`gtkThemingEnabled=true` 时） · accent-color writeback to `gsettings org.gnome.desktop.interface accent-color`（换壁纸时）
- **Does NOT provide**：file manager（nautilus）· image viewer（loupe）· video player（celluloid）· calculator（gnome-calculator）· disk utility（gnome-disk-utility）· screen recorder（gpu-screen-recorder）· KDE Connect frontend（DankKDEConnect plugin via `kdeconnect.sh`）· night light（gammastep）· polkit agent（polkit-gnome）

## Path conventions

| Purpose | Path |
|---|---|
| DMS settings | `~/.config/DankMaterialShell/settings.json` |
| DMS state | `~/.local/state/DankMaterialShell/` —— 壁纸图像本体在 `~/.local/share/wallpapers/` |
| DMS plugins | `~/.config/DankMaterialShell/plugins/` |
| matugen config | `~/.config/matugen/config.toml`（由 `dms setup` 创建） |
| matugen templates | `~/.config/matugen/templates/*.tera` ← `config/matugen/templates/` |
| fcitx5 theme | `~/.local/share/fcitx5/themes/Matugen/theme.conf`（matugen 输出） |
| GTK dynamic colors | `~/.config/gtk-{3,4}.0/dank-colors.css`（DMS 自动生成） |

## First-login service order

```
graphical-session.target
  ├─ dms.service                  (user unit /usr/lib/systemd/user/dms.service,
  │                                Type=dbus, registers org.freedesktop.Notifications
  │                                on session bus)
  ├─ fcitx5.service               (ours)
  ├─ fcitx5-theme-reload.path     (ours, watches themes/Matugen/theme.conf)
  │                               → try-restart fcitx5.service
  ├─ app-org.kde.kdeconnect.daemon@autostart.service
  │                               (generated from /etc/xdg/autostart/, kdeconnectd)
  ├─ dms-initial-settings.service (ours, IPC writes — settings + profile)
  └─ dms-matugen-init.service     (ours, oneshot matugen,
                                   After=dms-initial-settings)
```

`app-org.fcitx.Fcitx5@autostart.service`（systemd 从 `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop` 生成，因为 `niri.service` 带 `Wants=xdg-desktop-autostart.target`）被 `~/.config/autostart/org.fcitx.Fcitx5.desktop` 的 `Hidden=true` 显式屏蔽 —— 否则它会和 `fcitx5.service` 同时拉起第二个实例（见 [input-and-fonts.md](input-and-fonts.md#fcitx5-重复拉起)）。

`keyd.service`（系统级，由 `keyd.sh` 启）独立启动早于任何 user session，TTY/greetd 阶段就有正确键位。

两个 `dms-*-init` service 在第一次成功后自我禁用；后续动态更新（换壁纸等）走 DMS 内部 matugen 调用，我们不控制。

## Quirks

### IPC

- **`dms ipc call ...` 已被 v1.4.6+ 移除**：用 `dms ipc <target> <fn>` 形式。
- **`dms ipc keybinds toggle` 要 provider arg**：`dms ipc keybinds toggle niri`。其他常用 target（`launcher`/`settings`/`notifications`）都不要 provider，`keybinds` 是例外。
- **`dms ipc audio increment/decrement` 要 step arg**：`dms ipc audio increment "5"`。binds.kdl 必须显式传 step。
- **`dms ipc brightness increment/decrement` 要 step + device**：`dms ipc brightness increment "5" "backlight:amdgpu_bl2"`，device 名机器相关。`config/helpers/dms/brightness`（部署到 `~/.local/bin/dms-brightness`）自动取第一个 backlight，binds.kdl 用 wrapper 保持硬件无关。
- **DMS IPC 不能设置深层嵌套 key**：`dms ipc settings set cursorSettings.niri.hideWhenTyping true` 返回 `SETTINGS_INVALID_KEY`。Workaround：直接编辑 `settings.json`，下次 DMS 启动生效。

### Settings / setup

- **`gtkThemingEnabled` 自重置**：在 `config/dms/settings.json` 里写 `"gtkThemingEnabled": true` 不能存活，DMS 启动时把它重置为 false。Workaround：DMS 跑起来后通过 IPC 写入，见 `dms-initial-settings.service`。
- **`dms setup` 不部署 template / config**：v1.4.6 已知问题，`config.toml` 引用的模板可能缺失 → matugen 静默跳过；`binds.kdl` 可能空文件 → niri 零 keybind。Fix：自己 ship 模板到 `config/matugen/templates/` + `_set_template` 强制覆写；ship `config/niri/dms/binds.kdl` 通过 `copy_config` 部署。绑定原则：shell 功能用 DMS IPC；窗口/工作区操作用 niri 原生 action；raw `spawn` 仅当两者都覆盖不了时用。所有 `hotkey-overlay-title` 英文。

### matugen / 主题色

- **`dms-matugen-init.service` 在"no changes"时退出码 2**：DMS 在 matugen 跑完但检测到颜色无变化时返回 exit code 2（`INVALIDARGUMENT`）。systemd 视为失败 → `ExecStartPost`（自我 disable）不跑 → 每次开机都重跑。Fix：service 单元加 `SuccessExitStatus=2`。
- **`starship.tera` 模板可能 stale**：`matugen.sh` 用 `copy_config` 部署模板，但 `matugen.sh` 不重跑时部署的模板停在旧版本。matugen 每次换壁纸都基于旧模板重渲染，覆盖任何手工编辑的 `~/.config/starship.toml`。Fix：`cp config/matugen/templates/starship.tera ~/.config/matugen/templates/starship.tera`，再 `matugen --prefer lightness image <wallpaper>`。
- **libadwaita 1.6+ accent**：GTK4 应用（Files/nautilus）从 gsettings 读 accent palette，不从 user `gtk.css` 的 `@define-color accent_*`。运行中应用不会 live 拾取 —— accent 改变需要 app 重启。By design，不是 bug。

### Niri 集成

- **niri config reload command**：`niri msg action load-config-file`（不是 `reload-config`，那个 subcommand 不存在）。

### Portals / screen sharing

- **Screen sharing 必须 `xdg-desktop-portal-wlr`**：`xdg-desktop-portal-gnome` 是为 GNOME session 设计的，不能在 niri 提供 ScreenCast。niri 实现了 `wlr-screencopy`，所以 wlr portal 必须与 gnome/gtk portals 并存。`config/dms/portals.conf` 把 `ScreenCast` 和 `Screenshot` 路由到 wlr，其他接口（FileChooser/Settings 等）留 gnome/gtk —— 两个 backend 共存无冲突。DMS 自己的 `dms screenshot` 绕过 portal（直接 grim+slurp）。
- **`xdg-desktop-portal-wlr` 需要 chooser config**：没有 `~/.config/xdg-desktop-portal-wlr/config`，portal 没法呈现 screen/output 选择器 → 会议软件里点 screen share 没反应。`config/dms/xdpw.conf` 配 `slurp -f %o -or` 作为 chooser。

### DankKDEConnect plugin

**后端选型：上游 KDE Connect（`kdeconnectd`），不用 Valent。** kdeconnect 在官方仓库、随 KDE Gear 稳定发版；Valent 是 AUR 的 alpha（`1.0.0.alpha.x`）。插件两种后端都支持（`services/KDEConnectService.qml` 与 `ValentService.qml` 并存），换后端不丢功能。启动走包自带的 `/etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop`，由 systemd 的 xdg-autostart-generator 生成受管 unit —— 不写 niri spawn-at-startup、不自建 unit，少一条拉起路径就少一个重复实例的来源。

- **Tile 显示"无设备"但详情面板有设备（stale ID 死锁）**：`~/.config/DankMaterialShell/plugin_settings.json` 的 `dankKDEConnect.selectedDeviceId` 存了陈旧 ID（重新配对设备 / 换后端实现 / 重装都会换新 ID）。插件里**没有任何路径会重置非空的失效 ID**，所以这确实是个死锁：
  - tile：`DankKDEConnect.qml:433` 的 `hasDevice` 要求 ID 同时出现在 `deviceIds` 里，失效即为 false，`:461` 于是返回 "No devices"。
  - 详情面板：`KDEConnectDetailContent.qml:62` 的 `effectiveDeviceId` 在 ID 不在列表里时回退到 `deviceIds[0]`，照常显示真实设备 —— 两个视图不一致的根源就在这里。
  - 这个属性只有两个写入点：`:500` 从设置读（**只判非空，不校验设备是否还在**）和 `:601` 的 `selectDevice()`（用户操作）。
  - 自动选择只发生在 `selectedDeviceId === ""` 时（`:153` 的 `onSelectedDeviceIdChanged`、`:354` 的 `Component.onCompleted`），陈旧但非空就永远轮不到它。

  **修法**：先试插件自带的 `Alt+1`（`:550` 起的 Repeater，最多到 `Alt+9`）—— 它调 `selectDevice(deviceIds[0])`，顺带把新 ID 写回 plugin_settings，等于就地修好持久化的陈旧值；代价是它属于 `Qt.WindowShortcut`，bar 或弹窗得有焦点。`Ctrl+Tab` / `Ctrl+Shift+Tab` 只在设备数 >1 时有用（`switchDeviceNext` 在 `ids.length <= 1` 时直接 return）。都不方便时再手改 JSON：`kdeconnect-cli -l --id-only` 拿实测 ID 写进 `plugin_settings.json`，重启 DMS —— 光重启 DMS 不够，`onDevicesListChanged` 的初始信号可能在 plugin 订阅前就发了。
- **同一个协议只能有一个守护进程**：KDE Connect 与 Valent 都实现协议，同时跑会抢 `org.kde.kdeconnect` 总线名并各自做一遍设备发现。后端只能选一个；`kdeconnect.sh` 会清掉 Valent 时代的残留（手工 mask、GCR SSH agent 环境变量、valent 专用 nautilus 扩展），并停掉还在跑的 valent 进程 —— 它不是 systemd unit，光卸包不会让它退出。另外它还会删用户级 `~/.config/autostart/org.kde.kdeconnect.daemon.desktop`：那份**不是** Valent 的，是旧版 kdeconnect 留下的陈旧拷贝，按 basename 遮蔽包自带的新版本（那份覆盖里带 `Hidden=true` 等禁用标记时不删，那是用户有意的选择）。

## Why no `dankinstall`

`dankinstall` 是 DMS 官方 one-shot 配置工具。我们跳过它因为它装 `mako`（与 DMS 通知 daemon 冲突）和 `xfce-polkit` —— 都不想要。代价：dankinstall 免费 ship 的产物（niri binds 等）我们自己 ship。
