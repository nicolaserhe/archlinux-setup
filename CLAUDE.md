# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Automated post-install setup for a personal Arch Linux desktop (niri + DankMaterialShell). Run once on a freshly installed system; not idempotent in the sense of being safe to re-run arbitrarily, but most steps skip gracefully if already done.

## Running the installer

```bash
# Live ISO 内的"无脑"步骤：镜像源 + 微码自检 + pacstrap + fstab + 拷 chroot 脚本
# （分区/格式化/挂载/chroot/最后 umount 自己手动，避免误抹盘）
bash usb/install-base.sh
# 然后手动：arch-chroot /mnt && bash /root/usb-bootstrap/in-chroot.sh
# in-chroot.sh 全交互、零参数（菜单选 bootloader；systemd-boot 才会再问根分区）

# Full install (as root, from repo root, on the installed system)
bash install.sh

# Re-apply only user configs (as the target user, after install)
bash scripts/user-phase.sh /path/to/repo

# Install or re-install a single application (as user, no proxy)
bash scripts/apps/<name>.sh
```

**Prerequisites before running:**
- Place a valid Clash YAML config at `usb/sub2clash/files/*.yaml` (proxy is required for AUR/Flatpak downloads)
- Place `assets/wallpaper.{jpg,png}` and `assets/avatar.{jpg,png}`

**Post-install manual steps:**
- Set `DEEPSEEK_API_KEY` in `~/.zshrc` (the zshrc ships an empty `export DEEPSEEK_API_KEY=""`). Required for nvim minuet-ai ghost text completion (`<A-y>` to accept). Without it, minuet stays silent and `:MinuetToggle` errors.

## Repository layout

The codebase has three layers, reflecting **when** the script runs:

- **`usb/`** — bootstrap before the OS exists。`install-base.sh`（CN 镜像+微码+pacstrap+genfstab，不碰分区/mount/chroot）+ `in-chroot.sh`（chroot 内零参数全交互：bootloader 菜单/时区/locale/hostname）+ `sub2clash/`（独立订阅转换器）。**所有输出 ASCII 英文**（live ISO 无 CJK 字体）
- **`scripts/core/`** — system layer (compositor, shell, login, audio, input method...). Rarely changes. Run sequentially by `install.sh` in user-phase.
- **`scripts/apps/`** — application layer (Chrome, WeChat, QQ, Yaak, ...). Frequently installed/uninstalled. Each script is **self-contained** and can be run alone via `bash scripts/apps/<name>.sh` (no proxy started, sudo prompts on demand).

Package source (pacman / AUR / Flatpak) is **not** a directory — each module manages its own dependencies via `lib/pkg.sh` helpers.

## Two-phase architecture

`install.sh` runs as **root** and delegates user-level work via `runuser`:

```
install.sh (root)
├── scripts/setup-user.sh           # 1. create/select TARGET_USER
├── scripts/core/01-pacman-base.sh  # 2. pacman base packages + archlinuxcn
├── [sudo setup + mihomo proxy]     # 3-4
├── [enable linger + chown repo]    # 5-6
└── scripts/user-phase.sh (TARGET_USER)   # 7
    ├── proxy_start                          # mihomo bring-up via lib/proxy.sh
    ├── scripts/core/02-aur-bootstrap.sh     # yay
    ├── scripts/core/03-fonts.sh             # 字体基础设施：包 + 系统 fontconfig + Flatpak 字体修复
    ├── scripts/core/04-flatpak-init.sh      # Flathub remote
    ├── scripts/core/compositor.sh           # niri + xwayland + portals
    ├── scripts/core/login.sh                # greetd + regreet + tuigreet fallback
    ├── scripts/core/audio.sh                # PipeWire stack
    ├── scripts/core/system-services.sh      # bluetooth + avahi + power-profiles
    ├── scripts/core/docker.sh               # docker daemon + compose 子命令 + jq
    ├── scripts/core/shell.sh                # zsh + neovim + alacritty + eza + starship
    ├── scripts/core/dms.sh                  # DMS + matugen + GTK theming
    ├── scripts/core/matugen.sh              # must run AFTER dms.sh
    ├── scripts/core/fcitx.sh                # fcitx5 + rime-ice
    ├── scripts/core/keyd.sh                 # keyd key remapping
    ├── scripts/core/kdeconnect.sh           # must run AFTER dms.sh
    ├── scripts/core/clipboard.sh            # X11 ↔ Wayland clipboard bridge (CLIPBOARD + PRIMARY)
    ├── scripts/core/flclash.sh              # FlClash + subscription import
    ├── scripts/core/boot.sh                 # GRUB matter theme (sudo matter.py)
    └── scripts/apps/*.sh                    # all applications, in dict order
```

The proxy (Mihomo) is installed at step 4 of `install.sh` and torn down by a `trap EXIT` — it is never left on the system after the script exits.

### Cleanup architecture

