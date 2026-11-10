# 网络 quirks（双网卡 / DHCP / mDNS 名字）

本机有线 `enp11s0` 和无线 `wlp12s0` 同时接在同一个网段，两边（含 Windows 对端）全部 DHCP，
不写静态地址。跨机访问一律用 mDNS 名字：Windows 访问 `\\archlinux.local\Shared`，
Linux 访问对端用 `win.local`。

## 默认路由：谁先激活谁优先

两条默认路由的网关相同，NetworkManager 会给后激活的那条 **+20000 metric 惩罚**。
有线 profile 因此显式钉 `ipv4.route-metric=100`（无线保持自动，约 600）：插着网线时
默认走有线，拔掉后自动落到无线，不需要手工切。

## ARP flux 与 ACD 误判

Linux 默认会从任意网卡应答 ARP。双网卡同网段时，NetworkManager 的 ACD（地址冲突
检测）会把本机另一张网卡的应答误判成"IP 冲突"，把刚拿到的 DHCP 地址 decline 掉，
连默认路由一起撤掉 —— 表现是"有地址但上不了网"。

修法：`config/sysctl/90-multihome-arp.conf`（`arp_ignore=1` + `arp_announce=2`），由
`system-services.sh` 部署到 `/etc/sysctl.d/`，重启后仍在。

路由器 DHCP 还有一个坏状态：地址被 decline 之后，它可能持续 OFFER 同一地址，但对带
`Server-ID` 的 REQUEST 一律回 NACK（DHCP message "Invalid Request Message"），约 30
分钟才过期。这期间反复重连没用，等过期（或临时换 MAC）即可。

## `.local` 名字解析

- **Windows → Linux**：Windows 自带 mDNS，`\\archlinux.local\Shared` 不需要 Linux 侧配置。
- **Linux → Windows**：需要 `nss-mdns` + `/etc/nsswitch.conf` 的 hosts 行带
  `mdns_minimal [NOTFOUND=return]`（`system-services.sh` 部署这两样）。没有它
  `getent hosts win.local` / `ping win.local` 会失败，只有 `avahi-resolve` 能查。
- `.local` 是 mDNS 保留域名，`NOTFOUND=return` 让查不到时直接失败，不回退 DNS。

## Clash TUN 的 fake-IP 会劫持裸主机名

Mousehop 的 client 写 `hostname = "win"`（不带 `.local`）时，名字不走 mDNS，而是落到
系统 DNS；FlClash/mihomo 的 TUN 对域名先回一个 **fake-IP**（本机是 28.x 段），该地址被
路由进 `FlClash` 设备，局域网里的 Windows 收不到。表现是 Mousehop 启动时先连一次
注定失败的地址，随即用 `last_addr`（对端真实地址，Mousehop 自己记录）连上，功能不受
影响，只是日志里多一次失败拨号。

想省掉这次拨号：在**运行时** `~/.config/mousehop/config.toml` 的 `[[clients]]` 里填
`ips = ["192.168.3.15"]`。这是机器本地状态（对端 DHCP），不进仓库 seed —— seed 保持
`ips = []`，新机器靠 mDNS 发现 + `last_addr` 回退；对端换 IP 时这里跟着改。

不用清 DNS 缓存也不用加静态路由：fake-IP 是 TUN 的正常机制，清了会重新生成。真要
在源头规避，只能在 FlClash 的 `fake-ip-filter` 里排除 `win` / `*.local`，收益不大。

## mDNS 名字冲突

avahi 和 Mousehop 内嵌的 mdns-sd 都可能想占 `archlinux.local`。Mousehop 争不过时会
自行退让成 `archlinux-N.local`，只影响 SRV target，服务实例名（`archlinux`）不变。
反过来如果 avahi 被抢先改名成 `archlinux-2.local`，SMB 名字会跟着变 —— 重启
`avahi-daemon` 就能拿回 `archlinux.local`。Mousehop 服务广播里带 `(2)!` 后缀是旧实例
留下的缓存幽灵，TTL 到期自己消失。
