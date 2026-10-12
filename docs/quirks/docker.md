# Docker quirks

`scripts/core/docker.sh` 装 `docker` + `docker-compose` + `docker-buildx` + `jq`，部署 `/etc/docker/daemon.json`（只写日志上限），enable/start `docker.service`，把用户加进 `docker` 组（记得 `newgrp docker` 或重新登录）。**包选择理由**写在那个脚本的头部注释里；这里只记会咬人的操作事实。

## 镜像存储：containerd image store，"`/var/lib/docker` 是空的"是假象

`docker info` 报 `Storage Driver: overlayfs` + `driver-type: io.containerd.snapshotter.v1` —— 本机（dockerd 29.8.2，包版本见下节）默认启用 **containerd image store**：镜像层归 containerd 管，落在 `/var/lib/containerd` 下；`/var/lib/docker` 只剩 daemon 自己的状态（卷、容器元数据、网络）。

- **`du -sh /var/lib/docker` 给出的数是假的**：该目录 `0710 root:root`，`/var/lib/containerd` 是 `0700 root:root`，普通用户 `du` 两个都只报 `4.0K` 外加一行 `Permission denied` —— 那 4.0K 是"读不进去"，不是"没占盘"。
- 要问真实占用用 **`docker system df`**（不需要 root）：本机实测 27 个镜像 11.94 GB（其中 9.77 GB 可回收）、卷 3 个 328.8 MB、build cache 近空。清不清、清多少，看这一条输出就够，别去 `du` 那两个只有 root 能读的目录。
- 于是"看看 `/var/lib/docker` 多大"这个下意识动作在这里会给出完全错误的结论 —— 镜像空间全在 containerd 那边。

## dockerd 会落后于包版本

`pacman -Q docker` 是 `1:29.9.0-1`，`docker version` 却是 client 29.9.0 / **server 29.8.2**：pacman 升级只换文件，不重启服务，所以 dockerd 还在跑旧二进制。本机实测就是这么来的 —— `docker.service` 的 `ActiveEnterTimestamp`（09:45:41）早于 docker 包的 `Install Date`（09:47:12）。

判断"某个默认值 / 特性在不在"必须以 `docker info` / `docker version` 报的 **server** 为准，别拿包版本推断。

重启要挑时候：`Live Restore Enabled: false`，`systemctl restart docker` 会连带杀掉正在跑的容器（`--restart unless-stopped` 的会在 daemon 起来后自动回来，临时 `docker run` 的不会）。

## 日志上限：`/etc/docker/daemon.json` 只对新容器生效

`docker.sh` 从 2026-10-12 起部署 `/etc/docker/daemon.json`（`json-file` + `max-size 10m` / `max-file 3`，即每容器 30MB 封顶）。原先的判断是"低频用法够不上日志轮转那类事故"，实测不成立 —— 本机 `goldtrading-valkey` 连续跑了两小时，`goldtrading-pg` 是停了 13 天的长期项目容器，而 json-file driver 默认**无上限**。

两个生效时点，都比直觉晚：

- daemon.json 只在 **dockerd 启动**时读 —— 文件落盘不等于生效，`systemctl restart docker` 才读。
- log-opts 还要再晚一步：它是**建容器时**快照进容器的。验证一行：`docker inspect -f '{{json .HostConfig.LogConfig}}' <容器>`，本机两个容器现在都是 `{"Type":"json-file","Config":{}}`（空 Config = 无上限）。要吃到上限只能重建容器（`docker rm -f` + 原来的 `docker run` / `compose up -d`）。

所以 `docker.sh` 刻意**不**重启 dockerd：`Live Restore Enabled: false`，restart 会连带杀掉在跑的容器（见上一节）。已在跑的容器日志要清就 `sudo truncate -s0 /var/lib/docker/containers/*/*-json.log`（日志文件路径由 `docker inspect -f '{{.LogPath}}'` 给出，目录 0710 root，普通用户读不到）。

不用 `local` driver 的原因也在这两个时点上：换 driver 同样只对新容器生效，结果是老容器 json-file、新容器二进制 local 的格式分裂；这个量级下 `local` 的性能优势约等于零，`json-file` + 上限保住了 `docker logs` 的可读性。`registry-mirrors` 不加 —— 理由见 [decisions.md](../decisions.md)。

## 发布端口绕过主机防火墙

`-p` 发布的端口走 iptables **nat 表的 PREROUTING DNAT**，转发进容器的流量**不经过 `filter`/`INPUT`**。两件事叠加就是个洞：主机没开防火墙 + 容器绑 `0.0.0.0` = 该端口直接暴露在 LAN 上；而且**事后补一个基于 `filter` 链的防火墙也拦不住**（DNAT 在它前面）。能限住它的只有三条路：绑 `127.0.0.1`（首选）、在 `DOCKER-USER` 链里写规则、或者干脆不 `-p`。

本机 2026-10-12 按这条清理过：`goldprice-mysql`（3306）停用删除，`goldtrading-valkey`（6379）从 `-p 6379:6379` 改成 `-p 127.0.0.1:6379:6379`。`goldtrading-pg` 仍是 `-p 5432:5432`，但容器已停（13 天），处于不监听状态 —— 它一旦被启动就又是 0.0.0.0。同类改动见 [apps.md](apps.md) 里 `usb/sub2clash/convert.sh` 的 subconverter 容器。

### 陷阱：`-p 5432:5432` 的 `HostIp` 是空串，不是 `0.0.0.0`

`docker inspect -f '{{json .HostConfig.PortBindings}}'` 对没写 host IP 的 `-p 5432:5432` 给的是：

```
{"5432/tcp":[{"HostIp":"","HostPort":"5432"}]}
```

`HostIp` 是 **`""`** —— 空串在 Docker 里表示"所有接口"。所以任何"这个容器是不是只绑回环"的字符串比较，都必须先把空串规范化成 `0.0.0.0`，否则它和"压根没发布端口"的容器（`PortBindings` 为 `{}`，例如 `--network host` 建的）会混成同一个值。`docker port` 给的是规范化后的 `0.0.0.0:5432`，但它**只认运行中的容器**，对已停的容器报 `no public port ... published`。`usb/sub2clash/convert.sh` 的重建守卫因此直接读 `PortBindings` 并显式补 `0.0.0.0`（同一个守卫还比 `.Config.Image`：容器一旦建好就固定在自己的镜像上，光把 `docker run` 的镜像换成 digest，已有容器照样跑旧的）。