All cleanup runs as **root** via `install.sh`'s `_cleanup` (trap EXIT). Individual scripts **must not** set their own cleanup traps — root-owned files (e.g. `sudo python3 matter.py` creates root `__pycache__`) cause `rm -rf` to fail under `set -e` when run as a non-root user. Temp directories in `/tmp` are cleaned by both `_clean_tmp_state` (pre-flight) and `_cleanup` (post-install):

```bash
rm -rf /tmp/yay-build.* /tmp/rime-ice.* /tmp/dms-plugins.* /tmp/grub-matter.*
```

The only exception is `user-phase.sh`'s `_on_exit` trap, which stops the mihomo process (started by that same script) and prints the step summary. The root cleanup also kills mihomo as a safety net.

## Package placement: root vs user

`01-pacman-base.sh` (root) vs `shell.sh` (user). **No duplicates** — each package lives in exactly one place. System-wide infra and language runtimes → root; opinionated dev tools and version managers → user. Gotchas: `tree-sitter-cli` (NOT `tree-sitter`); `fnm`/`yarn` in extra repo (not AUR); nvim needs `python bootstrap.py` after clone.

**子脚本不要"兜底"重装 base 已经列过的包**（imagemagick / expect / curl 等）：base 是权威，本机出现某个 base 包缺失是历史人工卸载导致，不该让每个调用方背防御性 `pacman_install`。要补就在 base 里补，要修就修本机。

## Shared libraries (`lib/`)

Every script sources what it needs; each library guards against double-sourcing with `_*_LOADED` variables.

| File | Exports |
|---|---|
| `lib/utils.sh` | `info/success/warn/error/header/die`, `retry`, `run_step`, `print_summary`, `ensure_xdg_runtime_dir` |
| `lib/fs.sh` | `setup_sudo`, `git_clone`, `copy_config`, `find_asset`, `add_user_to_group` |
| `lib/pkg.sh` | `pacman_install`, `pacman_remove`, `aur_install`, `flatpak_install` (install helpers skip already-installed; `pacman_remove` skips not-installed). `pacman_install`/`pacman_remove` 内置 `sudo`，root 阶段透传无害、user-phase 阶段必备；不要再写 `sudo pacman -S` |
| `lib/svc.sh` | `enable_system_service`, `enable_user_service`, `add_user_service_wants`, `switch_display_manager` |
| `lib/proxy.sh` | `proxy_start`, `proxy_stop` (must be **sourced**, not executed — exports env vars to caller) |

**Key conventions:**
- All log output goes to **stderr**; stdout is kept clean so `$()` captures work correctly (e.g., `TARGET_USER="$(bash scripts/setup-user.sh)"`)
- `run_step "label" cmd` wraps any step: logs header, tracks pass/fail, prints summary at exit
- System-level operations in user-phase scripts use `sudo` (a temporary NOPASSWD rule is installed by `install.sh` and removed by the trap)
- Single-app re-runs (`bash scripts/apps/<name>.sh`) do **not** rely on the install-tmp NOPASSWD rule and prompt for password on demand

## Ordering constraints

- `02-aur-bootstrap.sh` → any module installing AUR packages: `login.sh`, `shell.sh`, `dms.sh`, `kdeconnect.sh`, `clipboard.sh` and most `apps/*.sh` invoke `aur_install` which requires yay
- `04-flatpak-init.sh` → any Flatpak app: registers Flathub remote; required before any `flatpak_install` call
- `03-fonts.sh` → any app with CJK/emoji text: deploys system fontconfig + Flatpak fontconfig override; run after `02-aur-bootstrap.sh` (uses sudo for `/etc/fonts/conf.d/`)
- `dms.sh` → `matugen.sh`: matugen overrides specific `[templates.*]` blocks in the DMS-generated `config.toml`; running matugen first would have nothing to override
- `dms.sh` → `kdeconnect.sh`: `kdeconnect.sh` is a DMS plugin installer; `dms.sh` writes all niri `config.kdl` content (incl. Valent `spawn-at-startup`); `kdeconnect.sh` only installs the plugin and `environment.d` config — never touches `config.kdl`
- `usb/sub2clash/convert.sh` → `flclash.sh`: `flclash.sh` reads `usb/sub2clash/files/config.yaml`; the conversion script must run first
- `docker.sh` → `apps/searxng.sh`: searxng 用 `docker compose` 起容器；docker.sh 装 docker + compose plugin + jq 并把用户加进 docker 组。同一次 install.sh 流程里用户进组**不会即时生效**（fork 时机），所以 searxng.sh 检测到组没生效时用 `sudo docker` 兜底

## Config files (`config/`)

Source files shipped in the repo, copied to their destinations by the core/apps scripts:

