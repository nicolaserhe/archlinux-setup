# System layer quirks

跨多模块的系统级坑：keyd / boot / system services / `run_step` 行为。

## keyd 键盘重映射

- **keyd Caps↔Esc 让 niri 看到的是 swap 后的 keysym**：keyd 在键到达 compositor 前 remap。带 `capslock=esc` 和 `esc=capslock`，niri 看到的是 Caps_Lock when 用户按物理 Esc，看到 Escape when 用户按物理 Caps。niri binding 用 post-remap keysym：bind 到 `Mod+Escape` 对应物理 Caps，`Mod+Caps_Lock` 对应物理 Esc。锁屏故意绑到 `Mod+Caps_Lock`（物理 Esc）避免 vim 高频 Esc 误触发。

## Boot

- **GRUB matter theme 不幂等**：`matter.py`（上游 installer）每次跑都重写 `GRUB_THEME`、重建 `grub.cfg`。`core/boot.sh` 检查 `/boot/grub/themes/Matter/` 已存在就跳过。
- **matter 1080p layout patch（opt-in）**：matter 默认布局对 1920x1080 偏稀疏，长 menuentry 标题（"Advanced options for Arch Linux"）被宽度截断。`GRUB_MATTER_1080P_LAYOUT=1 bash install.sh`（或单跑 `bash scripts/core/boot.sh`）触发，只调 `item_height`/`item_spacing`/`boot_menu` 区域。**字号必须保持 32**：matter 只生成字号 32 的 PF2 位图字体，改字号 → GRUB fallback 到 Unifont 字宽计算 → 字符叠加。幂等标记是 `theme.txt.bak` 存在；matter 上游升级若字段值变了，sed 前置 grep 校验会 abort 而非 silent no-op。

## System services

- **Avahi required for KDE Connect 设备发现**：没有 `avahi-daemon.service` enabled，手机在 LAN 上发现不了桌面。`system-services.sh` enable 它。
- **Notification daemon conflicts**：DMS 注册 `org.freedesktop.Notifications`。别的通知 daemon 抢到这个名字就阻塞 `dms.service`（systemd: `Two services allocated for the same bus name`）。`scripts/preflight.sh` 在 `install.sh` 早期检测六个 —— `mako`/`dunst`/`swaync`/`fnott`/`xfce4-notifyd`/`notification-daemon`（wlroots 系 + 跨环境 + 老 X11 的），命中就 die 并给出卸载命令。判据是**包在不在**而不是有没有在跑：装了没跑的，下次登录可能被 autostart 拉起来，那时 install 早跑完了，问题会以"通知弹两次"的形式出现。
- **Power management daemon conflicts**：`system-services.sh` 装 `power-profiles-daemon` 管 CPU 频率/电源策略。`tlp`/`auto-cpufreq`/`cpupower` 同样接管这一职责，同时运行会互相覆盖设置（PPD ↔ tlp 是众所周知互斥）。`tuned-ppd` 比它们更硬：它同时 `Provides` 和 `Conflicts` `power-profiles-daemon`，而 `pacman_install` 走 `--noconfirm`（冲突询问默认答 No），后果是 user-phase **中段**以"包冲突"中止，错误现场离病因很远；`tuned` 是它依赖的真 daemon，自己不声明冲突，但跟 PPD 是同一件事的两种实现。`preflight.sh` 把这五个都列为冲突并 die，让"二选一"发生在安装之前。

## lib/utils.sh `run_step` 行为

- **`run_step` LOG_FILE capture 不能吞交互 prompt**：bash `read -rp` 把 prompt 写到 stderr。若只是"重定向进 log、跑完再打出来"（老写法 `cat "$tmpfile" >&2`），prompt 会等到命令结束才出现，而用户要先看到才能输入 —— 交互脚本（如 `setup-user.sh`）看起来就是在静默 hang。Fix：`"$@" > >(tee -a "$LOG_FILE" >&2) 2>&1`，stdout + stderr 都落进 `$LOG_FILE`，tee 同时把内容实时转到 stderr。用 process substitution 而不是 `| tee` 还有第二个理由：pipe 会把子命令放进 subshell，`export TARGET_USER`（install.sh → 后续 step）和 `proxy_start` 导出的代理变量全都传不出去，详见 lib/utils.sh 里那段注释。

## Bash（`set -euo pipefail`）

- **`local -a x` 在 `set -u` 下仍算 unset**：它只把变量标成数组类型、不赋值，`${#x[@]}` 直接以 "x: unbound variable" 中止。要写成 `local -a x=()`。带字面量初始化的声明、以及后面紧跟 `mapfile` / `read -ra` 的声明都没这个问题（那两者空输入时也会赋值）。原 `pacman_remove` 就踩在这上面（"一个包都没装"是它最常见的路径）；函数本身已随「不做老版本兼容」删掉，坑记在这儿。
