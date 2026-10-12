# archlinux-setup —— 本地校验任务
#
# 本仓库未接 CI，这两条就是全部门禁。改动后至少跑 `just all` 再提交。
#
#   just lint    静态分析（shellcheck + bash -n）
#   just check   仓库自检（$REPO_DIR 引用完整性 + config/assets 已纳入 git + config/ 部署覆盖）
#   just all     两条都跑
#   just drift   仓库 ↔ 本机 的配置漂移（只能在这台装过机的用户下跑，不在 all 里）

set shell := ["bash", "-euo", "pipefail", "-c"]

# 跑全部校验
all: lint check

# 静态分析：shellcheck + bash -n
lint:
    bash scripts/checks/lint.sh

# 仓库自检：引用完整性 + git 跟踪状态 + config/ 部署覆盖
check:
    bash scripts/checks/verify-repo.sh

# 配置漂移：比对仓库与这台机器上已部署的文件（依赖本机状态，故不入 all）
drift:
    bash scripts/checks/drift-check.sh
