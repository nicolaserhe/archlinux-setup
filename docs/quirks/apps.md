# Application quirks

按应用聚合：Tauri & WebKitGTK / Playwright MCP / Claude Code MCP / FlClash / Proxy。

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