| Repo path | Destination |
|---|---|
| `config/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` |
| `config/alacritty/dracula.toml` | `~/.config/alacritty/dracula.toml` |
| `config/dms/settings.json` | merged into `~/.config/DankMaterialShell/settings.json` |
| `config/dms/environment.conf` | `~/.config/environment.d/90-dms.conf` |
| `config/dms/portals.conf` | `~/.config/xdg-desktop-portal/portals.conf` (portal backend routing) |
| `config/dms/xdpw.conf` | `~/.config/xdg-desktop-portal-wlr/config` (wlr portal screen chooser) |
| `config/fcitx5/` | `~/.config/fcitx5/` |
| `config/fontconfig/60-emoji.conf` | `/etc/fonts/conf.d/60-emoji.conf` (deployed by `03-fonts.sh`; prepends Noto Color Emoji before CJK fallbacks) |
| `config/fontconfig/65-cjk-sc.conf` | `/etc/fonts/conf.d/65-cjk-sc.conf` (deployed by `03-fonts.sh`; CJK fallback ordering) |
| `config/greetd/greetd-wrapper.sh` | `/usr/local/bin/greetd-wrapper.sh` (regreet 主，失败 fallback tuigreet) |
| `config/helpers/dms/brightness` | `~/.local/bin/dms-brightness` (brightness wrapper, auto-detects backlight device) |
| `config/helpers/clipboard/primary-sync` | `/usr/local/bin/primary-sync` (Python event-driven daemon — CLIPBOARD ↔ PRIMARY ↔ X11 PRIMARY three-way sync, deployed by `clipboard.sh`) |
| `config/helpers/clipboard/wechat-uri-fix` | `/usr/local/bin/wechat-uri-fix` (Python daemon — Wayland→X11 CLIPBOARD compat shim for WeChat Flatpak file paste, deployed by `clipboard.sh`) |
| `config/helpers/valent-send/valent_send.py` | `~/.local/share/nautilus-python/extensions/valent_send.py` (Nautilus 右键 "Send to <device>" 调 Valent `share.uris` GAction，deployed by `kdeconnect.sh`；扩展只在 nautilus 启动时加载，部署后需 `nautilus -q`) |
| `config/input/keyd.conf` | `/etc/keyd/default.conf` (keyd system-wide config) |
| `config/matugen/` | `~/.config/matugen/` |
| `config/niri/dms/binds.kdl` | `~/.config/niri/dms/binds.kdl` (niri keybinds, DMS IPC integrated) |
| `config/niri/dms/windowrules.kdl` | `~/.config/niri/dms/windowrules.kdl` (browser PiP floating rule, deployed by `dms.sh`) |
| `config/helpers/gsr-toggle` | `~/.local/bin/gsr-toggle` (gpu-screen-recorder start/stop toggle, single monitor, MP4 60fps opus) |
| `config/shell/zshrc` | `~/.zshrc` |
| `config/flatpak/fonts.conf` | `~/.config/fontconfig/fonts.conf` (deployed by `03-fonts.sh`; global flatpak override, all Flatpak apps benefit) |
| `config/searxng/docker-compose.yml` | `~/services/searxng/docker-compose.yml` (host network + Granian on :8888) |
| `config/searxng/settings.yml` | `~/services/searxng/settings.yml` (deployed by `apps/searxng.sh`; `__SECRET_KEY__` 由 openssl rand 替换；首次后保留旧 key) |
| `config/helpers/searxng/websearch` | `~/.local/bin/websearch` (Bash CLI 调本地 SearXNG 的 JSON API，jq 格式化输出) |

Templates under `config/matugen/templates/*.tera` are NOT copied to their final destinations directly — `matugen.sh` ships them to `~/.config/matugen/templates/` and registers `[templates.<name>]` entries in `config.toml` via the `_set_template` helper. matugen renders them on first login (and on every wallpaper change after) into:
- `config/matugen/templates/starship.tera` → `~/.config/starship.toml`
- `config/matugen/templates/fcitx5.tera` → `~/.local/share/fcitx5/themes/Matugen/theme.conf`

`assets/icons/fcitx_rime_*.svg` are copied verbatim to `~/.local/share/icons/hicolor/scalable/apps/` by `fcitx.sh` to override fcitx5's bundled rime status icons. A minimal `index.theme` is also written to the user-level hicolor root so `gtk-update-icon-cache` produces a real cache (see quirk below).

`config/dms/settings.json` is **merged** (not replaced) via inline Python in `dms.sh` to preserve DMS-generated defaults. Merge is **deep** for nested dicts; lists overwrite (DMS array semantics is full-replacement).

## Login flow (greetd)

`scripts/core/login.sh` 写 `/etc/greetd/config.toml` 两条 session:

- **`[initial_session]`** — 开机自动以 `$USER` 跑 `niri-session`，跳过 regreet GUI。greetd 0.10+ 行为：initial_session 进程退出后转 default_session，所以 logout 回到登录界面，重启又触发 initial_session。
- **`[default_session]`** — `/usr/local/bin/greetd-wrapper.sh`（regreet → tuigreet fallback），login flow 经过 PAM auth。

锁屏由 DMS 接手而非 greetd —— `config/dms/settings.json` 的 `lockAtStartup: true` 让 niri 启动后 DMS 立刻锁屏，所以 autologin 后仍要输一次密码。

要全无密码登录: 同时禁 `lockAtStartup`。要恢复 regreet 选择登录: 删 `[initial_session]` 段。

## DMS (DankMaterialShell) notes

