#!/usr/bin/env bash
# =============================================================================
# scripts/core/samba.sh -- Samba 共享（Windows 文件交换）
# =============================================================================

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/pkg.sh"
source "$REPO_DIR/lib/svc.sh"

# -- 包安装 -------------------------------------------------------------------
# samba 依赖 smbclient，装服务端时一并带上。
header "Samba package"
pacman_install samba

# -- 配置 ---------------------------------------------------------------------
# 配置用 %H/%U 按连接用户解析，不写死用户名。/etc/samba/smb.conf 归 root，
# 每次 install 覆盖；改了本机这份就等于漂移。
header "Samba config"
install_config_root \
    "$REPO_DIR/config/samba/smb.conf" \
    /etc/samba/smb.conf 644

# -- 共享目录 -----------------------------------------------------------------
# 只在首次创建时设 700，重跑 install 不覆盖用户后来改的权限。
if [[ ! -d "$HOME/Shared" ]]; then
    mkdir -p "$HOME/Shared"
    chmod 700 "$HOME/Shared"
    success "Created $HOME/Shared"
fi

# -- Samba 账号 ---------------------------------------------------------------
# smbpasswd 必须交互输入密码，仓库不保存密码。账号不存在时只提示，不让 install
# 失败 —— smbd 可以先起来，补完密码即可连接。
if _as_root pdbedit -L 2>/dev/null | cut -d: -f1 | grep -Fqx "$USER"; then
    success "Samba account for $USER already exists"
else
    warn "Samba account for $USER not found -- run: sudo smbpasswd -a $USER"
fi

# -- 服务 ---------------------------------------------------------------------
# 只开 smbd：Windows 走 \\<IP>\Shared 不需要 NetBIOS 名字服务（nmbd）。
# enable 管下次开机，start 让本次安装后立刻可连。
header "Samba service"
enable_system_service smb.service
start_system_service smb.service

# 配置每次覆盖；正在跑的 smbd 要 SIGHUP 才重读共享定义。
if systemctl is-active smb.service &>/dev/null; then
    if _as_root systemctl reload smb.service; then
        success "smb.service reloaded"
    else
        warn "smb.service reload failed -- restart it manually"
    fi
fi

success "Samba done"
