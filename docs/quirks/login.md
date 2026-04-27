# Login flow (greetd)

`scripts/core/login.sh` 写 `/etc/greetd/config.toml` 一条 `[default_session]`，开机直接走 regreet 选用户输密码，**无 autologin**。

- **`[default_session]`** —— `/usr/local/bin/greetd-wrapper.sh`（regreet → tuigreet fallback），经过 PAM auth。

历史上配过 `[initial_session]` 走 autologin 直进 niri，但叠加 DMS `lockAtStartup: true` 会让 niri 启动后 DMS 立刻锁屏，**先闪 1-2 秒桌面再盖上锁屏**（quickshell 冷启动延迟，race 不可消除）。当前选择：`config/dms/settings.json` 的 `lockAtStartup: false` + 无 autologin —— regreet 登录即 PAM 鉴权，进桌面后不再被锁，无闪屏。

要恢复 autologin 体验：在 `/etc/greetd/config.toml` 末尾追加 `[initial_session] command="niri-session" user="<USER>"`；要让 autologin 后仍自动锁屏，再把 `lockAtStartup` 改回 true（接受闪桌面）。

## Quirks

- **greetd wrapper：regreet 直跑 + tuigreet fallback**：logout 才会看到 greeter（开机走默认 session），wrapper 优先级是「可用 > 美观」。`config/greetd/greetd-wrapper.sh` 直接 `regreet`（不再用 cage 包 wayland nested compositor —— regreet 0.3+ 自带 wayland backend），失败时 `exec tuigreet` 兜底。`greetd-tuigreet` 是 extra repo 包，`login.sh` 装。永远可登录。