DMS is a Go backend (`/usr/sbin/dms`) + Quickshell frontend (`/usr/share/quickshell/dms`), communicating via Unix socket. Docs: https://danklinux.com/docs/dankmaterialshell.

### Key commands

| Command | Purpose |
|---|---|
| `dms setup` | Generate initial `~/.config/matugen/config.toml` and base settings. Interactive — `dms.sh` drives via `expect` (`scripts/core/helpers/dms-setup.exp`) |
| `dms ipc <target> <function> [args]` | Runtime control. E.g. `dms ipc settings set <key> <value>`, `dms ipc profile setImage <path>`. **Do NOT use `dms ipc call ...`** — v1.4.6+ rejects with `Target not found` |
| `dms matugen generate --shell-dir /usr/share/quickshell/dms --state-dir <state> --config-dir <config> --value <wallpaper>` | Synchronous matugen run. **`--shell-dir` and `--config-dir` both required as of v1.4.6+**. Use `~/.local/share/wallpapers/` for wallpaper path — `dms ipc profile getImage` returns the avatar image, NOT the wallpaper, and will produce wrong colors. |
| `dms screenshot` | Built-in Wayland screenshot (depends on `grim`+`slurp`) |

### Provided natively / NOT provided

- **Provides:** notifications · system tray · screenshot · GTK CSS auto-generation (when `gtkThemingEnabled=true`) · accent-color writeback to `gsettings org.gnome.desktop.interface accent-color` on wallpaper change
- **Does NOT provide:** file manager (nautilus) · image viewer (loupe) · video player (celluloid) · calculator (gnome-calculator) · disk utility (gnome-disk-utility) · screen recorder (gpu-screen-recorder) · KDE Connect frontend (DankKDEConnect plugin via `kdeconnect.sh`) · night light (gammastep) · polkit agent (polkit-gnome)

### Quirks (these caused real bugs)

