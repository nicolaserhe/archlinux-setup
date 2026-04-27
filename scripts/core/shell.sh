#!/usr/bin/env bash
# =============================================================================
# scripts/core/shell.sh -- 命令行工作区：Zsh + Neovim + Alacritty + CLI 工具
# =============================================================================

set -euo pipefail

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

# -- AUR 包 -------------------------------------------------------------------
# maple-mono-nf-cn: Alacritty 等宽字体（含中文 + Nerd Font 图标）
header "Terminal font (AUR)"
aur_install maple-mono-nf-cn

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
        sudo sh -c "echo '$zsh_path' >> /etc/shells"
    fi

    current_shell="$(getent passwd "$user" | cut -d: -f7)"
    if [[ "$current_shell" == "$zsh_path" ]]; then
        warn "Default shell is already zsh, skipping"
    else
        sudo usermod -s "$zsh_path" "$user"
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
install -Dm755 "$REPO_DIR/config/helpers/dms/brightness" "$HOME/.local/bin/dms-brightness"

# -- Claude Code --------------------------------------------------------------
header "Claude Code"
export PATH="$HOME/.local/bin:$PATH"
if command_exists claude; then
    warn "Claude Code already installed, skipping"
else
    curl -fsSL https://claude.ai/install.sh | bash
    success "Claude Code installed"
fi

success "Shell workspace done"
