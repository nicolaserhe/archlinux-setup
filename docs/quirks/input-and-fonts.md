# Input method / fonts quirks

fcitx5 + rime-ice 输入法、终端字体、CJK/emoji 渲染相关坑。

## Icon cache

- **hicolor user icon cache 需要 `index.theme`**：`gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor/`（`-t` = `--ignore-theme-index`）在没有 `index.theme` 时生成空 cache stub（只 header）。GTK 优先读 cache → 找不到任何图标 → 托盘图标静默消失。Fix：ship 最小 `index.theme` 到 user-level hicolor root 再跑 cache 更新（`fcitx.sh` 已处理）。
- **fcitx5 rime tray icon 需要 short + full name 两套**：fcitx5 请求的图标名是 `org.fcitx.Fcitx5.fcitx_rime_im`（完整反向域名）。只 ship `fcitx_rime_im.svg` 到 hicolor 没用 —— 必须同时 ship `org.fcitx.Fcitx5.fcitx_rime_im.svg`。`fcitx.sh` 部署两种。

## fcitx5 重复拉起

- **自建 systemd unit 不等于屏蔽了 XDG autostart**：`niri.service` 带 `Wants=xdg-desktop-autostart.target`，systemd 的 `systemd-xdg-autostart-generator` 会从 `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop` 生成 `app-org.fcitx.Fcitx5@autostart.service`（`ExecStart=:/usr/bin/fcitx5`，`PartOf=graphical-session.target`）。于是每次登录/会话重启都有**两个** fcitx5，撞上自建 unit 的 `--replace` 互相 SIGTERM。Fix：`~/.config/autostart/org.fcitx.Fcitx5.desktop` 写 `Hidden=true` —— 用户级 autostart 文件按 basename 覆盖系统级，generator 直接跳过。改完必须 `systemctl --user daemon-reload`。
- **`Restart=on-failure` 救不回干净退出**：fcitx5 捕获 SIGTERM 后走正常收尾、以 exit 0 结束，而 `on-failure` 只覆盖非零退出和被信号杀死的情形，所以不会重启它 —— unit 停在 `inactive`（不是 `failed`） —— 输入法就一直死着，表现是"只能打英文"。要 `Restart=always`。代价：托盘或 `fcitx5-remote -e` 主动退出也会在 `RestartSec` 后被拉回；systemd 发起的 `systemctl --user stop` 不受影响，想真停就用它。
- **`--verbose "*"=0` 会让故障无从排查**：它把所有日志级别设成 0，主实例在 journal 里一行都没有。用 `--verbose "default=3"` 留 Warn/Error。（`"*"` 和 `default` 是同一个槽位，后写的赢 —— `"*=0,default=3"` 与 `"default=3"` 等价。）
- **theme-reload 用 `try-restart` 而不是 `restart`**：unit 没在跑时 `try-restart` 是 no-op，不会把不该在跑的 fcitx5 提前拉起来。注意它**不能**防抖 —— 对 `active`/`activating` 的 unit 一样会真重启，matugen 连写多次 `theme.conf` 仍会重启多次（由 `ExecStartPre` 的 `sleep 1` 吸收）。

## 终端字体

- **Alacritty 字体名 case-sensitive 含空格**：必须 `"Maple Mono NF CN"`（不是 `"maple-mono-nf-cn"`）。错名 → fontconfig fallback 到 Nimbus Sans（比例字体）→ 终端字符叠在一起。

## CJK / emoji fontconfig

- **`noto-fonts-cjk` 和 `noto-fonts-emoji` 不 ship fontconfig 规则**：Arch 上必须手动部署到 `/etc/fonts/conf.d/`：
  - `60-emoji.conf`：前置 Noto Color Emoji（CJK 字体含单色 emoji 字形会遮蔽彩色字体）。
  - `65-cjk-sc.conf`：CJK fallback 顺序（`lang=zh` → prepend strong；其他 → append weak）。
  - `noto-fonts`（拉丁）也必须装 —— 它和 Noto CJK SC 共享垂直度量，避免中英混排时基线偏移。

## starship

- **`starship.toml` palette block 必须放最后**：把 `[palettes.dracula]` 放在 module sections 前面会让 TOML 解析后续 root keys（如 `add_newline`）当作 palette 颜色字符串。永远把 `[palettes.*]` 放文件末尾。
