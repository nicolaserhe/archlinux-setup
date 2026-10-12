# Config file map

`config/` 下的 source 文件 → 部署目标 → **归属**。哪个脚本负责部署写在右列。

归属不是文档里的标签，是代码里的调用：`lib/fs.sh` 提供一族部署 helper，调用哪个就是哪种归属。`just drift` 反过来扫这些调用点，得出这张表并比对本机实际状态 —— 所以本文件只是给人读的快照，**不是**权威源，也不会因为没同步而骗人。

| 归属 | helper | 语义 |
|---|---|---|
| **own** 仓库拥有 | `copy_config` / `copy_config_dir` / `install_config` / `install_config_root` | 每次 install 无条件覆盖。本机改了它就等于漂移，会被 `just drift` 报出来 |
| **seed** 仅首次播种 | `copy_config_seed` | 目标已存在就跳过。之后由运行时程序接管（它重写、加注释都正常），只检查文件还在不在 |
| **merge** 共同拥有 | `copy_config_merge` | 仓库只贡献若干键，运行时程序同时也在写同一个文件。不比对整体内容 |

## config/ 部署表

| Repo path | Destination | Deployed by |
|---|---|---|
| `config/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` | `shell.sh` |
| `config/alacritty/dracula.toml` | `~/.config/alacritty/dracula.toml` | `shell.sh` |
| `config/autostart/org.fcitx.Fcitx5.desktop` | `~/.config/autostart/org.fcitx.Fcitx5.desktop` | `fcitx.sh`（`Hidden=true`，屏蔽 XDG autostart 与自建 unit 的重复拉起） |
| `config/dms/settings.json` | merged into `~/.config/DankMaterialShell/settings.json` | `dms.sh`（`copy_config_merge`） |
| `config/dms/environment.conf` | `~/.config/environment.d/90-dms.conf` | `dms.sh` |
| `config/dms/portals.conf` | `~/.config/xdg-desktop-portal/portals.conf` | `dms.sh`（portal backend 路由） |
| `config/dms/xdpw.conf` | `~/.config/xdg-desktop-portal-wlr/config` | `dms.sh`（wlr portal screen chooser） |
| `config/docker/daemon.json` | `/etc/docker/daemon.json` | `docker.sh`（root；只写日志上限，理由与生效时机见 [quirks/docker.md](quirks/docker.md)） |
| `config/fcitx5/classicui.conf` | `~/.config/fcitx5/conf/classicui.conf` | `fcitx.sh`（字体 + `Theme=Matugen`） |
| `config/fcitx5/profile` | `~/.config/fcitx5/profile` | `fcitx.sh` —— **仅首次播种**：fcitx5 会把整个文件按自己的格式重写，覆盖它等于每次重跑 install 都重置用户的输入法顺序 |
| `config/fcitx5/rime/default.custom.yaml` | `~/.local/share/fcitx5/rime/default.custom.yaml` | `fcitx.sh` |
| `config/flatpak/fonts.conf` | `~/.config/fontconfig/flatpak-cjk.conf` | `fonts.sh`（**只**经 flatpak override 的 `FONTCONFIG_FILE` 给沙箱用；刻意不占 `fonts.conf` 那个主机用户级路径） |
| `config/fontconfig/60-emoji.conf` | `/etc/fonts/conf.d/60-emoji.conf` | `fonts.sh`（Noto Color Emoji 前置，root） |
| `config/fontconfig/65-cjk-sc.conf` | `/etc/fonts/conf.d/65-cjk-sc.conf` | `fonts.sh`（CJK fallback 顺序，root） |
| `config/greetd/config.toml` | `/etc/greetd/config.toml` | `login.sh`（root；autologin 段以注释形式放在仓库文件里，取消注释再重跑即可） |
| `config/greetd/regreet.toml` | `/etc/greetd/regreet.toml` | `login.sh`（root） |
| `config/greetd/greetd-wrapper.sh` | `/usr/local/bin/greetd-wrapper.sh` | `login.sh`（regreet → tuigreet fallback，root） |
| `config/helpers/dms/brightness` | `~/.local/bin/dms-brightness` | `shell.sh`（亮度 wrapper，自动检测 backlight 设备） |
| `config/helpers/git-health` | `~/.local/bin/git-health` | `shell.sh` |
| `config/helpers/gsr-toggle` | `~/.local/bin/gsr-toggle` | `shell.sh`（gpu-screen-recorder 开关，MP4 60fps opus） |
| `config/input/keyd.conf` | `/etc/keyd/default.conf` | `keyd.sh`（root） |
| `config/matugen/templates/*.tera` | `~/.config/matugen/templates/` | `matugen.sh`（`copy_config_dir`，见下节） |
| `config/niri/dms/binds.kdl` | `~/.config/niri/dms/binds.kdl` | `dms.sh`（niri keybinds, DMS IPC 集成） |
| `config/niri/dms/windowrules.kdl` | `~/.config/niri/dms/windowrules.kdl` | `dms.sh` —— **仅首次播种**：该文件同时是 DMS 的窗口规则存储，DMS 会加 `@id` 标记后整体重写 |
| `config/shell/zshrc` | `~/.zshrc` | `shell.sh` |
| `config/timesyncd/60-cn-ntp.conf` | `/etc/systemd/timesyncd.conf.d/60-cn-ntp.conf` | `system-services.sh`（root；国内 NTP 源） |

