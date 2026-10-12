#!/usr/bin/env bash
# =============================================================================
# usb/sub2clash/convert.sh -- 订阅链接转 Clash YAML 配置
#
# 在另一台主机上运行，产物写入 ./files/，最终拷贝到目标机的 usb/sub2clash/
# 目录被 lib/proxy.sh 读取启动 mihomo。
#
# subconverter 容器只公布到 127.0.0.1：它唯一的消费者是本脚本自己下面那条 curl
# （同样走 127.0.0.1），而 subconverter 没有任何鉴权，绑 0.0.0.0 等于把它摆到局域
# 网上，换不来任何东西。已存在但绑在别处的容器会被重建 —— 脚本按名字复用容器，
# 不重建的话改动对那个旧容器毫无效果（镜像换了同理，见下面的重建守卫）。
#
# 订阅 URL 按凭据对待：拿到它就能用你的节点与流量，而 `ps` 对同机所有用户可见。
# 本脚本不把它写进任何命令行参数 —— python 从环境变量读，curl 从 -K 配置文件读，
# 于是 argv 里只剩临时文件名。注意仍会留在你自己的 shell history 里。
#
# 用法: ./convert.sh <subscription-url>
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

# -- 配置 ---------------------------------------------------------------------
FILE_DIR="$SCRIPT_DIR/files"
OUTPUT="$FILE_DIR/config.yaml"

CONTAINER_NAME="subconverter"
# 用 digest 钉住，不写隐式 :latest：这个容器要读订阅、转出来的 YAML 直接进
# mihomo 的网络路径，而 `latest` 的意思是"上游什么时候推新镜像，你下次跑就换了
# 一份代码"。这是 manifest list 的 digest，多架构由 docker 自己挑。
# 升级：docker buildx imagetools inspect tindy2013/subconverter:latest \
#           --format '{{.Manifest.Digest}}'   然后替换下面这行。
CONTAINER_IMAGE="tindy2013/subconverter@sha256:9fd004f00e90a7f67631f4d9a3f435c95b0fe58e7afdce8b8c6ca28c92826632"
CONTAINER_PORT=25500
BIND_ADDR=127.0.0.1
API="http://127.0.0.1:${CONTAINER_PORT}/sub"

GEOIP_RELEASE_BASE="https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download"
GEOIP_ASSET="geoip-lite.metadb"

