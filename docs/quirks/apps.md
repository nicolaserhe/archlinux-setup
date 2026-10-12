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

转换用的 subconverter 容器**只公布到 `127.0.0.1`**：subconverter 自己不鉴权，而它唯一的消费者是脚本里那条同机的 curl。脚本按容器名复用，所以它启动时会先 `docker inspect` 已存在容器的 `PortBindings` 和 `.Config.Image`，两者任一与期望不符（绑在别处 —— 老版本建的、或 `--network host` 建的；或镜像不是当前钉的那份）就 `docker rm -f` 重建 —— 不重建的话，改了 `-p` 或换了镜像都会对旧容器毫无效果。

镜像用 **digest** 钉（`tindy2013/subconverter@sha256:…`，manifest list，多架构自动适配），不用隐式 `:latest`：这个容器读的是订阅，产出的 YAML 直接进 mihomo 的网络路径，"上游什么时候推新镜像"不该决定你下次跑的是哪份代码。升级方式写在 `convert.sh` 的注释里（`docker buildx imagetools inspect … --format '{{.Manifest.Digest}}'`）。

### tun 归 FlClash，bootstrap 的 mihomo 这辈子不碰 tun

两条路径不要混：

- **bootstrap（安装窗口）**：`patch-mihomo-config.py` 把 `tun:` 整段**删掉**（建 tun 设备要 CAP_NET_ADMIN，安装期没有特权），顺手把 `redir-port`/`tproxy-port` 注释掉、把 `allow-lan` 强制成 `false`。这份 `~/.config/mihomo/config.yaml` 是**临时物**：`install.sh` 的 `_cleanup` 会停 mihomo、卸包（除非装之前就有），并把配置目录还原成装之前的样子（原本没有就删掉）。所以**没有任何"把 tun 恢复回去"的步骤** —— 文件本身不存活，也不需要恢复。
- **持久态**：FlClash 自带核心与提权通道（`/usr/lib/flclash/FlClashCore` + `FlClashHelperService`，配 `flclash-helper.service`，unit 描述就是"starts the FlClash Core with the privileges TUN mode needs"）。TUN 是它在自己那份自动重生成的 `~/.local/share/com.follow.clash/config.yaml` 里开的（本机实测 `tun: {enable: true, device: "FlClash", stack: mixed}`，`ip link` 里 `FlClash` 设备 UP，helper 服务 active）。

于是"谁在管 tun"这个问题的答案是 FlClash 的 GUI 开关（`flclash.sh` 只写 `autoRun` 等三个启动开关，不碰 tun），而 `~/.config/mihomo/config.yaml` 那份配置即使在安装后残留，也和正在跑的代理无关。

另外两处：订阅 URL 当凭据对待，**不进任何 argv**（python 从环境变量读，curl 用 `-K` 配置文件，文件是 `mktemp` 的 0600）—— 否则 `ps` 里同机用户都能看到；`geoip.metadb` 用 release 提供的 `.sha256sum` 校验（上游只有一个 tag `latest` 且被强制移动，所以"下载 + 校验"整体放进 `retry`，串版本时这一轮失败、下一轮重取）。