## `config/fcitx5/rime/default.custom.yaml`

rime 词库本身**不在仓库里**：装的是 archlinuxcn 的 `rime-ice-double-pinyin-flypy-git`（词库落在 `/usr/share/rime-data/`，由 pacman 升级）。仓库只部署用户目录里的这个 patch 文件 —— 它必须和包变体对上（`schema_list: double_pinyin_flypy`），且是 rime 唯一的配置入口（`rime_ice.custom.yaml` 之类留给用户自己写，不在仓库）。用户目录里只该有用户自己的东西 —— rime-ice 的仓库文件一份都不往那儿放（rime 查文件时用户目录优先，副本会一直 shadow 掉 `/usr/share/rime-data` 里的同名文件）。

## 机器私有文件：`~/.config/zsh/local.zsh`

`~/.zshrc` 是 **own**（每次 install 覆盖），所以机器专属的环境变量不能写在里面。`config/shell/zshrc` 末尾 source `~/.config/zsh/local.zsh`（存在才 source），sdkman / `JAVA_HOME` / `ANDROID_SDK_ROOT` / Flutter 这类绑定本机 `$HOME` 路径的东西、以及密钥（`DEEPSEEK_API_KEY`）都放那儿。这个文件**不在仓库里、仓库也不部署它** —— 重跑 install 不会再冲掉工具链环境与密钥（在此之前，重跑一次 install.sh 就会丢）。

## 不在清单里的东西

`just drift` 只盘点"内容来自 `config/` 的文件"。下面这些同样是安装产物，但内容不来自仓库，所以不在漂移检查范围内，别把它们的不一致当成 bug：

- niri/dms 的空 stub（`colors.kdl` / `layout.kdl` / `alttab.kdl`，`dms.sh` 只保证文件存在，内容 DMS 自己写）
- `~/.config/gtk-{3,4}.0/settings.ini` + `gtk.css` 软链（`dms.sh` 写；`dank-colors.css` 由 DMS 每次登录生成）
- systemd user unit / drop-in（`lib/svc.sh` 从 heredoc 写出）
- `~/.local/state/DankMaterialShell/session.json`（`dms.sh` 用 heredoc 首次写入，含壁纸/头像这类机器私有值；之后 DMS 自己持续更新。它**有**仓库来源，但内容天然是本机状态，比对没有意义 —— 见 dms.md 里"settings.json 只存非默认值、机器状态搬到 session.json"那条）、`~/.config/matugen/config.toml`（`dms setup` 创建，之后 `matugen.sh` 往里 merge `[templates.*]`）
- `assets/` 下的壁纸、头像、图标（一次性拷贝的二进制资源，不比对）

## Matugen templates

`config/matugen/templates/*.tera` 由 `matugen.sh` 用 `copy_config_dir` 一次部署整个目录到 `~/.config/matugen/templates/`，再用 `_set_template` 注册 `[templates.<name>]` 到 `~/.config/matugen/config.toml`（`config.toml` 由 `dms setup` 创建，归 DMS）。matugen 首次登录（之后每次换壁纸）渲染：

- `config/matugen/templates/starship.tera` → `~/.config/starship.toml`
- `config/matugen/templates/fcitx5.tera` → `~/.local/share/fcitx5/themes/Matugen/theme.conf`

## fcitx5 rime icons

`assets/icons/fcitx_rime_*.svg` 被 `fcitx.sh` 原样复制到 `~/.local/share/icons/hicolor/scalable/apps/`，覆盖 fcitx5 自带 rime 状态图标。`fcitx.sh` 同时写最小 `index.theme` 到 user-level hicolor root —— 否则 `gtk-update-icon-cache` 产生空 cache stub，托盘图标全消失（见 [quirks/input-and-fonts.md](quirks/input-and-fonts.md)）。

## DMS settings merge

`config/dms/settings.json` 是 **merged**（非 replaced），通过 `copy_config_merge` → `lib/helpers/merge-json-deep.py` —— 保留 DMS 自己生成的默认值。merge 对嵌套 dict 是 **deep** 的；list 整体覆盖（DMS 数组语义是全量替换）。**merge 是单向的**：它只把仓库的键写进本机文件，从不删除本机已有的键 —— 所以从仓库里删掉一个键，本机那份文件不会有任何变化（要清掉本机残留得手改）。

已知边界：**声明成 DMS 默认值的键等于没声明**。DMS 落盘走 `SettingsStore.toJson()`，其中 `if (Util.isDefault(value, SPEC[k].def)) continue` 跳过一切等于 spec 默认值的键 —— 所以这类键写进去也会在 DMS 下次保存时消失，"仓库里声明了但本机文件里没有"是常态而非事故。`just drift` 会把这类标量键列成 `[INFO]`，只陈述事实，不当失败；也正因如此，`config/dms/settings.json` 只声明非默认值（要钉住就钉非默认值，如 `lockBeforeSuspend: true`）。见 [quirks/dms.md](quirks/dms.md)。
