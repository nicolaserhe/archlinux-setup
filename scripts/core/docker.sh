#!/usr/bin/env bash
# =============================================================================
# scripts/core/docker.sh -- Docker daemon + compose 子命令 + jq
#
# 用 docker-compose 包 = 同时提供 standalone 命令和 CLI plugin。后者注册到
# /usr/lib/docker/cli-plugins/docker-compose 让 `docker compose` 子命令可用。
# 仓库内所有 compose 调用统一用 `docker compose`（子命令形式）。
#
# 注意：把用户加进 docker 组后，**当前 shell 不会立即生效**。需要重新登录
# 或 `newgrp docker`。同一次 install.sh 跑里启动的 user-phase 也看不见 docker
# 组，所以 apps/searxng.sh 里有 sudo docker compose 兜底逻辑。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

header "Docker"

# docker:           daemon + CLI
# docker-compose:   提供 docker compose 子命令的 plugin + standalone 命令
# jq:               搜 wrapper / 各种 JSON 处理用
pacman_install docker docker-compose jq

# -- 启用 / 启动 daemon -------------------------------------------------------
enable_system_service docker.service
sudo systemctl start docker.service 2>/dev/null || true

# -- 加用户进 docker 组（免 sudo 调 docker）-----------------------------------
add_user_to_group "$USER" docker

success "Docker done"
