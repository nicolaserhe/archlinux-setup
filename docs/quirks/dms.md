# DMS (DankMaterialShell) quirks

Go backend + Quickshell frontend 合在同一个二进制 `/usr/bin/dms` 里（extra 的 `dms-shell` 包）。1.6 起 UI 编进二进制、运行时解包到 `$XDG_RUNTIME_DIR/danklinux-shell/<hash>/`，该路径写在 `$XDG_RUNTIME_DIR/danklinux.path`；`/usr/share/quickshell/dms` 这个旧路径已不存在 —— `pacman -Ql dms-shell` 里一个 QML 源文件都没有，只有 `/usr/bin/dms`、`/usr/lib/systemd/user/dms.service`、三个 `.desktop`、bash/fish/zsh 三套补全，以及 `/usr/share/doc/dms-shell/` 下的 README / IPC.md / 主题 JSON。Unix socket 通信。上游文档：https://danklinux.com/docs/dankmaterialshell。

`dms-shell-niri` / `-hyprland` / `-bin` 是 1.6 之前的 split 包，已被 `dms-shell` 用 `Replaces` 吸收；AUR 上现在只剩 `dms-shell-git`，`dms-shell-niri` 这个名字在 AUR 和 extra 里都不存在。

## Key commands

| Command | Purpose |
|---|---|
| `dms setup` | 生成初始 `~/.config/matugen/config.toml`。交互菜单 —— `dms.sh` 用 `expect` 驱动（见 `scripts/core/helpers/dms-setup.exp`） |
| `dms ipc [call] <target> <fn> [args]` | Runtime 控制。上游 IPC.md 的规范写法带 `call`，省略也照样生效（1.6.3 实测两种写法输出一致），仓库里的 binds.kdl 用的是省略形式 |
| `dms matugen generate --shell-dir "$(cat "$XDG_RUNTIME_DIR/danklinux.path")" --state-dir <state> --config-dir <config> --value <wallpaper>` | 同步 matugen 运行。**`--shell-dir` 必填，且只能从 `$XDG_RUNTIME_DIR/danklinux.path` 动态取**：`DMS_SHELL_DIR` 环境变量只喂全局的 `-c/--config`，喂不到它；`dms matugen queue` 走 socket 也照样要求显式传（传错/不传都是 `FATAL shell-dir is required`）。wallpaper path 必须用 `~/.local/share/wallpapers/` —— `dms ipc profile getImage` 返回的是头像不是壁纸，会出错色 |
| `dms screenshot` | Wayland 截图（依赖 `grim`+`slurp`） |

## Provides / does NOT provide

- **Provides**：notifications · system tray · screenshot · night light（`dms ipc call night`：gamma / 对比度 / 色温 / 定时，不必再装 gammastep）· clipboard history（`dms ipc call clipboard`，Mod+V）· GTK CSS auto-gen（原生生成 `~/.config/gtk-{3,4}.0/dank-colors.css`，每次登录重写） · accent-color writeback to `gsettings org.gnome.desktop.interface accent-color`（换壁纸时）
- **Does NOT provide**：file manager（nautilus）· image viewer（loupe）· video player（celluloid）· calculator（gnome-calculator）· disk utility（gnome-disk-utility）· screen recorder（gpu-screen-recorder）· KDE Connect frontend（DankKDEConnect plugin via `kdeconnect.sh`）· polkit agent（polkit-gnome）

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
  └─ dms-initial-settings.service (ours, IPC write — profile image)
