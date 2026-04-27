# Config file map

`config/` 下的 source 文件 → 部署目标。哪个脚本负责部署写在右列。

| Repo path | Destination | Deployed by |
|---|---|---|
| `config/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` | `shell.sh` |
| `config/alacritty/dracula.toml` | `~/.config/alacritty/dracula.toml` | `shell.sh` |
| `config/dms/settings.json` | merged into `~/.config/DankMaterialShell/settings.json` | `dms.sh`（inline Python deep-merge） |
| `config/dms/environment.conf` | `~/.config/environment.d/90-dms.conf` | `dms.sh` |
| `config/dms/portals.conf` | `~/.config/xdg-desktop-portal/portals.conf` | `dms.sh`（portal backend 路由） |
| `config/dms/xdpw.conf` | `~/.config/xdg-desktop-portal-wlr/config` | `dms.sh`（wlr portal screen chooser） |
| `config/fcitx5/` | `~/.config/fcitx5/` | `fcitx.sh` |
| `config/fontconfig/60-emoji.conf` | `/etc/fonts/conf.d/60-emoji.conf` | `fonts.sh`（Noto Color Emoji 前置） |
| `config/fontconfig/65-cjk-sc.conf` | `/etc/fonts/conf.d/65-cjk-sc.conf` | `fonts.sh`（CJK fallback 顺序） |
| `config/greetd/greetd-wrapper.sh` | `/usr/local/bin/greetd-wrapper.sh` | `login.sh`（regreet → tuigreet fallback） |
| `config/helpers/dms/brightness` | `~/.local/bin/dms-brightness` | `shell.sh`（亮度 wrapper，自动检测 backlight 设备） |
| `config/helpers/clipboard/unified-clipboard` | `/usr/local/bin/unified-clipboard` | `clipboard.sh`（CLIPBOARD + PRIMARY 双向，含 WeChat file paste compat） |
| `config/helpers/clipboard/primary-sync` | `/usr/local/bin/primary-sync` | _deprecated_（v1 旧 daemon，已被 unified-clipboard 替代） |
| `config/helpers/clipboard/wechat-uri-fix` | `/usr/local/bin/wechat-uri-fix` | _deprecated_（v1 旧 daemon，已被 unified-clipboard 替代） |
| `config/helpers/valent-send/valent_send.py` | `~/.local/share/nautilus-python/extensions/valent_send.py` | `kdeconnect.sh`（Nautilus 右键 "Send to <device>"；扩展只在 nautilus 启动时加载，部署后需 `nautilus -q`） |
| `config/input/keyd.conf` | `/etc/keyd/default.conf` | `keyd.sh` |
| `config/matugen/` | `~/.config/matugen/` | `matugen.sh` |
| `config/niri/dms/binds.kdl` | `~/.config/niri/dms/binds.kdl` | `dms.sh`（niri keybinds, DMS IPC 集成） |
| `config/niri/dms/windowrules.kdl` | `~/.config/niri/dms/windowrules.kdl` | `dms.sh`（browser PiP floating rule） |
| `config/helpers/gsr-toggle` | `~/.local/bin/gsr-toggle` | `shell.sh`（gpu-screen-recorder 开关，MP4 60fps opus） |
| `config/shell/zshrc` | `~/.zshrc` | `shell.sh` |
| `config/flatpak/fonts.conf` | `~/.config/fontconfig/fonts.conf` | `fonts.sh`（全局 flatpak override，所有 Flatpak app 受益） |

## Matugen templates

`config/matugen/templates/*.tera` **不**直接 copy 到最终目标 —— `matugen.sh` ship 到 `~/.config/matugen/templates/`，再用 `_set_template` 注册 `[templates.<name>]` 到 `config.toml`。matugen 首次登录（之后每次换壁纸）渲染：

- `config/matugen/templates/starship.tera` → `~/.config/starship.toml`
- `config/matugen/templates/fcitx5.tera` → `~/.local/share/fcitx5/themes/Matugen/theme.conf`

## fcitx5 rime icons

`assets/icons/fcitx_rime_*.svg` 被 `fcitx.sh` 原样复制到 `~/.local/share/icons/hicolor/scalable/apps/`，覆盖 fcitx5 自带 rime 状态图标。`fcitx.sh` 同时写最小 `index.theme` 到 user-level hicolor root —— 否则 `gtk-update-icon-cache` 产生空 cache stub，托盘图标全消失（见 [quirks/input-and-fonts.md](quirks/input-and-fonts.md)）。

## DMS settings merge

`config/dms/settings.json` 是 **merged**（非 replaced），通过 `dms.sh` 里 inline Python 处理 —— 保留 DMS 自己生成的默认值。merge 对嵌套 dict 是 **deep** 的；list 整体覆盖（DMS 数组语义是全量替换）。
