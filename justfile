# archlinux-setup —— 本地校验任务
#
# 本仓库未接 CI，这两条就是全部门禁。改动后至少跑 `just all` 再提交。
#
#   just lint    静态分析（shellcheck + bash -n）
#   just check   仓库自检（$REPO_DIR 引用完整性 + config/assets 是否已纳入 git）
#   just all     两条都跑

set shell := ["bash", "-euo", "pipefail", "-c"]

# 跑全部校验
all: lint check

# 静态分析：shellcheck + bash -n
lint:
    bash scripts/checks/lint.sh

# 仓库自检：引用完整性 + git 跟踪状态
check:
    bash scripts/checks/verify-repo.sh
