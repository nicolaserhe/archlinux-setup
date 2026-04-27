#!/usr/bin/env bash
# =============================================================================
# scripts/apps/wechat.sh -- 微信（Flatpak）
# 单跑：bash scripts/apps/wechat.sh
#
# AUR 版 wechat-appimage / wechat-bin 在 niri + DMS 下有文字上移 bug
#（自定义渲染引擎兼容性问题），Flatpak 版无此问题。
#
# 中文字体修复由 core/03-flatpak-init.sh 统一处理（全局 flatpak override）。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

APP_ID="com.tencent.WeChat"

header "WeChat (Flatpak)"
flatpak_install "$APP_ID"

# -- Flatpak 权限覆盖：文件访问 -------------------------------------------
# Manifest 默认 filesystems=xdg-download:ro，只读，微信保存文件会失败。
# 追加可写权限：download、pictures、desktop。
# 注意：不 reset —— manifest 里的 sockets/devices 等必须保留。
header "WeChat Flatpak overrides"
flatpak override --user "$APP_ID" \
    --filesystem=host \
    --filesystem=/tmp

success "WeChat done"
