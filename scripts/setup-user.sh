#!/usr/bin/env bash
# =============================================================================
# scripts/setup-user.sh -- 用户选择 / 创建
#
# stdout 仅输出最终用户名，便于调用方通过 $() 捕获。
# 提示与日志写到 stderr，避免污染捕获结果。
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/utils.sh"

header "User setup"

# wheel/sudo 组同时存在时取并集；root 永不视为候选，避免误选
_sudo_users() {
    local grp u
    local -a users=() members
    for grp in wheel sudo; do
        getent group "$grp" &>/dev/null || continue
        IFS=',' read -ra members <<<"$(getent group "$grp" | cut -d: -f4)"
        for u in "${members[@]}"; do
            [[ -n "$u" && "$u" != "root" ]] && users+=("$u")
        done
    done
    ((${#users[@]} > 0)) && printf '%s\n' "${users[@]}" | sort -u
}

_create_user() {
    local new_user
    while true; do
        read -rp "$(echo -e "${BOLD}New username: ${RESET}")" new_user
        if [[ -z "$new_user" ]]; then
            warn "Username cannot be empty"
            continue
        fi
        if id "$new_user" &>/dev/null; then
            warn "User '$new_user' already exists"
            continue
        fi
        break
    done
    useradd -m -G wheel -s /bin/bash "$new_user"
    success "User '$new_user' created and added to wheel group"
    echo -e "${BOLD}Set password for '$new_user':${RESET}" >&2
    passwd "$new_user"
    echo "$new_user"
}

mapfile -t sudo_users < <(_sudo_users)

if ((${#sudo_users[@]} == 0)); then
    warn "No existing sudo users found -- creating a new user"
    _create_user
    exit 0
fi

echo -e "${BOLD}Existing sudo users:${RESET}" >&2
for i in "${!sudo_users[@]}"; do
    if ((i == 0)); then
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
        echo "${sudo_users[$input]}"
        break
    else
        warn "Invalid input -- enter a number (0-$((${#sudo_users[@]} - 1))) or n"
    fi
done
