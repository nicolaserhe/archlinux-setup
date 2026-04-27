#!/usr/bin/env bash
# =============================================================================
# scripts/apps/searxng.sh -- 本地 SearXNG 元搜索 + websearch wrapper
# 单跑：bash scripts/apps/searxng.sh
#
# 部署：
#   ~/services/searxng/docker-compose.yml  ← config/searxng/docker-compose.yml
#   ~/services/searxng/settings.yml        ← config/searxng/settings.yml（secret 替换）
#   ~/.local/bin/websearch                 ← config/helpers/searxng/websearch
#
# 容器用 host network，搜索引擎请求出口走 FlClash 127.0.0.1:7890（settings.yml
# 里 outgoing.proxies 配死）。监听 127.0.0.1:8888，纯本机。
#
# 拔除：
#   cd ~/services/searxng && docker compose down
#   rm -rf ~/services/searxng ~/.local/bin/websearch
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"

header "SearXNG"

# -- 前置依赖 -----------------------------------------------------------------
command_exists docker || die "docker 未装。先跑 bash scripts/core/docker.sh"
command_exists jq || die "jq 未装。先跑 bash scripts/core/docker.sh"
docker compose version &>/dev/null || die "docker compose 子命令不可用。先跑 bash scripts/core/docker.sh"

SEARXNG_DIR="$HOME/services/searxng"
mkdir -p "$SEARXNG_DIR"

# -- compose 文件 -------------------------------------------------------------
copy_config "$REPO_DIR/config/searxng/docker-compose.yml" "$SEARXNG_DIR/docker-compose.yml"

# -- settings.yml（首次生成随机 secret_key，已存在则保留）---------------------
if [[ -f "$SEARXNG_DIR/settings.yml" ]] && grep -q 'secret_key:' "$SEARXNG_DIR/settings.yml" \
   && ! grep -q '__SECRET_KEY__' "$SEARXNG_DIR/settings.yml"; then
    warn "settings.yml 已存在，保留当前 secret_key"
else
    SECRET_KEY="$(openssl rand -hex 32)"
    sed "s/__SECRET_KEY__/$SECRET_KEY/" "$REPO_DIR/config/searxng/settings.yml" > "$SEARXNG_DIR/settings.yml"
    success "Generated settings.yml with fresh secret_key"
fi

# -- websearch wrapper --------------------------------------------------------
mkdir -p "$HOME/.local/bin"
install -m755 "$REPO_DIR/config/helpers/searxng/websearch" "$HOME/.local/bin/websearch"
success "Installed ~/.local/bin/websearch"

# -- 启动容器 -----------------------------------------------------------------
# 用户加进 docker 组后，**当前 shell 不会立即生效**（fork 时机问题）。
# 同次 install.sh 流程里 user-phase 仍然在 pre-add-to-group 的环境，所以
# 用 sudo 兜底。手动单跑（用户已经 re-login）走原生 docker。
DOCKER_CMD=(docker)
if ! id -nG "$USER" | grep -qw docker; then
    warn "$USER 还没在 docker 组生效（首次 install 后需 re-login），改用 sudo docker"
    DOCKER_CMD=(sudo docker)
fi

info "Starting SearXNG container"
if (cd "$SEARXNG_DIR" && "${DOCKER_CMD[@]}" compose up -d 2>&1 | tail -5); then
    success "SearXNG container up at http://127.0.0.1:8888"
else
    error "docker compose up failed (镜像拉取慢的话过几分钟手动重跑)"
fi

success "SearXNG done"
