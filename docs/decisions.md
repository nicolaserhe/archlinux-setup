# Software choices

为什么选 A 不选 B —— 一次性选定、想换时复查的简短笔记。详细的踩坑在 [quirks/](quirks/)。

- **eza, not lsd**：`lsd` 上游维护变慢；`eza` 是接力者，git 集成更好。Aliases（`ls`/`ll`/`la`/`lt`）用 `--icons=auto`（Nerd Font）。Dracula 配色由 `EZA_COLORS`（24-bit RGB）在 `zshrc` 提供。
- **gpu-screen-recorder, not wf-recorder**：硬件编码（VAAPI/NVENC/AMF）录制时 CPU 占 1-3%，wf-recorder 软编 30-60%。用 `gsr-toggle` wrapper（Alt+Print），不用 gsr-ui GUI（已移除 —— GUI 关闭时会重写 config）。
- **keyd, not kanata**：keyd 是系统级 daemon（TTY/greetd 阶段就工作，不需要 user session），极简 INI config。当前配置只有 caps↔esc swap。需要复杂层（tap-hold、app-specific）再迁 kanata。
- **linuxqq-appimage（`scripts/apps/qq.sh`）**：官方 QQ Linux（Electron）AppImage，AUR 包装。Tencent 停更 deb，AppImage 唯一 channel。Electron GPU sandbox 在 Wayland/niri 触发 SIGBUS —— `qq.sh` 创建 user desktop override 加 `--disable-gpu-sandbox`。
- **`easy_anysearch_skill` + Playwright MCP, not 本地 SearXNG / Tavily / Exa**：搜索走 Skill（公网 API，零运维，Claude 自动触发）；JS 渲染 / 反爬 / 需要交互时上 `mcp__playwright__browser_navigate`（`@playwright/mcp` 用系统 chromium + headless）。SearXNG 自建栈用过一段（`websearch` wrapper + docker compose），但 Google/CF 按出口 IP 风控，实际抗压性引擎能拿到的东西 anysearch 也能拿到，运维成本不值，2026-05 撤了。
- **WeChat Flatpak, not AUR**：AUR 版自定义渲染引擎在 niri 下文字上移；Flatpak 沙盒不受系统 GTK 主题干扰。见 [quirks/apps.md](quirks/apps.md)。
- **loupe, not eog/gthumb**：GTK4 + libadwaita 原生图片查看器，accent-color 感知，启动时间比 gthumb 插件加载快。
- **celluloid, not totem/vlc**：mpv GTK4 前端 —— 继承 mpv 的 VAAPI/NVENC 硬解；totem 不维护，vlc 自带 Qt 主题冲突。
- **gammastep, not redshift**：Wayland 原生 `wlr-gamma-control` 协议；redshift 在非 wlroots compositor 上需要 shim。用 geoclue 自动定位。
- **gdu, not ncdu**：Go 并行扫描，SSD 上比 ncdu 快 5-10×，输出格式相同。
- **7zip, not p7zip+unrar**：单包同时覆盖 7z 和 RAR；p7zip 拆在 `p7zip`（7z）+ `unrar`（RAR）两个包。