- **`dms ipc keybinds toggle` requires provider arg**: `dms ipc keybinds toggle niri` — omitting `niri` returns "Too few arguments" and does nothing. All other common targets (`launcher`, `settings`, `notifications`, etc.) do NOT need a provider arg; `keybinds` is the exception.
- **`dms ipc audio increment/decrement` requires a step arg**: `dms ipc audio increment "5"` — omitting the step returns "Too few arguments". binds.kdl must pass the step explicitly.
- **`dms ipc brightness increment/decrement` requires step + device**: `dms ipc brightness increment "5" "backlight:amdgpu_bl2"` — device name is machine-specific. Use `dms ipc brightness list` to enumerate available devices. `config/helpers/dms/brightness` (deployed to `~/.local/bin/dms-brightness`) auto-detects the first backlight device so binds.kdl stays hardware-independent.
- **niri config reload command**: `niri msg action load-config-file` (NOT `reload-config` — that subcommand doesn't exist).
- **`gtkThemingEnabled` self-resets**: putting `"gtkThemingEnabled": true` in `config/dms/settings.json` does NOT survive — DMS resets it to `false` on startup despite the JSON merge. Workaround: set via IPC after DMS is running. `dms-initial-settings.service` does this.
- **`dms setup` 不部署 template / config 文件**: v1.4.6 已知问题：`config.toml` 引用的模板文件可能缺失 → matugen 静默跳过；`binds.kdl` 可能空文件 → niri 零 keybind。Fix: 自己 ship 模板到 `config/matugen/templates/` + `_set_template` 强制覆写；ship `config/niri/dms/binds.kdl` 通过 `copy_config` 部署。绑定原则：shell 功能用 DMS IPC；窗口/工作区操作用 niri 原生 action；raw `spawn` 仅当两者都覆盖不了时用。所有 `hotkey-overlay-title` 英文。
- **greetd wrapper: regreet 直跑 + tuigreet fallback**: 我们 logout 才会看到 greeter（开机走 autologin，见 `## Login flow`），所以 wrapper 优先级是「可用 > 美观」。`config/greetd/greetd-wrapper.sh` 直接 `regreet`（不再用 cage 包 wayland nested compositor — regreet 0.3+ 自带 wayland backend），失败时 `exec tuigreet` 兜底。`greetd-tuigreet` 是 extra repo 包，`login.sh` 装。永远可登录。
- **hicolor user icon cache must have an `index.theme`**: `gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor/` (`-t` = `--ignore-theme-index`) generates an empty cache stub when no `index.theme` is present. GTK reads the cache first → no icons found → tray icons silently disappear. Fix: ship a minimal `index.theme` to the user-level hicolor root before running cache update (handled in `fcitx.sh`).
- **Notification daemon conflicts**: DMS registers `org.freedesktop.Notifications`. Pre-existing `mako`/`dunst`/`notification-daemon` blocks `dms.service` (`systemd: Two services allocated for the same bus name`). Cleanup: `scripts/preflight.sh` (manual run, NOT auto-invoked by `install.sh`).
- **Alacritty font family name is case-sensitive with spaces**: must be `"Maple Mono NF CN"` (not `"maple-mono-nf-cn"`). Wrong name → fontconfig falls back to Nimbus Sans (proportional) → characters overlap in terminal.
- **`noto-fonts-cjk` and `noto-fonts-emoji` don't ship fontconfig rules on Arch**: two configs deployed to `/etc/fonts/conf.d/`: `60-emoji.conf` prepends Noto Color Emoji (CJK fonts contain monochrome emoji glyphs that shadow the color font), `65-cjk-sc.conf` handles CJK fallback (lang=zh → prepend strong, otherwise → append weak). `noto-fonts` (Latin) must also be installed — it shares vertical metrics with Noto CJK SC, preventing baseline offset in mixed Chinese+Latin text.
- **Avahi required for Valent/KDE Connect discovery**: without `avahi-daemon.service` enabled, the phone cannot discover the desktop on the LAN. `system-services.sh` enables it.
- **fcitx5 rime tray icon requires both short and full name**: fcitx5 requests icons as `org.fcitx.Fcitx5.fcitx_rime_im` (full reverse-domain name). Deploying only `fcitx_rime_im.svg` to hicolor does nothing — must also deploy `org.fcitx.Fcitx5.fcitx_rime_im.svg`. `fcitx.sh` deploys both.
- **starship.toml palette block must be last**: placing `[palettes.dracula]` before module sections causes TOML to parse subsequent root keys (e.g. `add_newline`) as palette color strings. Always put `[palettes.*]` at the end of the file.
- **libadwaita 1.6+ accent**: GTK4 apps (Files/nautilus) read accent palette from gsettings, NOT from `@define-color accent_*` in user `gtk.css`. Running apps don't pick up live — accent change requires app restart. By design, not a bug.
- **Screen sharing (video conferencing) requires xdg-desktop-portal-wlr**: `xdg-desktop-portal-gnome` is designed for GNOME sessions and cannot provide the ScreenCast interface on niri. niri implements `wlr-screencopy`, so `xdg-desktop-portal-wlr` must be installed alongside gnome/gtk portals. `config/dms/portals.conf` routes `ScreenCast` and `Screenshot` to the wlr backend while leaving all other interfaces (FileChooser, Settings, etc.) on gnome/gtk — the two backends coexist without conflict. DMS's own `dms screenshot` bypasses the portal entirely (calls grim+slurp directly) and is unaffected.
- **xdg-desktop-portal-wlr requires a chooser config**: without `~/.config/xdg-desktop-portal-wlr/config`, the portal has no way to present a screen/output selector to the user → screen share button in apps appears to do nothing. `config/dms/xdpw.conf` configures `slurp -f %o -or` as the chooser (already installed for DMS screenshots), which shows a click-to-select overlay when an app requests a screencast.
- **Tauri/WebKitGTK apps show black screen**: apps like Yaak use WebKitGTK for rendering. On some GPU drivers (e.g. amdgpu), the DMA-BUF renderer produces a black window. Fix: `WEBKIT_DISABLE_DMABUF_RENDERER=1` in `config/dms/environment.conf`.
- **dms-matugen-init.service exits with code 2 on "no changes"**: DMS returns exit code 2 (`INVALIDARGUMENT`) when matugen runs but detects no color changes. systemd treats this as failure → `ExecStartPost` (self-disable) never runs → service re-runs on every boot. Fix: `SuccessExitStatus=2` in the service unit.
- **starship.tera template at `~/.config/matugen/templates/` can be stale**: `matugen.sh` deploys the template via `copy_config`, but if `matugen.sh` isn't re-run after a repo update, the deployed template stays at the old version. matugen then re-renders dynamic colors on every DMS matugen call, overwriting any manual edits to `~/.config/starship.toml`. Fix: `cp config/matugen/templates/starship.tera ~/.config/matugen/templates/starship.tera` then re-run `matugen --prefer lightness image <wallpaper>`.
- **GRUB matter theme is not idempotent**: `matter.py` (the upstream installer) overwrites `GRUB_THEME` and rebuilds `grub.cfg` on every run. `core/boot.sh` checks `/boot/grub/themes/Matter/` and skips if present.
- **`run_step` LOG_FILE capture must not swallow interactive prompts**: bash `read -rp` writes its prompt to stderr. A plain `2>"$tmpfile"` redirect hides the prompt from the user — interactive scripts (e.g. `setup-user.sh`) appear to hang silently. Fix: use `2> >(tee -a "$tmpfile" >&2)` so the prompt reaches the terminal in real time while still being captured for the log. The old pattern of `cat "$tmpfile" >&2` after the command finishes is useless for prompts because the user needed to see them *before* typing.
- **keyd Caps↔Esc swap makes niri see swapped keysyms**: keyd remaps keys before they reach the compositor. With `capslock=esc` and `esc=capslock`, niri sees Caps_Lock where the user pressed physical Esc, and Escape where the user pressed physical Caps. niri bindings use the post-remap keysym: bind to `Mod+Escape` for the physical Caps key, or `Mod+Caps_Lock` for the physical Esc key. Lock screen is intentionally bound to `Mod+Caps_Lock` (physical Esc) to avoid accidental triggers from the Caps position (which is the primary Esc key for heavy vim users).
- **multicliprelay 四个 service 启动竞态可能永久 dead**: niri 异步启动 socket + `wayland-1` 非默认名 + 默认端口 8080 常被占用。Fix: drop-in 设 `WAYLAND_DISPLAY=wayland-1`、自动找 17000-17999 空闲端口、`RestartSec=5`/`StartLimitBurst=0`。见 `scripts/core/clipboard.sh`。
- **中键粘贴不工作（Wayland PRIMARY 三层断裂）**: multicliprelay 只桥 CLIPBOARD；xwayland-satellite 不桥 PRIMARY；Wayland app 大多不写 PRIMARY（winit 0.30 缺 `set_primary_selection` API；GTK4 非 GNOME 默认关闭；WebKitGTK 独立禁用）。Fix: `primary-sync` daemon 三向打通 CLIPBOARD↔PRIMARY↔X11 PRIMARY + `gtk-enable-primary-paste=true` + `WEBKIT_GTK_ENABLE_PRIMARY_PASTE=1`。见 `scripts/core/clipboard.sh`。
- **`StartLimitBurst`/`StartLimitIntervalSec` 必须在 `[Unit]` 段**: systemd 允许这些键出现在 `[Service]` 下但**静默忽略**，不报任何警告。必须在 `[Unit]` 下才生效。Fix: `primary-sync.service` 的 heredoc 中两个键移到 `[Unit]`。
- **winit 0.30 缺 PRIMARY set API**: Alacritty 选中文字无法写入 Wayland PRIMARY。Workaround: `selection.save_to_clipboard = true` → `primary-sync` daemon 同步到 PRIMARY。
- **Claude Code MCP 配置位置**：`~/.claude.json` 的 `mcpServers` 字段，非 `~/.claude/settings.json`。用 `claude mcp add/remove/list` CLI 操作（`--scope user` → `~/.claude.json`）。改完必须重启 Claude Code 进程。
- **Playwright headless 过不去 CF Turnstile / Google `/sorry/`**：`navigator.webdriver=true` 硬指纹。临时绕过：`--user-data-dir` + headed 手动过 Turnstile 一次，cookies 缓存几天。日常 ~80% 页面 vanilla headless 够用。
- **WeChat (Flatpak) 粘贴文件变成路径文本**: multicliprelay 把 `text/uri-list` 原始字节当 `text/plain` 返回给微信。Fix: `wechat-uri-fix` daemon 检测到文件 URI 时接管 X11 CLIPBOARD，只暴露 file targets（`TARGETS`/`TIMESTAMP`/`text/uri-list`/`x-special/gnome-copied-files`），拒绝 `text/*` → 微信识别为文件粘贴。关键点：`set_selection_owner` 是 Window 方法非 Display；SelectionClear 后 50ms 重 grab；URI 消失时不主动释放（避免空窗）。该 daemon 是微信兼容层，微信迁移 Wayland 后可删（见 Clipboard 模块 §3）。
- **微信 Flatpak 中键粘贴不可用（系统无解）**: 微信 Flatpak 用 `sockets=x11` + `QT_QPA_PLATFORM=xcb`（纯 X11 模式），自定义渲染引擎 RadiumWMPF 不处理中键粘贴事件。这不是权限问题，是微信 Linux 客户端本身不支持 PRIMARY paste。只能用 Ctrl+C/V。
- **QQ (linuxqq-appimage) SIGBUS on Wayland**: Electron GPU sandbox + `memfd` 触发 bus error。AUR desktop 文件有 `--no-sandbox` 但未禁用 GPU sandbox。Fix: `qq.sh` 创建 user-level desktop override 追加 `--disable-gpu-sandbox`。
- **WeChat Flatpak filesystem permissions**: manifest defaults to `filesystems=xdg-download:ro`. `wechat.sh` runs `flatpak override --user --filesystem=home` to grant full home directory access. Note: `flatpak override --reset` must NOT be used — it strips manifest permissions and breaks the app.
- **DMS IPC 不能设置深层嵌套 key**: `dms ipc settings set cursorSettings.niri.hideWhenTyping true` 返回 `SETTINGS_INVALID_KEY`。嵌套较深的对象 IPC 不接受。Workaround: 直接编辑 `settings.json`，下次 DMS 启动生效。
- **DMS Valent 插件 tile 显示"无设备"，但详情面板列出设备（stale ID 死锁）**: `~/.config/DankMaterialShell/plugin_settings.json` 的 `dankKDEConnect.selectedDeviceId` 存了陈旧设备 ID（重新配对手机 / 重装 Valent 都会换新 ID）。Plugin 拿旧 ID 在 `PhoneConnectService.devices` 字典查不到 → `selectedDevice=null` → tile 文案显 "No devices"；而详情面板列**所有** devices → 显示真实设备。auto-select (`DankKDEConnect.qml:64`) 只在 `selectedDeviceId === ""` 时触发，非空但失效就死锁；详情面板里 device item `selectable: deviceIds.length > 1`，单设备时 GUI 点不动。Fix: 把 `selectedDeviceId` 改成 Valent 实测 ID（`busctl --user call ca.andyholmes.Valent /ca/andyholmes/Valent org.freedesktop.DBus.ObjectManager GetManagedObjects`），重启 DMS。光重启 DMS 不够 —— `onDevicesListChanged` 初始信号可能在 plugin 订阅前就发了。

### Path conventions

| Purpose | Path |
|---|---|
| DMS settings | `~/.config/DankMaterialShell/settings.json` |
| DMS state (wallpaper, etc.) | `~/.local/state/DankMaterialShell/` — wallpaper image itself stored at `~/.local/share/wallpapers/` |
| DMS plugins | `~/.config/DankMaterialShell/plugins/` |
| matugen config | `~/.config/matugen/config.toml` (created by `dms setup`) |
| matugen templates (shipped) | `~/.config/matugen/templates/*.tera` ← `config/matugen/templates/` |
| fcitx5 theme | `~/.local/share/fcitx5/themes/Matugen/theme.conf` (matugen output) |
| fcitx5 rime icons | `~/.local/share/icons/hicolor/scalable/apps/fcitx_rime_*.svg` ← `assets/icons/` |
| GTK dynamic colors | `~/.config/gtk-{3,4}.0/dank-colors.css` (DMS auto-generated) |

### First-login service order

```
graphical-session.target
  ├─ dms.service                  (system unit, registers Notifications D-Bus)
  ├─ fcitx5.service               (ours)
  ├─ fcitx5-theme-reload.path     (ours, watches themes/Matugen/theme.conf)
  ├─ dms-initial-settings.service (ours, IPC writes — settings + profile)
  └─ dms-matugen-init.service     (ours, oneshot matugen,
                                   After=dms-initial-settings)
```

`keyd.service` (system unit, started by `keyd.sh`) starts independently before any user session, so key remapping is active even at the TTY/greetd stage.

The two `dms-*-init` services self-disable after first successful run; subsequent dynamic updates (wallpaper change etc.) go through DMS's internal matugen call, which we do not control.

### Why no `dankinstall`

`dankinstall` is DMS's official one-shot provisioning tool. We skip it because it installs `mako` (conflicts with DMS's own notification daemon) and `xfce-polkit` — both unwanted. Trade-off: artifacts dankinstall ships for free (niri binds, etc.) we ship ourselves.