# -- 参数 ---------------------------------------------------------------------
[[ $# -ge 1 && -n "$1" ]] || die "Usage: $0 <subscription-url>"
SUB_URL="$1"

# -- 工作目录 -----------------------------------------------------------------
mkdir -p "$FILE_DIR"

# -- Docker -------------------------------------------------------------------
docker info >/dev/null 2>&1 ||
    die "Docker is not available -- please make sure the daemon is running"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    # 已存在但公布地址不对（老版本建的容器）就重建：容器按名字复用，留着旧的就等于
    # 这次改动从没发生过。读 PortBindings 配置而不是 `docker port` —— 后者只认运行中
    # 的容器，会把"绑对了但已停"的容器误判成要重建。而老写法 `-p 25500:25500` 在
    # inspect 里是 HostIp=""（不是 "0.0.0.0"），这里显式规范化，免得空串跟"压根没
    # 发布端口"（如 --network host 建的）混成一个值。
    #
    # 镜像同理：容器一旦建好就固定在自己的镜像上，光改上面的 CONTAINER_IMAGE 对
    # 已有容器毫无影响 —— 那正是"钉了 digest 却还在跑老镜像"这种最难发现的假钉。
    # .Config.Image 回的就是当初 `docker run` 收到的那个字符串，可以直接比。
    _published="$(docker inspect -f \
        '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{if .HostIp}}{{.HostIp}}{{else}}0.0.0.0{{end}}:{{.HostPort}}{{end}}{{end}}' \
        "$CONTAINER_NAME" 2>/dev/null || true)"
    _image="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    if [[ "$_published" != "${BIND_ADDR}:${CONTAINER_PORT}" ]]; then
        warn "Recreating $CONTAINER_NAME: published on '${_published:-none}', want ${BIND_ADDR}:${CONTAINER_PORT}"
        docker rm -f "$CONTAINER_NAME" >/dev/null
    elif [[ "$_image" != "$CONTAINER_IMAGE" ]]; then
        warn "Recreating $CONTAINER_NAME: built from '${_image:-unknown}', want '$CONTAINER_IMAGE'"
        docker rm -f "$CONTAINER_NAME" >/dev/null
    fi
    unset _image
fi

if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log "Creating subconverter container"
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${BIND_ADDR}:${CONTAINER_PORT}:${CONTAINER_PORT}" \
        "$CONTAINER_IMAGE" >/dev/null ||
        die "Failed to create container $CONTAINER_NAME"
    sleep 2
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log "Starting existing subconverter container"
    docker start "$CONTAINER_NAME" >/dev/null ||
        die "Failed to start container $CONTAINER_NAME"
fi

# -- geoip 数据库 -------------------------------------------------------------
log "Downloading geoip database"

# 落盘名保持 geoip.metadb（不是上游的 geoip-lite.metadb）：lib/proxy.sh 按这个名字
# 找它并部署进 mihomo 配置目录。校验是拿哈希值直接比，文件名对不上不影响。
_geoip_out="$FILE_DIR/geoip.metadb"
_geoip_sum="$_geoip_out.sha256sum.tmp"

# 为什么没有 URL 层面的版本钉：上游只有一个 tag，名字就叫 `latest`，每次发版
# 强制移动它（`git ls-remote --tags` 只回这一个；release 标题就是"Release
# 2026-10-12 09:28"这种时间戳，一天重发好几次）。也就是说 checksum 与文件之间
# **没有**"同一次发布"的 URL 保证，唯一的办法是把"下载 + 校验"当成一个整体去
# 重试：串版本时这一轮校验就失败，下一轮重新取两份。
_download_geoip() {
    local want got

    # 都下到 .tmp：半截文件被 mihomo 当数据库读会得到一堆莫名其妙的规则失败
    curl -fsSL --proto '=https' --proto-redir '=https' --max-time 60 \
        "$GEOIP_RELEASE_BASE/$GEOIP_ASSET" -o "$_geoip_out.tmp" || return 1
    curl -fsSL --proto '=https' --proto-redir '=https' --max-time 30 \
        "$GEOIP_RELEASE_BASE/$GEOIP_ASSET.sha256sum" -o "$_geoip_sum" || return 1
    [[ -s "$_geoip_out.tmp" && -s "$_geoip_sum" ]] || return 1

    want="$(awk 'NR==1{print $1}' "$_geoip_sum")"
    got="$(sha256sum "$_geoip_out.tmp" | awk '{print $1}')"

    if [[ ! "$want" =~ ^[0-9a-f]{64}$ ]]; then
        warn "geoip checksum asset is not a sha256sum file -- retrying"
        return 1
    fi
    if [[ "$want" != "$got" ]]; then
        warn "geoip checksum mismatch (want ${want:0:12}..., got ${got:0:12}...) -- upstream may have republished mid-download"
        return 1
    fi
    return 0
}

if retry 3 3 _download_geoip; then
    mv "$_geoip_out.tmp" "$_geoip_out"
    rm -f "$_geoip_sum"
    # 说清楚这层校验证明了什么：checksum 也走同一条 HTTPS 从上游拿，防不住上游
    # 被投毒；它拦的是传输截断、CDN 混进旧版本、以及"下回来一页 HTML 错误页"
    # —— 这些正是原先只判 `-s`（非空）时漏掉的。而 files/ 里这份最终会被 proxy.sh
    # 原样部署给 mihomo，是长期在用的资产。
    success "geoip.metadb saved to: $FILE_DIR (sha256 verified)"
else
    rm -f "$_geoip_out.tmp" "$_geoip_sum"
    die "Failed to download + verify the geoip database after 3 attempts"
fi

# -- 订阅转换 -----------------------------------------------------------------
log "Converting subscription to Clash YAML"

# 两条路都不让订阅 URL 进 argv：
#   python —— 从环境变量读（/proc/<pid>/environ 只有属主和 root 能读，argv 是全局可读）
#   curl   —— 用 -K 配置文件（mktemp 默认 0600），命令行上只剩文件路径
# 编码仍用 quote() 的默认 safe（不编码 "/"）：query 里 "/" 是合法字符，且这是
# 一直在跑的写法，没有理由顺手改动它。
encoded_url="$(SUB_URL="$SUB_URL" python3 -c \
    'import os, urllib.parse; print(urllib.parse.quote(os.environ["SUB_URL"]))')"

_curl_cfg="$(mktemp -t sub2clash-curl.XXXXXX)"
trap 'rm -f "$_curl_cfg"' EXIT
{
    printf 'url = "%s?target=clash&url=%s"\n' "$API" "$encoded_url"
    printf 'output = "%s"\n' "$OUTPUT"
    printf 'fail\nsilent\nshow-error\nmax-time = 30\n'
} >"$_curl_cfg"

curl -K "$_curl_cfg" || die "subconverter request failed"

[[ -s "$OUTPUT" ]] || die "Conversion produced an empty file"

success "Conversion successful: $OUTPUT"
log "File size: $(du -h "$OUTPUT" | cut -f1)"
