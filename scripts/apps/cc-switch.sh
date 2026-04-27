#!/usr/bin/env bash
# =============================================================================
# scripts/apps/cc-switch.sh -- cc-switch 大模型 API 配置切换器（AUR）
# 单跑：bash scripts/apps/cc-switch.sh
#
# 状态栏式快捷工具，用于在多个 Claude Code API 配置间切换。
#
# 替代方案（如果不想装这个工具，可以用纯 shell 函数实现）：
#
#   # 把以下函数放进 zshrc：
#   cc-switch() {
#       local profile="$1"
#       ln -sf "$HOME/.claude/profiles/${profile}.json" "$HOME/.claude/settings.json"
#   }
#
#   # 用法：cc-switch openai     # 切到 ~/.claude/profiles/openai.json
#   #       cc-switch anthropic  # 切到 ~/.claude/profiles/anthropic.json
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "cc-switch"
aur_install cc-switch-bin

success "cc-switch done"