## Clipboard (`scripts/core/clipboard.sh`)

All clipboard logic lives in a single self-contained module. Five subsystems:

```
clipboard.sh
├── 1. multicliprelay (AUR)        → Wayland ↔ X11 CLIPBOARD（含图片+文件URI）
├── 2. primary-sync daemon         → CLIPBOARD ↔ PRIMARY ↔ X11 三向同步
├── 3. wechat-uri-fix daemon       → Wayland 出现 text/uri-list 时接管 X11
│                                    CLIPBOARD，只暴露 file targets，拒绝
│                                    text/* → WeChat 识别为文件粘贴
├── 4. GTK4 gsettings              → gtk-enable-primary-paste = true
└── 5. WebKitGTK environment.d     → WEBKIT_GTK_ENABLE_PRIMARY_PASTE = 1
```

**各 daemon 职责分界:**

| Daemon | 方向 | 协议 |
|---|---|---|
| multicliprelay (4 services) | Wayland CLIPBOARD ↔ X11 CLIPBOARD | `wl_data_device_manager` / X11 atoms |
| primary-sync (1 service) | Wayland CLIPBOARD ↔ Wayland PRIMARY | `wl-paste --watch` (CLIPBOARD + PRIMARY 两个 watcher) |
| primary-sync | Wayland PRIMARY ↔ X11 PRIMARY | XFIXES `SelectSelectionInput` 监听 X11 PRIMARY，xclip 读写 |
| wechat-uri-fix (1 service) | Wayland text/uri-list → X11 CLIPBOARD | `wl-paste --watch` 事件源 + python-xlib selection owner |

