#!/usr/bin/env bash
# =============================================================================
# scripts/apps/ai/agent-stack.sh -- AI 工具套件（clone → install → cleanup）
# 单跑：bash scripts/apps/ai/agent-stack.sh
#
# 从 nicolaserhe/agent-stack 临时 clone，执行 bash install 后清理。
# 所有 AI 工具（cc-switch、Playwright MCP 等）统一由 agent-stack 管理。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

header "agent-stack"

AGENT_STACK_URL="https://github.com/nicolaserhe/agent-stack.git"
WORK_DIR="$(mktemp -d --suffix=.agent-stack)"

trap 'rm -rf "$WORK_DIR"' EXIT

info "Cloning $AGENT_STACK_URL"
git clone --depth 1 "$AGENT_STACK_URL" "$WORK_DIR"

info "Running install"
bash "$WORK_DIR/install.sh"

trap - EXIT
rm -rf "$WORK_DIR"

success "agent-stack done"
