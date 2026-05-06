#!/usr/bin/env bash
# =============================================================================
# scripts/config/shell.sh -- Zsh 配置文件、插件、默认 shell
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

header "Zsh config"
copy_config "$REPO_DIR/config/shell/zshrc" "$HOME/.zshrc"

header "Zsh plugins"
ZSH_PLUGIN_DIR="$HOME/.zsh/plugins"
mkdir -p "$ZSH_PLUGIN_DIR"

git_clone "$ZSH_PLUGIN_DIR/zsh-autosuggestions" \
    https://github.com/zsh-users/zsh-autosuggestions

git_clone "$ZSH_PLUGIN_DIR/zsh-history-substring-search" \
    https://github.com/zsh-users/zsh-history-substring-search

# syntax-highlighting 必须最后 source（顺序见 zshrc）
git_clone "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting" \
    https://github.com/zsh-users/zsh-syntax-highlighting

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

success "Shell config done"