三组 daemon 互不依赖——关掉一个不影响其他。

**关键技术点:**
- `primary-sync`：Python event-driven，`select()` 多路复用 2 个 `wl-paste --watch` + XFIXES X11 PRIMARY 监听。`subprocess.run(input=bytes)` 传字节流避免反馈环路。纯文本。
- multicliprelay relay 端口：自动在 17000-17999 找空闲端口（避开 8080 等常用端口）
- niri 用 `wayland-1`（非默认 `wayland-0`），需显式 `WAYLAND_DISPLAY`
- `wechat-uri-fix`：Python daemon + `python-xlib`。`text/uri-list` 出现时接管 X11 CLIPBOARD（`set_selection_owner` 是 Window 方法非 Display；python-xlib 0.33+ 不能用 `SetSelectionOwner` request）。拒绝 `text/*` → 微信识别为文件粘贴。乒乓一回合终结；URI 消失时不主动释放避免空窗。
- TTY 安装不阻塞：6 个 service 全部无 `ExecStartPre`，`Restart=always` 兜底；`StartLimitBurst=0`（且必须在 `[Unit]` 下），Python daemon 内部 retry-loop。

## FlClash config (`scripts/core/flclash.sh`)

FlClash is installed via pacman (`flclash`) and manages the user's proxy subscription. `flclash.sh` does three things:

