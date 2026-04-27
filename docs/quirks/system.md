# System layer quirks

跨多模块的系统级坑：keyd / boot / system services / `run_step` 行为。

## keyd 键盘重映射

- **keyd Caps↔Esc 让 niri 看到的是 swap 后的 keysym**：keyd 在键到达 compositor 前 remap。带 `capslock=esc` 和 `esc=capslock`，niri 看到的是 Caps_Lock when 用户按物理 Esc，看到 Escape when 用户按物理 Caps。niri binding 用 post-remap keysym：bind 到 `Mod+Escape` 对应物理 Caps，`Mod+Caps_Lock` 对应物理 Esc。锁屏故意绑到 `Mod+Caps_Lock`（物理 Esc）避免 vim 高频 Esc 误触发。

## Boot

- **GRUB matter theme 不幂等**：`matter.py`（上游 installer）每次跑都重写 `GRUB_THEME`、重建 `grub.cfg`。`core/boot.sh` 检查 `/boot/grub/themes/Matter/` 已存在就跳过。
- **matter 1080p layout patch（opt-in）**：matter 默认布局对 1920x1080 偏稀疏，长 menuentry 标题（"Advanced options for Arch Linux"）被宽度截断。`GRUB_MATTER_1080P_LAYOUT=1 bash install.sh`（或单跑 `bash scripts/core/boot.sh`）触发，只调 `item_height`/`item_spacing`/`boot_menu` 区域。**字号必须保持 32**：matter 只生成字号 32 的 PF2 位图字体，改字号 → GRUB fallback 到 Unifont 字宽计算 → 字符叠加。幂等标记是 `theme.txt.bak` 存在；matter 上游升级若字段值变了，sed 前置 grep 校验会 abort 而非 silent no-op。

## System services

- **Avahi required for Valent/KDE Connect 设备发现**：没有 `avahi-daemon.service` enabled，手机在 LAN 上发现不了桌面。`system-services.sh` enable 它。
- **Notification daemon conflicts**：DMS 注册 `org.freedesktop.Notifications`。已有的 `mako`/`dunst`/`notification-daemon` 阻塞 `dms.service`（systemd: `Two services allocated for the same bus name`）。`scripts/preflight.sh` 在 `install.sh` 早期自动检测这三个包并 die，让用户先 `sudo pacman -Rns mako dunst notification-daemon` + `systemctl --user disable --now ...` 再继续。
- **Power management daemon conflicts**：`system-services.sh` 装 `power-profiles-daemon` 管 CPU 频率/电源策略。`tlp`/`auto-cpufreq`/`cpupower` 同样接管这一职责，同时运行会互相覆盖设置（PPD ↔ tlp 是众所周知互斥）。`scripts/preflight.sh` 同样检测并 die，提示用户先 `sudo pacman -Rns <pkg>` + `sudo systemctl disable --now <pkg>` 再继续。

## lib/utils.sh `run_step` 行为

- **`run_step` LOG_FILE capture 不能吞交互 prompt**：bash `read -rp` 把 prompt 写到 stderr。简单 `2>"$tmpfile"` 重定向会让用户看不到 prompt，交互脚本（如 `setup-user.sh`）看起来在静默 hang。Fix：`2> >(tee -a "$tmpfile" >&2)` 让 prompt 实时到终端同时记录到 log。老写法 `cat "$tmpfile" >&2` 在命令完成后再喷对 prompt 没用 —— 用户必须**先**看到再输入。
