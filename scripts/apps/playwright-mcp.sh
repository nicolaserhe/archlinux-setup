#!/usr/bin/env bash
# =============================================================================
# scripts/apps/playwright-mcp.sh -- Playwright MCP server for Claude Code
# 单跑：bash scripts/apps/playwright-mcp.sh
#
# 给 Claude Code 提供 headless Chromium，用于读 JS-rendered 页面 / 突破基础反爬。
#
# 覆盖范围：
#   - ✓ JS-rendered SPA / 现代文档站（Anthropic docs, MDN, GitHub 等）
#   - ✓ 普通页面抓取、表单填写、点击交互
#   - ✗ Cloudflare Turnstile（Stack Overflow 等启用 CF 的站点）
#   - ✗ Google 搜索结果页（headless 指纹被 /sorry/ 拦）
#
# Vanilla headless Chromium 的 navigator.webdriver=true 是 CF 主要识别点；
# 真要绕 CF：临时去掉 --headless，把 --isolated 换 --user-data-dir，手动过一次
# Turnstile 后 cookies 缓存够用几天。换 google-chrome 也救不了 webdriver flag。
#
# 拔除：
#   claude mcp remove playwright --scope user
#   npm uninstall -g @playwright/mcp
#   sudo pacman -R chromium  # 若无其他用途
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/pkg.sh"

header "Playwright MCP"

# -- 前置依赖检查 -------------------------------------------------------------
# nodejs/npm 由 01-pacman-base.sh 在 root 层装；apps/ 不重复装
command_exists npm || die "npm 未装。先跑 install.sh，或 sudo pacman -S nodejs npm"
command_exists claude || die "claude CLI 未装。安装 Claude Code 后再跑此脚本"

# -- 系统 Chromium（pacman）---------------------------------------------------
# Playwright 自带 Chrome-for-Testing 下载常被 GH/Azure CDN 限速，国内更糟；
# 用 Arch 仓库的 chromium 包，pacman 管依赖、定期升级、走 pacman 镜像。
pacman_install chromium

# -- @playwright/mcp（npm 用户级 prefix，免 sudo）-----------------------------
NPM_PREFIX="$(npm config get prefix)"
PLAYWRIGHT_MCP_BIN="$NPM_PREFIX/bin/playwright-mcp"

if [[ -x "$PLAYWRIGHT_MCP_BIN" ]]; then
    warn "Already installed, skipping: @playwright/mcp"
else
    # FlClash 端口 7890 在跑 → 自动给 npm 走代理，否则交给 shell env
    if [[ -z "${HTTPS_PROXY:-}" ]] && ss -tln 2>/dev/null | grep -q '127.0.0.1:7890'; then
        export HTTPS_PROXY=http://127.0.0.1:7890
        export HTTP_PROXY=http://127.0.0.1:7890
        info "Detected FlClash 7890, using as npm proxy"
    fi
    info "Installing @playwright/mcp globally"
    npm install -g @playwright/mcp@latest
fi

[[ -x "$PLAYWRIGHT_MCP_BIN" ]] || die "playwright-mcp binary not found at $PLAYWRIGHT_MCP_BIN"

# -- 注册到 Claude Code 用户级 MCP 配置 ---------------------------------------
# 用 `claude mcp` CLI 而非直接改 ~/.claude.json：上游 JSON schema 可能变。
# --scope user 写入 ~/.claude.json 的全局 mcpServers，所有项目都能用。
if claude mcp get playwright &>/dev/null; then
    warn "MCP playwright already registered, skipping"
else
    info "Registering playwright MCP server (user scope)"
    claude mcp add --scope user playwright -- \
        "$PLAYWRIGHT_MCP_BIN" \
        --headless \
        --isolated \
        --executable-path /usr/bin/chromium \
        --proxy-server http://127.0.0.1:7890
fi

success "Playwright MCP done"
info "重启 Claude Code 加载 MCP server（必须完整重启进程）"
