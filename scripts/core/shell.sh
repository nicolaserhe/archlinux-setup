#!/usr/bin/env bash
# =============================================================================
# scripts/core/shell.sh -- 命令行工作区：Zsh + Neovim + Alacritty + CLI 工具
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"

# -- Shell & 终端 -------------------------------------------------------------
header "Shell & terminal"
pacman_install \
    zsh \
    alacritty \
    eza \
    starship \
    fzf

# -- 编辑器 --------------------------------------------------------------------
header "Editor"
pacman_install \
    neovim \
    tree-sitter-cli

# -- Node.js -------------------------------------------------------------------
header "Node.js"
pacman_install \
    fnm \
    yarn

# -- CLI 工具 ------------------------------------------------------------------
header "CLI utilities"
pacman_install \
    duf \
    fd \
    zoxide \
    ripgrep \
    bat \
    tldr \
    fastfetch \
    github-cli

cargo install du-dust --locked

# -- 等宽字体（archlinuxcn）----------------------------------------------------
# Maple Mono NF CN：Alacritty 等宽字体（含中文 + Nerd Font 图标）。
# 走 archlinuxcn 的 ttf-maplemono-nf-cn 而不是 AUR 的 maple-mono-nf-cn：
# AUR 那个包（2 票，DawnMagnet，最后更新 2025-07-25）跟着上游仓库
# github.com/subframe7536/maple-mono-nf，而该仓库已经 404（上游合并进
# subframe7536/maple-font），所以它停在 7.4-0；archlinuxcn 跟主仓库走，现为
# 7.9-1（= 上游最新稳定版 V7.9）。
# 换源前核对过字体元数据（下载 7.9 的包、fc-query 比对）：family 仍是
# "Maple Mono NF CN"，16 个字重的 family/style 名逐个一致 —— alacritty.toml 按
# family + style 指定字体，任何一个名字变了都会静默掉到 fallback。
header "Terminal font (archlinuxcn)"
pacman_install ttf-maplemono-nf-cn

# -- AUR 包 -------------------------------------------------------------------
# devtoolbox: 开发者工具箱（正则/JSON/Base64/UUID/时间戳等离线工具）
aur_install devtoolbox

# parabolic: yt-dlp 图形前端（视频/音频下载）
aur_install parabolic

# -- Zsh 配置 -----------------------------------------------------------------
header "Zsh config"
copy_config "$REPO_DIR/config/shell/zshrc" "$HOME/.zshrc"

# -- Zsh 插件 -----------------------------------------------------------------
header "Zsh plugins"
ZSH_PLUGIN_DIR="$HOME/.config/zsh/plugins"
mkdir -p "$ZSH_PLUGIN_DIR"

git_clone "$ZSH_PLUGIN_DIR/zsh-autosuggestions" \
    https://github.com/zsh-users/zsh-autosuggestions

git_clone "$ZSH_PLUGIN_DIR/zsh-history-substring-search" \
    https://github.com/zsh-users/zsh-history-substring-search

# syntax-highlighting 必须最后 source（顺序见 zshrc）
git_clone "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting" \
    https://github.com/zsh-users/zsh-syntax-highlighting

# -- 默认 shell ---------------------------------------------------------------
header "Default shell"
_setup_zsh_shell() {
    local zsh_path="/usr/bin/zsh" current_shell user
    user="$(whoami)"

    if ! grep -qx "$zsh_path" /etc/shells; then
        echo "$zsh_path" | _as_root tee -a /etc/shells >/dev/null
    fi

    current_shell="$(getent passwd "$user" | cut -d: -f7)"
    if [[ "$current_shell" == "$zsh_path" ]]; then
        warn "Default shell is already zsh, skipping"
    else
        _as_root usermod -s "$zsh_path" "$user"
        success "Default shell set to zsh (re-login to apply)"
    fi
}
_setup_zsh_shell

# -- Neovim 配置 --------------------------------------------------------------
header "Neovim config"
git_clone "$HOME/.config/nvim" https://github.com/nicolaserhe/nvim
(cd "$HOME/.config/nvim" && python bootstrap.py)

# -- Alacritty 配置 -----------------------------------------------------------
header "Alacritty config"
copy_config \
    "$REPO_DIR/config/alacritty/alacritty.toml" \
    "$HOME/.config/alacritty/alacritty.toml"
copy_config \
    "$REPO_DIR/config/alacritty/dracula.toml" \
    "$HOME/.config/alacritty/dracula.toml"

# -- Helper scripts -----------------------------------------------------------
header "Helper scripts"
install_config "$REPO_DIR/config/helpers/dms/brightness" "$HOME/.local/bin/dms-brightness" 755
install_config "$REPO_DIR/config/helpers/git-health" "$HOME/.local/bin/git-health" 755
install_config "$REPO_DIR/config/helpers/gsr-toggle" "$HOME/.local/bin/gsr-toggle" 755

# -- Claude Code --------------------------------------------------------------
header "Claude Code"
export PATH="$HOME/.local/bin:$PATH"
if command_exists claude; then
    warn "Claude Code already installed, skipping"
else
    # 上游没有为 install.sh 发布校验和或签名（下载下来的二进制才由安装器自己
    # 校验），所以这里能做的只有三件事：不 pipe to bash（先落盘、失败可留着查）、
    # 失败即停（`-f`，HTTP 4xx/5xx 返回的错误页不会被当成脚本执行）、以及不让
    # 传输层被降级 —— `--proto '=https' --proto-redir '=https'` 连重定向里的
    # http 都拒掉，`--tlsv1.2` 兜住老 TLS。
    _claude_installer="$(mktemp /tmp/claude-install.XXXXXX.sh)"
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 \
        https://claude.ai/install.sh -o "$_claude_installer"
    bash "$_claude_installer"
    rm -f "$_claude_installer"
    unset _claude_installer
    success "Claude Code installed"
fi

# cc-switch: Claude Code 模型/供应商切换（archlinuxcn，非 AUR —— 它是 repo 包，
# 用 pacman_install 表达"来源是官方/第三方仓库"，别让 yay 兜圈子）
pacman_install cc-switch

success "Shell workspace done"
