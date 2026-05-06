#!/usr/bin/env bash
# =============================================================================
# usb/sub2clash/convert.sh -- 订阅链接转 Clash YAML 配置
#
# 在另一台主机上运行，产物写入 ./files/，最终拷贝到目标机的 usb/sub2clash/
# 目录被 lib/proxy.sh 读取启动 mihomo。
#
# 用法: ./convert.sh <subscription-url>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

# -- 配置 ---------------------------------------------------------------------
FILE_DIR="$SCRIPT_DIR/files"
OUTPUT="$FILE_DIR/config.yaml"

CONTAINER_NAME="subconverter"
CONTAINER_IMAGE="tindy2013/subconverter"
CONTAINER_PORT=25500
API="http://127.0.0.1:${CONTAINER_PORT}/sub"

GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geoip-lite.metadb"

# -- 参数 ---------------------------------------------------------------------
[[ $# -ge 1 && -n "$1" ]] || die "Usage: $0 <subscription-url>"
SUB_URL="$1"

# -- 工作目录 -----------------------------------------------------------------
mkdir -p "$FILE_DIR"

# -- Docker -------------------------------------------------------------------
docker info >/dev/null 2>&1 \
    || die "Docker is not available -- please make sure the daemon is running"

if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log "Creating subconverter container"
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${CONTAINER_PORT}:${CONTAINER_PORT}" \
        "$CONTAINER_IMAGE" >/dev/null \
        || die "Failed to create container $CONTAINER_NAME"
    sleep 2
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log "Starting existing subconverter container"
    docker start "$CONTAINER_NAME" >/dev/null \
        || die "Failed to start container $CONTAINER_NAME"
fi

# -- geoip 数据库 -------------------------------------------------------------
log "Downloading geoip database"
_download_geoip() {
    # 下载到 .tmp 后再重命名，避免半截文件被 mihomo 误用
    curl -fsSL --max-time 60 "$GEOIP_URL" -o "$FILE_DIR/geoip.metadb.tmp" \
        && [[ -s "$FILE_DIR/geoip.metadb.tmp" ]]
}
if retry 3 3 _download_geoip; then
    mv "$FILE_DIR/geoip.metadb.tmp" "$FILE_DIR/geoip.metadb"
    success "geoip.metadb saved to: $FILE_DIR"
else
    rm -f "$FILE_DIR/geoip.metadb.tmp"
    die "Failed to download geoip database after 3 attempts"
fi

# -- 订阅转换 -----------------------------------------------------------------
log "Converting subscription to Clash YAML"
encoded_url="$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$SUB_URL")"

curl -fsS --max-time 30 "${API}?target=clash&url=${encoded_url}" -o "$OUTPUT" \
    || die "subconverter request failed"

[[ -s "$OUTPUT" ]] || die "Conversion produced an empty file"

success "Conversion successful: $OUTPUT"
log "File size: $(du -h "$OUTPUT" | cut -f1)"
