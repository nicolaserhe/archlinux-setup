#!/bin/bash
# greetd 登录包装脚本
# regreet（图形界面）优先；任何环节失败 fallback 到 tuigreet（字符界面）
# 确保用户永远可登录。greetd autologin 启用后这个 wrapper 只在 logout
# 之后才会被看到，因此朴素的 tuigreet 也够用。
#
# 进程生命周期：greetd 在 greeter IPC 提交成功后会主动 kill 本进程，
# 所以 success path 不需要显式 exit；exec tuigreet 是 fallback path。
set -o pipefail

REASONS_FILE="/tmp/regreet-fallback-reason.txt"

if command -v regreet &>/dev/null; then
    regreet 2>/tmp/regreet-errors.log
    ret=$?
    if [[ $ret -ne 0 ]]; then
        echo "regreet exit code $ret, falling back to tuigreet" > "$REASONS_FILE"
        tail -5 /tmp/regreet-errors.log >> "$REASONS_FILE" 2>/dev/null
    fi
else
    echo "regreet not found, falling back to tuigreet" > "$REASONS_FILE"
fi

exec /usr/bin/tuigreet --cmd niri-session --time --remember --asterisks
