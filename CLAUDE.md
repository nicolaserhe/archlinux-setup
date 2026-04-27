# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Automated post-install setup for a personal Arch Linux desktop (niri + DankMaterialShell). Run once on a freshly installed system; not idempotent in the sense of being safe to re-run arbitrarily, but most steps skip gracefully if already done.

## Running the installer

```bash
# Live ISO 内："无脑"步骤（镜像源 + 微码自检 + pacstrap + fstab + 拷 chroot 脚本）
# 分区/格式化/挂载/chroot/最后 umount 自己手动，避免误抹盘
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
- Set `DEEPSEEK_API_KEY` in `~/.zshrc` (the zshrc ships an empty `export DEEPSEEK_API_KEY=""`). Required for nvim minuet-ai ghost text completion (`<A-y>` to accept).

## Repository layout

The codebase has three layers, reflecting **when** the script runs:

- **`usb/`** — bootstrap before the OS exists。`install-base.sh`（CN 镜像+微码+pacstrap+genfstab，不碰分区/mount/chroot）+ `in-chroot.sh`（chroot 内零参数全交互：bootloader 菜单/时区/locale/hostname）+ `sub2clash/`（独立订阅转换器）。**所有输出 ASCII 英文**（live ISO 无 CJK 字体）
- **`scripts/core/`** — system layer (compositor, shell, login, audio, input method...). Rarely changes. Run sequentially by `install.sh` in user-phase.
- **`scripts/apps/`** — application layer (Chrome, WeChat, QQ, Yaak, ...). Frequently installed/uninstalled. Each script is **self-contained** and can be run alone via `bash scripts/apps/<name>.sh`.

Package source (pacman / AUR / Flatpak) is **not** a directory — each module manages its own dependencies via `lib/pkg.sh` helpers.

## Two-phase architecture

`install.sh` runs as **root** and delegates user-level work via `runuser`:

```
install.sh (root)
├── scripts/preflight.sh            # 0. assets + 通知 daemon 冲突早 fail
├── scripts/setup-user.sh           # 1. create/select TARGET_USER
├── scripts/core/pacman-base.sh     # 2. pacman base packages + archlinuxcn
├── [sudo setup + mihomo proxy]     # 3-4
├── [enable linger + chown repo]    # 5-6
└── scripts/user-phase.sh (TARGET_USER)   # 7
    ├── proxy_start                          # mihomo bring-up via lib/proxy.sh
    ├── scripts/core/aur-bootstrap.sh     # yay
    ├── scripts/core/fonts.sh             # 字体基础设施
    ├── scripts/core/flatpak-init.sh      # Flathub remote
    ├── scripts/core/compositor.sh           # niri + xwayland + portals
    ├── scripts/core/login.sh                # greetd + regreet + tuigreet
    ├── scripts/core/audio.sh                # PipeWire stack
    ├── scripts/core/system-services.sh      # bluetooth + avahi + power-profiles
    ├── scripts/core/docker.sh               # docker + compose 子命令 + jq
    ├── scripts/core/shell.sh                # zsh + neovim + alacritty + ...
    ├── scripts/core/dms.sh                  # DMS + GTK theming
    ├── scripts/core/matugen.sh              # must run AFTER dms.sh
    ├── scripts/core/fcitx.sh                # fcitx5 + rime-ice
    ├── scripts/core/keyd.sh                 # keyd key remapping
    ├── scripts/core/kdeconnect.sh           # must run AFTER dms.sh
    ├── scripts/core/clipboard.sh            # X11 ↔ Wayland clipboard 桥
    ├── scripts/core/flclash.sh              # FlClash + subscription import
    ├── scripts/core/boot.sh                 # GRUB matter theme
    └── scripts/apps/{*,ai/*}.sh             # 由 user-phase.sh 的显式 APP_SCRIPTS 数组驱动（AI 相关脚本归 apps/ai/）；agent-stack 不在默认列表，需要时 `bash scripts/apps/ai/agent-stack.sh` 单跑

WeChat 已从 Flatpak 切到 AUR（wechat-bin + wechat + portable）。Flatpak 沙箱阻止 XSetSelectionOwner 导致复制不可用。
```

Proxy (mihomo) 装在 step 4，由 trap EXIT 卸载 —— 退出后系统上不留。

**Cleanup**：所有清理都由 `install.sh` 的 `_cleanup`（trap EXIT）以 root 跑。子脚本**不要**自设 cleanup trap —— root-owned 文件（如 `sudo python3 matter.py` 产生的 root `__pycache__`）在非 root 进程的 `rm -rf` 下会被 `set -e` 打断。唯一例外是 `user-phase.sh` 的 `_on_exit`（stop mihomo + print summary）。`/tmp` 临时目录被 `_clean_tmp_state`（pre-flight）和 `_cleanup`（post-install）双重清理：`rm -rf /tmp/yay-build.* /tmp/rime-ice.* /tmp/dms-plugins.* /tmp/grub-matter.*`。

## Package placement: root vs user

`pacman-base.sh`（root）vs `shell.sh`（user）。**没有重复** —— 每个包只在一处。系统级基础设施和语言运行时 → root；有偏好的开发工具和版本管理器 → user。Gotchas：`tree-sitter-cli`（**不是** `tree-sitter`）；`fnm`/`yarn` 在 extra repo（不在 AUR）；nvim 需要 `python bootstrap.py` after clone。

**子脚本不要"兜底"重装 base 已经列过的包**（imagemagick / expect / curl 等）：base 是权威，本机出现某个 base 包缺失是历史人工卸载导致，不该让每个调用方背防御性 `pacman_install`。要补就在 base 里补，要修就修本机。

## Shared libraries (`lib/`)

每个脚本 source 自己需要的；每个库用 `_*_LOADED` 防双重 source。

| File | Exports |
|---|---|
| `lib/utils.sh` | `info/success/warn/error/header/die`, `retry`, `run_step`, `print_summary`, `ensure_xdg_runtime_dir`；source 时自动安装 ERR trap（调用方 `set -Eeuo pipefail` 即生效） |
| `lib/fs.sh` | `setup_sudo`, `git_clone`, `copy_config`, `find_asset`, `add_user_to_group`, `append_block_once`（往 file 末尾追加 stdin 内容，按 marker 子串幂等） |
| `lib/pkg.sh` | `pacman_install`, `pacman_remove`, `aur_install`, `flatpak_install`（install helpers 跳已装；`pacman_remove` 跳未装）。**内置 `sudo`**：root 阶段透传无害、user-phase 必备；不要再写 `sudo pacman -S` |
| `lib/svc.sh` | `enable_system_service`, `enable_user_service`, `add_user_service_wants`, `switch_display_manager`, `write_user_unit`/`write_user_dropin`（stdin → `~/.config/systemd/user/<unit>` 或 `<unit>.d/<file>`） |
| `lib/proxy.sh` | `proxy_start`, `proxy_stop`（**必须 source**，不能 exec —— 把 env vars export 到调用方）。常量拆在同级 `lib/proxy-const.sh`，install.sh 只需要 PID/LOG 文件路径时可单独 source 它 |
| `lib/helpers/*.py` | 子脚本调用的独立 Python helpers：`patch-mihomo-config.py`（YAML port/tun 修补）、`merge-json-deep.py`（DMS settings merge）、`matugen-strip-template-block.py`（matugen config.toml block 切除）、`flclash-upsert-profile.py` + `flclash-patch-prefs.py`（FlClash SQLite/prefs 写入） |

**Key conventions:**
- 所有 log 写 **stderr**；stdout 保持干净便于 `$()` 捕获（如 `TARGET_USER="$(bash scripts/setup-user.sh)"`）
- `run_step "label" cmd` 包任何 step：log header、跟踪 pass/fail、退出时 print summary；stdout+stderr 都进 `$LOG_FILE`
- 所有 .sh 用 `set -Eeuo pipefail` —— `-E` 让 `lib/utils.sh` 的 ERR trap 在子函数里也生效，失败时打印 `source:line: 'cmd' (exit N)`
- user-phase 脚本里的系统级操作走 `sudo`（`install.sh` 装临时 NOPASSWD 规则、trap 删除）
- 单 app 重跑（`bash scripts/apps/<name>.sh`）**不依赖** install-tmp NOPASSWD，按需弹密码框
- **Lint**：仓库根 `.shellcheckrc` 配好规则集，提交前跑 `find install.sh scripts/ lib/ usb/ -name '*.sh' | xargs shellcheck` 应为 CLEAN。`shellcheck` 已加进 `pacman-base.sh` 的 Dev tools 段

## Ordering constraints

- `aur-bootstrap.sh` → 任何装 AUR 的模块：`login.sh`, `shell.sh`, `dms.sh`, `kdeconnect.sh`, 多数 `apps/*.sh` 调 `aur_install` 需要 yay
- `flatpak-init.sh` → 任何 Flatpak 应用：注册 Flathub remote，`flatpak_install` 前必须
- `fonts.sh` → 任何带 CJK/emoji 的应用：部署系统 fontconfig + Flatpak fontconfig override；在 `aur-bootstrap.sh` 后跑（用 sudo 写 `/etc/fonts/conf.d/`）
- `dms.sh` → `matugen.sh`：matugen 覆盖 DMS 生成的 `config.toml` 里的 `[templates.*]`；先跑 matugen 没有可覆盖的内容
- `dms.sh` → `kdeconnect.sh`：`kdeconnect.sh` 是 DMS plugin 装载器；`dms.sh` 写所有 niri `config.kdl` 内容（含 Valent `spawn-at-startup`）；`kdeconnect.sh` 只装 plugin + `environment.d` 配置，**不碰** `config.kdl`
- `usb/sub2clash/convert.sh` → `flclash.sh`：`flclash.sh` 读 `usb/sub2clash/files/config.yaml`，转换脚本必须先跑

## See also

详情拆到 `docs/`：

- [docs/config-map.md](docs/config-map.md) —— `config/` 各文件到部署目标的完整映射
- [docs/decisions.md](docs/decisions.md) —— Software choices（eza vs lsd、gpu-screen-recorder vs wf-recorder、keyd vs kanata 等）
- [docs/quirks/dms.md](docs/quirks/dms.md) —— DMS / matugen / portals / GTK / Valent 插件相关坑
- [docs/quirks/clipboard.md](docs/quirks/clipboard.md) —— 剪贴板 unified daemon、file_only mode、MIME 校验
- [docs/quirks/input-and-fonts.md](docs/quirks/input-and-fonts.md) —— fcitx5 / rime icon cache / Alacritty 字体 / Noto fontconfig / starship palette
- [docs/quirks/login.md](docs/quirks/login.md) —— greetd / autologin / lockAtStartup race
- [docs/quirks/apps.md](docs/quirks/apps.md) —— WeChat / QQ / Tauri / WebKit / Playwright / Claude Code MCP / FlClash / Proxy
- [docs/quirks/system.md](docs/quirks/system.md) —— keyd / boot / system services / `run_step` 行为

## Portal backend: gnome with SHM niri

**当前推荐方案**：gnome portal + SHM niri。

niri 的 PipeWire screencast 只支持 DMA-BUF。腾讯会议/飞书（Electron/Chromium WebRTC）无法消费纯 DMA-BUF 流，需用 niri PR #1791 的 SHM 回退补丁。

**注意**：上游补丁（PR #1791，wrvsrx）的 `mark_buffer_after_render()` 有一个 bug——SHM 分支里 `chunk.size = 1`，导致消费者只读 1 字节（黑屏）。需改为 `chunk.size = shmbuf.size as u32`。详情见 [[niri-screencast]]。

**portal 配置**（`config/dms/portals.conf`）：
```ini
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=gnome
org.freedesktop.impl.portal.Screenshot=gnome
```

**niri config 需加 portal 重启 spawn**（等 niri ScreenCast D-Bus 就绪后重启 gnome portal）：
```
spawn-at-startup "sh" "-c" "while ! busctl --user status org.gnome.Mutter.ScreenCast >/dev/null 2>&1; do sleep 0.2; done; pkill -f xdg-desktop-portal-gnome"
```

**AUR `niri-shm-sharing` 不可直接用**：makepkg strip 步骤处理大 Rust 二进制会产空文件，需手动 `cargo build --release` + `cp`。

**恢复原版**：`sudo pacman -S niri`

## Temporary scripts

When the user asks me to write a one-shot shell script for the current machine, save it to `tmp/` (repo root, gitignored) with a descriptive prefix (e.g. `tmp/setup-foo.sh`).
