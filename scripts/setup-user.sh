#!/usr/bin/env bash
# =============================================================================
# scripts/setup-user.sh -- 用户选择 / 创建
#
# stdout 只输出最终用户名，供调用方通过 $() 捕获。
# 所有提示信息写到 stderr，不干扰 stdout 捕获。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

header "User setup"

# 获取所有 wheel/sudo 组成员（去重，排除 root）
_sudo_users() {
    local users=()
    for grp in wheel sudo; do
        if getent group "$grp" &>/dev/null; then
            IFS=',' read -ra members <<<"$(getent group "$grp" | cut -d: -f4)"
            for u in "${members[@]}"; do
                [[ -n "$u" && "$u" != "root" ]] && users+=("$u")
            done
        fi
    done
    printf '%s\n' "${users[@]}" | sort -u
}

_create_user() {
    local new_user
    while true; do
        read -rp "$(echo -e "${BOLD}New username: ${RESET}")" new_user
        [[ -z "$new_user" ]] && {
            warn "Username cannot be empty"
            continue
        }
        id "$new_user" &>/dev/null && {
            warn "User '$new_user' already exists"
            continue
        }
        break
    done
    useradd -m -G wheel -s /bin/bash "$new_user"
    success "User '$new_user' created and added to wheel group"
    echo -e "${BOLD}Set password for '$new_user':${RESET}" >&2
    passwd "$new_user"
    echo "$new_user" # stdout：供调用方 $() 捕获
}

mapfile -t sudo_users < <(_sudo_users)

if [[ ${#sudo_users[@]} -eq 0 ]]; then
    warn "No existing sudo users found -- creating a new user"
    _create_user
    exit 0
fi

# 展示现有用户列表
echo -e "${BOLD}Existing sudo users:${RESET}" >&2
for i in "${!sudo_users[@]}"; do
    if [[ $i -eq 0 ]]; then
        echo -e "  ${GREEN}$i) ${sudo_users[$i]}${RESET}  ${BOLD}[default]${RESET}" >&2
    else
        echo -e "  $i) ${sudo_users[$i]}" >&2
    fi
done
echo -e "  n) Create a new user" >&2
echo >&2

while true; do
    read -rp "$(echo -e "${BOLD}Select [0]: ${RESET}")" input
    input="${input:-0}"
    if [[ "$input" =~ ^[nN]$ ]]; then
        _create_user
        break
    elif [[ "$input" =~ ^[0-9]+$ ]] && ((input < ${#sudo_users[@]})); then
        success "Selected user: ${sudo_users[$input]}"
        echo "${sudo_users[$input]}" # stdout：供调用方 $() 捕获
        break
    else
        warn "Invalid input -- enter a number (0-$((${#sudo_users[@]} - 1))) or n"
    fi
done
