#!/usr/bin/env bash
# =============================================================================
# scripts/config/fcitx.sh -- Fcitx5 + 雾凇拼音配置
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/common.sh"

# -- 校验 pacman 包已安装 -----------------------------------------------------
header "Fcitx5 packages (verify)"
for pkg in fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool fcitx5-rime librime; do
    pacman -Qi "$pkg" &>/dev/null ||
        die "Missing package: $pkg -- run scripts/packages/pacman.sh first"
done
success "Fcitx5 packages ready"

# -- Wayland 环境变量 ---------------------------------------------------------
header "Input method env vars"
mkdir -p "$HOME/.config/environment.d"
cat >"$HOME/.config/environment.d/fcitx.conf" <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
success "Written: ~/.config/environment.d/fcitx.conf"

# -- 皮肤与 UI ----------------------------------------------------------------
header "ClassicUI config"
mkdir -p "$HOME/.config/fcitx5/conf"
cat >"$HOME/.config/fcitx5/conf/classicui.conf" <<'EOF'
PerScreenDPI=False
Font="Noto Sans Mono 13"
Theme=adwaita-dark
EOF
success "Written: ~/.config/fcitx5/conf/classicui.conf"

# -- Profile（预选 Rime）------------------------------------------------------
header "Fcitx5 profile"
mkdir -p "$HOME/.config/fcitx5"
cat >"$HOME/.config/fcitx5/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=rime
Layout=

[GroupOrder]
0=Default
EOF
success "Written: ~/.config/fcitx5/profile"

# -- XDG Autostart ------------------------------------------------------------
header "Fcitx5 autostart"
mkdir -p "$HOME/.config/autostart"
cat >"$HOME/.config/autostart/fcitx5.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx5
Exec=fcitx5
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
success "Written: ~/.config/autostart/fcitx5.desktop"

# -- 雾凇拼音 -----------------------------------------------------------------
# 在 subshell 中运行，将临时目录的 trap 完全隔离，
# 不覆盖调用方（user-phase.sh）的 trap EXIT。
header "rime-ice"
RIME_DIR="$HOME/.local/share/fcitx5/rime"

(
    set -euo pipefail
    tmp="$(mktemp -d /tmp/rime-ice.XXXXXX)"
    trap 'rm -rf "$tmp"' EXIT

    git_clone "$tmp/rime-ice" https://github.com/iDvel/rime-ice

    rm -rf "$RIME_DIR"
    mkdir -p "$RIME_DIR"
    cp -r "$tmp/rime-ice/." "$RIME_DIR/"
)
success "rime-ice deployed: $RIME_DIR"

# -- default.custom.yaml ------------------------------------------------------
# 用补丁文件覆盖默认配置，升级词库时不会丢失这些设置
header "Rime custom config"
cat >"$RIME_DIR/default.custom.yaml" <<'EOF'
patch:
  menu/page_size: 9

  key_binder/bindings:
    - { when: paging,   accept: comma,        send: Page_Up   }
    - { when: has_menu, accept: period,       send: Page_Down }
    - { when: has_menu, accept: bracketleft,  send: Page_Up   }
    - { when: has_menu, accept: bracketright, send: Page_Down }
EOF
success "Written: $RIME_DIR/default.custom.yaml"

# -- 预编译词库 ---------------------------------------------------------------
header "Rime dictionary build"
if command_exists rime_deployer; then
    info "Building dictionary, please wait..."
    rime_deployer --build "$RIME_DIR" &&
        success "Dictionary built" ||
        warn "rime_deployer returned non-zero -- fcitx5 will retry on first launch"
else
    warn "rime_deployer not found -- dictionary will be built on first fcitx5 launch"
fi

success "Fcitx5 config done"
