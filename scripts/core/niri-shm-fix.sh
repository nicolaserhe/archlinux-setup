#!/usr/bin/env bash
# =============================================================================
# scripts/core/niri-shm-fix.sh -- SHM screencast 补丁（niri 26.04）
#
# 为 niri 26.04 添加 PipeWire SHM 回退支持，修复腾讯会议/飞书等 Electron
# WebRTC 应用的屏幕共享黑屏问题。
#
# 基于 niri PR #1791（wrvsrx），额外修复了上游补丁的 chunk.size bug。
# 上游合入后可删除此脚本，portal 配置直接切 gnome 即可。
#
# 幂等：检测已安装的 niri 二进制是否为 SHM 修复版，是则跳过。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

NIRI_COMMIT="8ed0da44d974c32c6877d2f4630c314da0717ecb"
NIRI_VERSION="26.04"
PATCH_URL="https://github.com/wrvsrx/niri/compare/tag_support-shm-sharing_4~19..tag_support-shm-sharing_4.patch"
BUILD_DIR="/tmp/niri-shm-build"
MARKER_FILE="$HOME/.local/share/niri-shm/installed-commit"

# -- 幂等检查 -------------------------------------------------------------------
# 检测已安装的二进制是否包含 SHM 修复（通过 commit 标记文件判断）
if [[ -f "$MARKER_FILE" ]]; then
    _installed_commit="$(cat "$MARKER_FILE")"
    if [[ "$_installed_commit" == "$NIRI_COMMIT" ]]; then
        success "niri SHM fix already installed (commit ${NIRI_COMMIT:0:7})"
        exit 0
    fi
    info "niri SHM fix outdated ($_installed_commit) → rebuilding ($NIRI_COMMIT)"
fi
unset _installed_commit

header "niri SHM patch ($NIRI_VERSION)"

# -- 编译依赖 -------------------------------------------------------------------
# rust 已在 pacman-base.sh 安装；clang 是 niri 编译依赖
pacman_install clang

# -- 下载源码 + 打补丁 ----------------------------------------------------------
info "Cloning niri source (${NIRI_COMMIT:0:7})..."
rm -rf "$BUILD_DIR"
git clone --depth 1 https://github.com/niri-wm/niri.git "$BUILD_DIR" 2>/dev/null
(
    cd "$BUILD_DIR"
    git fetch --depth 1 origin "$NIRI_COMMIT" 2>/dev/null
    git checkout "$NIRI_COMMIT" 2>/dev/null

    info "Applying SHM patch..."
    curl -sSL "$PATCH_URL" -o /tmp/niri-shm.patch
    git am -3 /tmp/niri-shm.patch 2>/dev/null
    rm -f /tmp/niri-shm.patch

    info "Fixing chunk.size bug (PR #1791 upstream: chunk.size=1 → shmbuf.size)..."
    sed -i 's/(\*chunk)\.size = 1;/(*chunk).size = shmbuf.size as u32;/' \
        src/screencasting/pw_utils.rs

    # 确认 sed 生效
    if ! grep -q 'shmbuf.size as u32' src/screencasting/pw_utils.rs; then
        die "sed fix failed — chunk.size line not patched"
    fi
    success "chunk.size fix applied"

    # -- 编译 -------------------------------------------------------------------
    header "Compiling niri with SHM support (this takes ~10 minutes)"
    cargo build --release

    # -- 替换二进制 -------------------------------------------------------------
    info "Replacing /usr/bin/niri..."
    if [[ -f /usr/bin/niri ]]; then
        # 运行中的 niri 不能被直接覆盖，删旧建新
        sudo rm -f /usr/bin/niri
    fi
    sudo cp target/release/niri /usr/bin/niri
    sudo chmod 755 /usr/bin/niri

    # -- 写标记 -----------------------------------------------------------------
    mkdir -p "$(dirname "$MARKER_FILE")"
    echo "$NIRI_COMMIT" > "$MARKER_FILE"
)

success "niri SHM patch installed — restart your session to apply"
