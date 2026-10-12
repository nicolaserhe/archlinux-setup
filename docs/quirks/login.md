# Login flow (greetd)

`scripts/core/login.sh` 把 `config/greetd/config.toml` 部署到 `/etc/greetd/config.toml`，里面只有一条 `[default_session]`，开机直接走 regreet 选用户输密码，**无 autologin**。配置文件归仓库所有（`install_config_root`），脚本只负责把仓库文件部署过去。

- **`[default_session]`** —— `/usr/local/bin/greetd-wrapper.sh`（regreet → tuigreet fallback），经过 PAM auth。

历史上配过 `[initial_session]` 走 autologin 直进 niri，但叠加 DMS `lockAtStartup: true` 会让 niri 启动后 DMS 立刻锁屏，**先闪 1-2 秒桌面再盖上锁屏**（quickshell 冷启动延迟，race 不可消除）。当前选择：`lockAtStartup` 保持 false + 无 autologin —— regreet 登录即 PAM 鉴权，进桌面后不再被锁，无闪屏。**这个 false 不需要声明**：DMS spec 里 `lockAtStartup` 的默认值就是 `false`，而声明成默认值的键 DMS 落盘时会跳过（见 [dms.md](dms.md)），所以 `config/dms/settings.json` 故意不写它。

要恢复 autologin 体验：把 `config/greetd/config.toml` 末尾那段 `[initial_session]` 注释取消（`user` 改成你的登录名），重跑 `bash scripts/core/login.sh`；要让 autologin 后仍自动锁屏，往 `config/dms/settings.json` 加回 `"lockAtStartup": true` 并重跑 `dms.sh`（`true` ≠ 默认值，所以这一条会真的落盘），接受闪桌面。改仓库文件而不是改 `/etc` 下的副本 —— 后者下次跑 install 就没了，前者还会被 `just drift` 盯着。

## Quirks

- **greetd wrapper：regreet 直跑 + tuigreet fallback**：logout 才会看到 greeter（开机走默认 session），wrapper 优先级是「可用 > 美观」。`config/greetd/greetd-wrapper.sh` 直接 `regreet`（不再用 cage 包 wayland nested compositor —— regreet 0.3+ 自带 wayland backend），失败时 `exec tuigreet` 兜底。`greetd-tuigreet` 是 extra repo 包，`login.sh` 装。永远可登录。