1. **Profile import**: copies `usb/sub2clash/files/config.yaml` into FlClash's data dir, registers in SQLite with fixed ID.
2. **Activate profile**: sets `currentProfileId` in `shared_preferences.json`.
3. **Persistent rule injection**: adds weather API DIRECT rules (`open-meteo.com`, `nominatim.openstreetmap.org`, `ip-api.com`) to `patchClashConfig.rule` — survives subscription updates.

Key files under `~/.local/share/com.follow.clash/`: `config.yaml` (active, auto-regenerated), `profiles/<id>.yaml` (subscription), `shared_preferences.json` (UI state + overrides). **Never edit `config.yaml` directly** — always modify `patchClashConfig.rule`.

## Proxy config (`usb/sub2clash/`)

`usb/sub2clash/convert.sh` converts a subscription URL into `files/config.yaml` + `files/geoip.metadb`. `lib/proxy.sh` reads from `usb/sub2clash/files/` and patches the YAML (sets `mixed-port`, disables `tun`) via `lib/helpers/patch-mihomo-config.py` before starting mihomo.

## WeChat (Flatpak) — `scripts/apps/wechat.sh`

WeChat 用 Flatpak 版（非 AUR）：AUR 版自定义渲染引擎在 niri 下文字上移，Flatpak 沙盒不受系统 GTK 主题干扰。`wechat.sh` 做 `flatpak override --filesystem=host --filesystem=/tmp`。中文字体由 `03-fonts.sh` 统一处理。

## Software choices worth knowing

- **eza, not lsd**: `lsd` upstream maintenance has slowed; `eza` is the actively-maintained successor with better git integration. Aliases (`ls`/`ll`/`la`/`lt`) use `--icons=auto` for Nerd Font glyphs. Dracula color scheme is provided via `EZA_COLORS` (24-bit RGB) in `zshrc`.
- **gpu-screen-recorder, not wf-recorder**: hardware encoding (VAAPI/NVENC/AMF) keeps CPU usage at 1-3% during recording, vs 30-60% with `wf-recorder`'s software encoding. We use `gsr-toggle` wrapper (Alt+Print), not the gsr-ui GUI (removed — GUI rewrites config on close).
- **keyd, not kanata**: keyd is a system-level daemon (works at TTY/greetd stage, before any user session); minimal INI config (`/etc/keyd/default.conf`). Current config is just caps↔esc swap. Migrate to kanata if/when complex layers (tap-hold, app-specific) become needed.
- **linuxqq-appimage (`scripts/apps/qq.sh`)**: the official QQ Linux (Electron) AppImage via AUR. Tencent stopped updating the deb; the AppImage is the only maintained channel. Electron GPU sandbox causes `SIGBUS` crashes on Wayland/niri — `qq.sh` creates a user desktop override appending `--disable-gpu-sandbox` to the default `--no-sandbox`.
- **`websearch` (本地 SearXNG) + Playwright MCP, not Tavily/Exa**: 自建本地搜索+浏览器栈替代付费 API。`websearch <q>` 调 `~/services/searxng/`（docker compose，host network 走 FlClash 7890）的 JSON API，Brave/Bing/mwmbl/wiby 等抗压性引擎兜底。读 JS-rendered 页面或反爬时用 `mcp__playwright__browser_navigate`（`@playwright/mcp` 用系统 chromium + headless）。覆盖 ~80% 场景；CF Turnstile / Google `/sorry/` 过不去（vanilla headless 暴露 `navigator.webdriver`）。栈见 `scripts/apps/searxng.sh`、`scripts/apps/playwright-mcp.sh`、`scripts/core/docker.sh`。
- **WeChat Flatpak, not AUR**: see `## WeChat (Flatpak)` above.
- **loupe, not eog/gthumb**: GTK4 + libadwaita native image viewer, accent-color aware, minimal startup time vs gthumb's plugin-heavy init.
- **celluloid, not totem/vlc**: mpv GTK4 frontend — inherits mpv's VAAPI/NVENC hardware decoding; totem is unmaintained, vlc ships its own Qt theme clash.
- **gammastep, not redshift**: Wayland-native `wlr-gamma-control` protocol; redshift requires a shim on non-wlroots compositors. Uses geoclue for auto-location.
- **gdu, not ncdu**: Go parallel disk scanner, 5-10× faster than ncdu on SSD. Output format identical.
- **7zip, not p7zip+unrar**: single package covers both 7z and RAR extraction; p7zip is split across `p7zip` (7z) and `unrar` (RAR).

## Temporary scripts

When the user asks me to write a one-shot shell script for the current machine, save it to `tmp/` (repo root, gitignored) with a descriptive prefix (e.g. `tmp/setup-foo.sh`).
