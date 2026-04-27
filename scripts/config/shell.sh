#!/usr/bin/env bash
# =============================================================================
# scripts/config/shell.sh -- Zsh 配置文件、插件、默认 shell
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

header "Zsh config"
copy_config "$REPO_DIR/config/zshrc" "$HOME/.zshrc"

header "Zsh plugins"
ZSH_PLUGIN_DIR="$HOME/.zsh/plugins"
mkdir -p "$ZSH_PLUGIN_DIR"

git_clone "$ZSH_PLUGIN_DIR/zsh-autosuggestions" \
    https://github.com/zsh-users/zsh-autosuggestions

git_clone "$ZSH_PLUGIN_DIR/zsh-history-substring-search" \
    https://github.com/zsh-users/zsh-history-substring-search

# syntax-highlighting 必须最后 source（zshrc 里有说明）
git_clone "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting" \
    https://github.com/zsh-users/zsh-syntax-highlighting

header "Default shell"
_setup_zsh_shell() {
    local zsh_path="/usr/bin/zsh"
    grep -qx "$zsh_path" /etc/shells || sudo sh -c "echo '$zsh_path' >> /etc/shells"

    local current_shell
    current_shell="$(getent passwd "$(whoami)" | cut -d: -f7)"
    if [[ "$current_shell" == "$zsh_path" ]]; then
        warn "Default shell is already zsh, skipping"
    else
        sudo usermod -s "$zsh_path" "$(whoami)"
        success "Default shell set to zsh (re-login to apply)"
    fi
}
_setup_zsh_shell

success "Shell config done"
