# KDE Connect quirks

后端用上游 `kdeconnectd`（选型理由见 [dms.md](dms.md)）。守护进程由包自带的 `/etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop` 经 systemd 的 xdg-autostart-generator 生成 `app-org.kde.kdeconnect.daemon@autostart.service`，不自建 unit。

## 设备发现

- **别用 avahi 判断对端在不在**。实测 `avahi-browse -rtp _kdeconnect._udp` 只列出本机自己，对端 win（192.168.1.3）一条记录都没有 —— 而它当时是活的。判断对端用 TCP 探测：`timeout 2 bash -c 'echo >/dev/tcp/<ip>/1716'`（win 实测 445/139/1716 都开）。
- **守护进程重启后会自己重新发现**，不需要手动干预。实测 restart 后同一秒日志就有 `new capabilities for "win"`，`kdeconnect-cli -l` 直接报 `reachable`。
- 真发现不到时的第一条恢复动作：`kdeconnect-cli --refresh`（强制重播身份广播）。

## 查询对端支持哪些插件

D-Bus 方法在 `org.kde.kdeconnect.device` 接口上，**插件名必须带 `kdeconnect_` 前缀**：

```bash
busctl --user call org.kde.kdeconnect \
  /modules/kdeconnect/devices/<device-id> \
  org.kde.kdeconnect.device hasPlugin s "kdeconnect_ping"   # → b true
```

传不带前缀的 `"ping"` **不报错、静默返回 false** —— 拿它轮询一遍会把 win 的 7 个可用插件全判成不可用，得出"这设备什么都不支持"的错误结论。设备对象路径用 `busctl --user tree org.kde.kdeconnect` 枚举；整份清单读同接口的 `supportedPlugins` 属性。

`busctl introspect` 对这个对象**用不了**（服务端报 `duplicate method 'sendSimpleNotification'`），方法名只能靠 `gdbus introspect` 或直接试。

## 文件传输

- `kdeconnect_sftp`（「浏览设备文件」）需要**对端**跑 SFTP 服务端。Windows 版 KDE Connect 不提供，所以对 win 这类对端该功能不可用 —— Linux 侧装 `sshfs` 只是补上客户端，救不回来。实测 win 的 `supportedPlugins` 里没有 `kdeconnect_sftp`。
- 对端是 Windows 时的替代：SMB（win 的 445/139 开着），或在 Windows 上启用自带的 OpenSSH Server 再走 `sshfs`。
- `kdeconnect_share`（发送文件）是单向推送，不需要对端有服务端，win 上可用。

## 守护进程生命周期

`kdeconnectd` 是 Qt GUI 应用（链 `Qt6Widgets`，用 `QGuiApplication`），**图形会话连接一断就跟着退出**。实测一次 amdgpu GPU reset（chrome 触发 page fault → MODE2 复位）打断 Wayland 连接，它即以 `Error reading events from display: Broken pipe` 退出（exit 1），12 秒后被 systemd 拉起，设备发现、剪贴板全部自愈。

看到这条日志先查 `journalctl -k | grep 'GPU reset'`，别当成 KDE Connect 自己的 bug。

## `isPluginSupported` 日志噪音

守护进程日志偶尔出现：

```
QDBusConnection: couldn't handle call to isPluginSupported, no slot matched
Could not find slot Device::isPluginSupported
```

这是**别人**在调一个不存在的方法。`busctl` 直调会在 introspection 阶段就被拒、不产生日志，所以来源另有其人 —— 但 DankKDEConnect 插件目录、`/usr/share/quickshell/dms`、`dms` 二进制里都搜不到这个字符串，出处未明。DMS 插件的 `hasPlugin()` 读的是设备属性 `supportedPlugins`，不受影响。无已知影响。
