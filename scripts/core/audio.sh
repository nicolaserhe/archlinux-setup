#!/usr/bin/env bash
# =============================================================================
# scripts/core/audio.sh -- PipeWire 音频栈
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# pipewire:       新一代音视频服务器
# pipewire-pulse: PulseAudio 兼容层，让 PA 应用无感切换
# wireplumber:    PipeWire 会话与策略管理器
header "PipeWire packages"
pacman_install pipewire pipewire-pulse wireplumber

# -- 启用用户服务 -------------------------------------------------------------
# unit 文件由 pacman 装到系统路径，无需 daemon-reload 即可 enable
header "PipeWire user services"
for _svc in pipewire pipewire-pulse wireplumber; do
    enable_user_service "$_svc.service"
done
unset _svc

# -- block-source-volume quirk -----------------------------------------------
# Chromium WebRTC AGC 会在通话时接管麦克风增益，导致音量滑块被锁死或乱跳。
# pipewire-pulse 的 block-source-volume quirk 禁止应用修改源音量。
header "PipeWire block-source-volume quirk"
mkdir -p "$HOME/.config/pipewire/pipewire-pulse.conf.d"
copy_config \
    "$REPO_DIR/config/pipewire/10-block-source-volume.conf" \
    "$HOME/.config/pipewire/pipewire-pulse.conf.d/10-block-source-volume.conf"

success "Audio done"