```

主题生成不在这棵树里：`dms.service` 起来后自己读 `session.json` 的壁纸跑 matugen
（journal: `Processing theme: image <wallpaper>` → `Running matugen image with
dank16 injection`）。历史上有过的 `dms-matugen-init.service` 已在 1.6 上删除，
见下方 quirk。

`app-org.fcitx.Fcitx5@autostart.service`（systemd 从 `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop` 生成，因为 `niri.service` 带 `Wants=xdg-desktop-autostart.target`）被 `~/.config/autostart/org.fcitx.Fcitx5.desktop` 的 `Hidden=true` 显式屏蔽 —— 否则它会和 `fcitx5.service` 同时拉起第二个实例（见 [input-and-fonts.md](input-and-fonts.md#fcitx5-重复拉起)）。

`keyd.service`（系统级，由 `keyd.sh` 启）独立启动早于任何 user session，TTY/greetd 阶段就有正确键位。

`dms-initial-settings.service` 在第一次成功后自我禁用；换壁纸等后续动态更新全走 DMS 内部 matugen 调用，我们不控制。

## Quirks

### IPC

- **`dms ipc call ...` 和 `dms ipc ...` 都可用**：别被"`call` 被移除"的旧说法误导 —— 上游 `/usr/share/doc/dms-shell/IPC.md` 的规范格式就是 `dms ipc call <target> <fn>`，省掉 `call` 也生效（dms-shell 1.6.3 实测 `dms ipc night status` 与 `dms ipc call night status` 输出一致）。
- **`dms ipc keybinds toggle` 要 provider arg**：`dms ipc keybinds toggle niri`。其他常用 target（`launcher`/`settings`/`notifications`）都不要 provider，`keybinds` 是例外。
- **`dms ipc audio increment/decrement` 要 step arg**：`dms ipc audio increment "5"`。binds.kdl 必须显式传 step。
- **`dms ipc brightness increment/decrement` 要 step + device**：`dms ipc brightness increment "5" "backlight:amdgpu_bl2"`，device 名机器相关。`config/helpers/dms/brightness`（部署到 `~/.local/bin/dms-brightness`）自动取第一个 backlight，binds.kdl 用 wrapper 保持硬件无关。
- **DMS IPC 不能设置深层嵌套 key**：`dms ipc settings set cursorSettings.niri.hideWhenTyping true` 返回 `SETTINGS_INVALID_KEY`。Workaround：直接编辑 `settings.json`，下次 DMS 启动生效。

### Settings / setup

- **`gtkThemingEnabled` 在 1.6 已被删除**：二进制里 0 处引用，`dms ipc settings dump` 的 17 个键里也没有；`dms ipc settings get gtkThemingEnabled` 返回 `undefined`。GTK 取色改为原生 —— DMS 每次登录直接重写 `~/.config/gtk-{3,4}.0/dank-colors.css`，不需要任何开关。1.5 时代"写进 settings.json 会被重置回 false，得用 IPC 补"的 workaround 连同 `dms-initial-settings.service` 里那行一并删掉了。
- **`dms setup` 不部署 template / config**：v1.4.6 已知问题，`config.toml` 引用的模板可能缺失 → matugen 静默跳过；`binds.kdl` 可能空文件 → niri 零 keybind。Fix：自己 ship 模板到 `config/matugen/templates/` + `_set_template` 强制覆写；ship `config/niri/dms/binds.kdl` 通过 `copy_config` 部署。绑定原则：shell 功能用 DMS IPC；窗口/工作区操作用 niri 原生 action；raw `spawn` 仅当两者都覆盖不了时用。所有 `hotkey-overlay-title` 英文。
- **`settings.json` 只落盘"非默认值"**：`copy_config_merge`（`dms.sh`）把 `config/dms/settings.json` 的键 deep-merge 进 `~/.config/DankMaterialShell/settings.json`；但 DMS 保存时走 `SettingsStore.toJson()`（`Common/settings/SettingsStore.js:173`，运行时路径 `$XDG_RUNTIME_DIR/danklinux-shell/<hash>/` 下），里面一句 `if (Util.isDefault(value, SPEC[k].def)) continue` —— **等于 spec 默认值的键一律不写**（`isDefault` 是 `SpecUtil.js:13` 的 `stableStringify` 深比较，各键的 `def` 在 `Common/settings/SettingsSpec.js`）。推论：
  - 声明成默认值的键**永远不会**出现在部署文件里：install 时 merge 进去，DMS 下次保存就删掉，净效果为零。所以 `config/dms/settings.json` 只声明非默认值 —— 要钉住某个键，就钉非默认值（`lockBeforeSuspend: true`、`lockScreenPowerOffMonitorsOnLock: true`、`acMonitorTimeout`/`batteryMonitorTimeout: 600` 实测都留在本机文件里；`lockAtStartup: false` 和六个 `*Timeout`/`*Behavior: 0` 因为是默认值已从仓库删掉，见 [login.md](login.md)）。
  - `just drift` 把这类"仓库声明了、本机文件里没有"的标量键列成 `[INFO]`，**既不代表 merge 没生效，也测不出它生效与否** —— 值本身就等于 spec 默认值，`dms ipc settings get lockAtStartup` 返回的 `false` 跟 DMS 自己的默认值无法区分。判断某个键谁说了算要看 spec 的 `def`，不是看文件里有没有。
  - 反过来，非默认值落盘后**能稳定留着**：`cursorSettings.niri.hideWhenTyping`（spec 默认 `false`）这种 IPC 设不了、只能手改文件的深层键，写进去就一直在。

### matugen / 主题色

- **`dms-matugen-init.service` 已删除（1.6 起冗余且必然失败）**：DMS 自己就会在启动时从 `session.json` 的壁纸生成整套主题，不需要外部 one-shot。老单元的 `--shell-dir` 写死在 `/usr/share/quickshell/dms`，该目录在 UI 内嵌后已不存在 → `FATAL Theme generation failed`；而 `ExecStartPost` 只在成功时自我禁用 → 每次登录失败一次、永不收敛。（1.5 时代它还有个"no changes 时 exit 2"的坑，靠 `SuccessExitStatus=2` 绕过 —— 现在整单元一起没了。）
- **`starship.tera` 模板可能 stale**：`matugen.sh` 用 `copy_config_dir` 部署模板，但 `matugen.sh` 不重跑时部署的模板停在旧版本。matugen 每次换壁纸都基于旧模板重渲染，覆盖任何手工编辑的 `~/.config/starship.toml`。Fix：`cp config/matugen/templates/starship.tera ~/.config/matugen/templates/starship.tera`，再 `matugen --prefer lightness image <wallpaper>`。`just drift` 能直接报出这种"仓库改了但没重跑部署"的状态。
- **libadwaita 1.6+ accent**：GTK4 应用（Files/nautilus）从 gsettings 读 accent palette，不从 user `gtk.css` 的 `@define-color accent_*`。运行中应用不会 live 拾取 —— accent 改变需要 app 重启。By design，不是 bug。

### Niri 集成

- **niri config reload command**：`niri msg action load-config-file`（不是 `reload-config`，那个 subcommand 不存在）。

### Portals / screen sharing

- **Screen sharing 必须 `xdg-desktop-portal-wlr`**：`xdg-desktop-portal-gnome` 是为 GNOME session 设计的，不能在 niri 提供 ScreenCast。niri 实现了 `wlr-screencopy`，所以 wlr portal 必须与 gnome/gtk portals 并存。`config/dms/portals.conf` 把 `ScreenCast` 和 `Screenshot` 路由到 wlr，其他接口（FileChooser/Settings 等）留 gnome/gtk —— 两个 backend 共存无冲突。DMS 自己的 `dms screenshot` 绕过 portal（直接 grim+slurp）。
- **`xdg-desktop-portal-wlr` 需要 chooser config**：没有 `~/.config/xdg-desktop-portal-wlr/config`，portal 没法呈现 screen/output 选择器 → 会议软件里点 screen share 没反应。`config/dms/xdpw.conf` 配 `slurp -f %o -or` 作为 chooser。

### DankKDEConnect plugin

守护进程、设备发现、插件能力查询、文件传输这些**后端层**的坑在 [kdeconnect.md](kdeconnect.md)，本节只讲插件层。

**后端选型：上游 KDE Connect（`kdeconnectd`），不用 Valent。** kdeconnect 在官方仓库、随 KDE Gear 稳定发版；Valent 是 AUR 的 alpha（`1.0.0.alpha.x`）。插件两种后端都支持（`services/KDEConnectService.qml` 与 `ValentService.qml` 并存），换后端不丢功能。启动走包自带的 `/etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop`，由 systemd 的 xdg-autostart-generator 生成受管 unit —— 不写 niri spawn-at-startup、不自建 unit，少一条拉起路径就少一个重复实例的来源。

- **Tile 显示"无设备"但详情面板有设备（stale ID 死锁）**：`~/.config/DankMaterialShell/plugin_settings.json` 的 `dankKDEConnect.selectedDeviceId` 存了陈旧 ID（重新配对设备 / 换后端实现 / 重装都会换新 ID）。插件里**没有任何路径会重置非空的失效 ID**，所以这确实是个死锁：
  - tile：`DankKDEConnect.qml:433` 的 `hasDevice` 要求 ID 同时出现在 `deviceIds` 里，失效即为 false，`:461` 于是返回 "No devices"。
  - 详情面板：`KDEConnectDetailContent.qml:62` 的 `effectiveDeviceId` 在 ID 不在列表里时回退到 `deviceIds[0]`，照常显示真实设备 —— 两个视图不一致的根源就在这里。
  - 这个属性只有两个写入点：`:500` 从设置读（**只判非空，不校验设备是否还在**）和 `:601` 的 `selectDevice()`（用户操作）。
  - 自动选择只发生在 `selectedDeviceId === ""` 时（`:153` 的 `onSelectedDeviceIdChanged`、`:354` 的 `Component.onCompleted`），陈旧但非空就永远轮不到它。

  **修法**：先试插件自带的 `Alt+1`（`:550` 起的 Repeater，最多到 `Alt+9`）—— 它调 `selectDevice(deviceIds[0])`，顺带把新 ID 写回 plugin_settings，等于就地修好持久化的陈旧值；代价是它属于 `Qt.WindowShortcut`，bar 或弹窗得有焦点。`Ctrl+Tab` / `Ctrl+Shift+Tab` 只在设备数 >1 时有用（`switchDeviceNext` 在 `ids.length <= 1` 时直接 return）。都不方便时再手改 JSON：`kdeconnect-cli -l --id-only` 拿实测 ID 写进 `plugin_settings.json`，重启 DMS —— 光重启 DMS 不够，`onDevicesListChanged` 的初始信号可能在 plugin 订阅前就发了。
- **同一个协议只能有一个守护进程**：KDE Connect 与 Valent 都实现协议，同时跑会抢 `org.kde.kdeconnect` 总线名并各自做一遍设备发现。本仓库只保留一个后端（`kdeconnectd`，见上），所以别再加第二条拉起路径：不写 Valent 的 `spawn-at-startup`，也不给 kdeconnectd 另建 unit —— 它已经有包自带的 `/etc/xdg/autostart/` 那条。

## Why no `dankinstall`

`dankinstall` 是 DMS 官方 one-shot 配置工具。我们跳过它因为它装 `mako`（与 DMS 通知 daemon 冲突）和 `xfce-polkit` —— 都不想要。代价：dankinstall 免费 ship 的产物（niri binds 等）我们自己 ship。
