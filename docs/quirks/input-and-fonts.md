# Input method / fonts quirks

fcitx5 + rime-ice 输入法、终端字体、CJK/emoji 渲染相关坑。

## Icon cache

- **hicolor user icon cache 需要 `index.theme`**：`gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor/`（`-t` = `--ignore-theme-index`）在没有 `index.theme` 时生成空 cache stub（只 header）。GTK 优先读 cache → 找不到任何图标 → 托盘图标静默消失。Fix：ship 最小 `index.theme` 到 user-level hicolor root 再跑 cache 更新（`fcitx.sh` 已处理）。
- **fcitx5 rime tray icon 需要 short + full name 两套**：fcitx5 请求的图标名是 `org.fcitx.Fcitx5.fcitx_rime_im`（完整反向域名）。只 ship `fcitx_rime_im.svg` 到 hicolor 没用 —— 必须同时 ship `org.fcitx.Fcitx5.fcitx_rime_im.svg`。`fcitx.sh` 部署两种。

## 终端字体

- **Alacritty 字体名 case-sensitive 含空格**：必须 `"Maple Mono NF CN"`（不是 `"maple-mono-nf-cn"`）。错名 → fontconfig fallback 到 Nimbus Sans（比例字体）→ 终端字符叠在一起。

## CJK / emoji fontconfig

- **`noto-fonts-cjk` 和 `noto-fonts-emoji` 不 ship fontconfig 规则**：Arch 上必须手动部署到 `/etc/fonts/conf.d/`：
  - `60-emoji.conf`：前置 Noto Color Emoji（CJK 字体含单色 emoji 字形会遮蔽彩色字体）。
  - `65-cjk-sc.conf`：CJK fallback 顺序（`lang=zh` → prepend strong；其他 → append weak）。
  - `noto-fonts`（拉丁）也必须装 —— 它和 Noto CJK SC 共享垂直度量，避免中英混排时基线偏移。

## starship

- **`starship.toml` palette block 必须放最后**：把 `[palettes.dracula]` 放在 module sections 前面会让 TOML 解析后续 root keys（如 `add_newline`）当作 palette 颜色字符串。永远把 `[palettes.*]` 放文件末尾。
