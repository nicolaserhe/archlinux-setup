#!/usr/bin/env bash
# =============================================================================
# scripts/apps/wechat.sh -- 微信（AUR wechat，非沙箱模式）
# 单跑：bash scripts/apps/wechat.sh
#
# Flatpak 版剪贴板复制不可用（沙箱阻止 XSetSelectionOwner），改用 AUR wechat。
# 中文字体修复由 core/fonts.sh 统一处理。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "WeChat (AUR)"
aur_install wechat-bin
aur_install wechat
aur_install portable
success "WeChat done — run 'wechat.sh' to start"
