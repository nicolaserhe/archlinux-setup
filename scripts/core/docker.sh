#!/usr/bin/env bash
# =============================================================================
# scripts/core/docker.sh -- Docker daemon + compose/buildx 子命令 + jq
#
# 用 docker-compose 包 = 同时提供 standalone 命令和 CLI plugin。后者注册到
# /usr/lib/docker/cli-plugins/docker-compose 让 `docker compose` 子命令可用。
# 仓库内所有 compose 调用统一用 `docker compose`（子命令形式）。
# docker-buildx 同理提供 `docker buildx`，装它的理由见下面的包注释。
#
# 落 /etc/docker/daemon.json（2026-10-12 加，反转了原先"不加"的判断）。原来写的
# 理由是"偶尔 build 镜像 + 两个开发容器，够不上日志轮转那一类事故" —— 实测本机
# 不是这个用法：`goldtrading-valkey` 连续跑了两小时（`goldtrading-pg` 是停了 13 天
# 的长期项目容器），而 json-file driver 默认**无上限**，这类容器挂几周就能把
# /var/lib/docker 吃到几十 GB（真实占用看 `docker system df`，目录本身读不进去 ——
# 见 docs/quirks/docker.md）。
#
# 只写两件事：log-driver=json-file + max-size=10m / max-file=3（每容器封顶 30MB）。
#   - 不换 `local` driver：它更省（按 20m×5 默认轮转、二进制格式），但**换 driver
#     只对新容器生效**，本机已有的两个容器是 json-file，混着来等于日志格式分裂；
#     json-file + 上限保住了 `docker logs` 的可读性与格式一致性，这个量级下 local
#     的性能优势约等于零。
#   - 不加 registry-mirrors / 其余常被抄进来的键（containerd snapshotter、iptables、
#     storage-driver、data-root）：后者在这台 dockerd（29.8.2，`docker info` 实测）
#     上**已经是默认值**，写一遍只会让后来的人以为改过什么；前者的理由见
#     docs/decisions.md（国内 Docker Hub 公共镜像基本关停，本机走代理可达）。
#
# 生效时机（两个坑，见 docs/quirks/docker.md）：daemon.json 只在 dockerd 启动时读；
# log-opts 还要再晚一步 —— 它是**建容器时**快照进容器的，所以已在跑的容器
# （`docker inspect -f '{{json .HostConfig.LogConfig}}'` 显示 `Config: {}`）重建才
# 吃得到。脚本刻意**不**重启 dockerd：`Live Restore Enabled: false`，
# `systemctl restart docker` 会连带杀掉正在跑的容器。对新机器没这个问题 ——
# 配置在 `systemctl start` 之前就位。
#
# 注意：把用户加进 docker 组后，**当前 shell 不会立即生效**。需要重新登录
# 或 `newgrp docker`。
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

header "Docker"

# docker:         daemon + CLI
# docker-compose: 提供 docker compose 子命令的 plugin + standalone 命令
# docker-buildx:  提供 docker buildx；也是 `docker build` 走 BuildKit 的前提。
#                 不装的话 `docker build` 只能用 legacy builder（Docker 29 已经
#                 打上 "will be removed in a future release" 的弃用横幅），而
#                 DOCKER_BUILDKIT=1 docker build 会直接报 "BuildKit is enabled
#                 but the buildx component is missing or broken"。BuildKit 本身
#                 编在 dockerd 里，所以不需要再装独立的 buildkit 包。
# jq:             搜 wrapper / 各种 JSON 处理用
pacman_install docker docker-compose docker-buildx jq

# -- 日志上限（/etc/docker/daemon.json）---------------------------------------
# 部署在启动服务**之前**：新机器上 dockerd 第一次起来就带着这份配置。
install_config_root \
    "$REPO_DIR/config/docker/daemon.json" \
    /etc/docker/daemon.json 644

# 已经在跑 dockerd 的机器上这份配置还没被读进去（要重启 daemon），而且已在跑的
# 容器不吃 log-opts（建容器时快照的）—— 重启会杀容器，所以只提示、不代劳。
if systemctl is-active --quiet docker.service; then
    info "daemon.json is not live yet: dockerd reads it at startup, and running containers"
    info "keep the log config they were created with (Live Restore is off, so a restart kills them)."
fi

# -- 启用 / 启动 daemon -------------------------------------------------------
enable_system_service docker.service
_as_root systemctl start docker.service 2>/dev/null || true

# -- 加用户进 docker 组（免 sudo 调 docker）-----------------------------------
add_user_to_group "$USER" docker

success "Docker done"
