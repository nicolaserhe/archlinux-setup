# Application quirks

按应用聚合：WeChat / QQ / Tauri & WebKitGTK / Playwright MCP / Claude Code MCP / FlClash / Proxy。

## WeChat (Flatpak) — `scripts/apps/wechat.sh`

WeChat 用 Flatpak 版（非 AUR）：AUR 版自定义渲染引擎在 niri 下文字上移，Flatpak 沙盒不受系统 GTK 主题干扰。`wechat.sh` 做 `flatpak override --user --filesystem=host --filesystem=/tmp` —— host 覆盖外置盘（`/run/media`）和其他挂载点，`/tmp` 单列因为 host 不含 `/tmp`。中文字体由 `fonts.sh` 统一处理。

- **Filesystem permissions**：manifest 默认 `filesystems=xdg-download:ro`。`flatpak override --reset` **不能用** —— 会剥掉 manifest 里的 `sockets`/`devices`，应用直接坏掉。
- **粘贴文件变成路径文本**：见 [clipboard.md](clipboard.md) 里 file_only mode 那条。
- **中键粘贴不可用（系统无解）**：见 [clipboard.md](clipboard.md)。

## QQ — `scripts/apps/qq.sh`

linuxqq-appimage（AUR，Electron AppImage）。Tencent 停更 deb，AppImage 是唯一在维护的 channel。

- **SIGBUS on Wayland**：Electron GPU sandbox + `memfd` 共享内存触发 bus error。AUR desktop 文件有 `--no-sandbox` 但不覆盖 GPU sandbox。Fix：`qq.sh` 创建 user-level desktop override 追加 `--disable-gpu-sandbox`（同名 desktop 文件，user-level 优先于 system-level）。

## Tauri / WebKitGTK

- **黑屏**：Yaak 等用 WebKitGTK 渲染。某些 GPU 驱动（如 amdgpu）的 DMA-BUF renderer 出黑窗口。Fix：`WEBKIT_DISABLE_DMABUF_RENDERER=1` 在 `config/dms/environment.conf`。

## AI 工具套件 — `scripts/apps/ai/agent-stack.sh`

> 不在 `user-phase.sh` 的 `APP_SCRIPTS` 默认列表里。按需 `bash scripts/apps/ai/agent-stack.sh` 单跑。所有 AI 工具（cc-switch、Playwright MCP 等）统一由 [agent-stack](https://github.com/nicolaserhe/agent-stack) 管理，clone 到 /tmp → `bash install` → 清理。

## Claude Code MCP

- **MCP 配置位置**：`~/.claude.json` 的 `mcpServers` 字段，**非** `~/.claude/settings.json`。用 `claude mcp add/remove/list` CLI 操作（`--scope user` → `~/.claude.json`）。改完必须**完整重启** Claude Code 进程。

## FlClash — `scripts/core/flclash.sh`

FlClash 由 pacman（`flclash`）装，管理用户的代理订阅。`flclash.sh` 做四件事：

1. **Profile import**：copies `usb/sub2clash/files/config.yaml` into FlClash 数据目录，SQLite 写一条固定 ID 的 profile 记录。
2. **Activate profile**：`shared_preferences.json` 设 `currentProfileId`。
3. **Silent autostart**：`appSettingProps` 写 `autoLaunch=true`（XDG autostart desktop file）+ `silentLaunch=true`（启动不弹窗，只待命托盘）+ `autoRun=true`（启动后自动开代理核心）。三个开关都在 `flutter.config.appSettingProps`，对应 GUI 里"开机自启/静默启动/自启代理"。
4. **Persistent rule injection**：通过 `patchClashConfig.rule` 注入天气 API DIRECT 规则（`open-meteo.com`、`nominatim.openstreetmap.org`、`ip-api.com`）—— 跨订阅更新仍保留。

Key files under `~/.local/share/com.follow.clash/`：`config.yaml`（active，自动重生成）、`profiles/<id>.yaml`（subscription）、`shared_preferences.json`（UI state + overrides）。**不要直接编辑 `config.yaml`** —— 永远改 `patchClashConfig.rule`。

## Proxy bootstrap — `usb/sub2clash/` + `lib/proxy.sh`

`usb/sub2clash/convert.sh` 把订阅 URL 转成 `files/config.yaml` + `files/geoip.metadb`。`lib/proxy.sh` 从 `usb/sub2clash/files/` 读，并通过 `lib/helpers/patch-mihomo-config.py` 修补 YAML（设 `mixed-port`、禁 `tun`）后启 mihomo。
