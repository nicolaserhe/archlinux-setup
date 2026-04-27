#!/bin/bash

# =========================
# 使用说明：
# 1. 通过命令行参数传递订阅链接
# 2. 自动检查 subconverter Docker 容器
# 3. 若不存在则自动创建并启动
# 4. 输出 Clash 配置到 files/config.yaml
# 5. 自动下载 geoip.metadb 到 files/
# =========================

OUTPUT="./files/config.yaml"
FILE_DIR="./files"

CONTAINER_NAME="subconverter"
API="http://127.0.0.1:25500/sub"

GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download/geoip-lite.metadb"

# =========================
# 参数校验（确保提供订阅链接）
# =========================
if [ -z "$1" ]; then
    echo "[❌] 请提供订阅链接"
    echo "用法: ./convert.sh <订阅链接>"
    exit 1
fi

SUB_URL=$1

# =========================
# 确保文件目录存在
# =========================
if [ ! -d "$FILE_DIR" ]; then
    echo "[+] 文件目录不存在，正在创建 $FILE_DIR ..."
    mkdir -p "$FILE_DIR"

    if [ $? -ne 0 ]; then
        echo "[❌] 无法创建目录 $FILE_DIR"
        exit 1
    fi

    echo "[✔] 文件目录 $FILE_DIR 创建成功"
fi

# =========================
# Docker 是否可用
# =========================
docker info >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[❌] Docker 不可用（请检查 Docker 是否启动）"
    exit 1
fi

# =========================
# 检查容器是否存在
# =========================
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[+] 未发现 subconverter 容器，正在创建..."

    docker run -d \
        --name subconverter \
        -p 25500:25500 \
        tindy2013/subconverter

    if [ $? -ne 0 ]; then
        echo "[❌] Docker 容器创建失败，脚本退出"
        exit 1
    fi

    sleep 2
fi

# =========================
# 如果容器没运行则启动
# =========================
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
if [ $? -ne 0 ]; then
    echo "[+] 启动 subconverter 容器..."
    docker start "$CONTAINER_NAME" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "[❌] Docker 启动失败（不处理 Docker 问题，退出）"
        exit 1
    fi
fi

# =========================
# 📦 下载 geoip 数据库
# =========================
echo "[+] 正在下载 geoip 数据库..."

# curl 重试机制（最多重试 3 次）
RETRIES=3
for ((i = 1; i <= RETRIES; i++)); do
    curl -L -s "$GEOIP_URL" -o "$FILE_DIR/geoip.metadb.tmp"

    if [ $? -eq 0 ] && [ -s "$FILE_DIR/geoip.metadb.tmp" ]; then
        mv "$FILE_DIR/geoip.metadb.tmp" "$FILE_DIR/geoip.metadb"
        echo "[✔] geoip.metadb 已保存到 files/"
        break
    else
        echo "[❌] geoip 下载失败，第 $i 次重试..."
        if [ $i -eq $RETRIES ]; then
            echo "[❌] geoip 下载失败，退出"
            exit 1
        fi
    fi
done

# =========================
# 📥 获取订阅链接（已经在最开始校验）
# =========================
# ====== URL encode ======
ENCODED_URL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$SUB_URL'''))")

echo "[+] 正在转换订阅..."

curl -s "$API?target=clash&url=$ENCODED_URL" -o "$OUTPUT"

# ====== 检查结果 ======
if [ -s "$OUTPUT" ]; then
    echo "[✔] 转换成功: $OUTPUT"
    echo "[✔] 文件大小: $(du -h "$OUTPUT" | cut -f1)"
else
    echo "[❌] 转换失败，文件为空"
fi
