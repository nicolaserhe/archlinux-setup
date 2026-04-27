"""Nautilus 右键 'Send to <device>' via Valent / KDE Connect.

接 Valent D-Bus 枚举已配对+已连接的设备，文件右键调
org.gtk.Actions.Activate("share.uris", [URIs]) 把文件推到手机。

部署位置: ~/.local/share/nautilus-python/extensions/valent_send.py
依赖:    nautilus-python (extra), valent (AUR)
重载:    nautilus -q  (扩展只在 nautilus 启动时加载)
"""

# Nautilus 进程加载扩展时已 require_version 完毕，扩展里再调会 ValueError。
from gi.repository import GLib, GObject, Gio, Nautilus

VALENT_BUS = "ca.andyholmes.Valent"
VALENT_ROOT = "/ca/andyholmes/Valent"
DEVICE_IFACE = "ca.andyholmes.Valent.Device"
STATE_PAIRED = 1
STATE_CONNECTED = 2


def _reachable_devices():
    """返回 [(object_path, name), ...]，仅 paired + connected."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = bus.call_sync(
            VALENT_BUS,
            VALENT_ROOT,
            "org.freedesktop.DBus.ObjectManager",
            "GetManagedObjects",
            None,
            GLib.VariantType.new("(a{oa{sa{sv}}})"),
            Gio.DBusCallFlags.NONE,
            3000,
            None,
        )
    except GLib.Error:
        return []

    objs = reply.unpack()[0]
    devices = []
    for path, ifaces in objs.items():
        props = ifaces.get(DEVICE_IFACE)
        if not props:
            continue
        state = props.get("State", 0)
        if (state & STATE_PAIRED) and (state & STATE_CONNECTED):
            devices.append((path, props.get("Name", "device")))
    return devices


def _send_to(device_path, uris):
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        params = GLib.Variant(
            "(sava{sv})",
            ("share.uris", [GLib.Variant("as", uris)], {}),
        )
        bus.call_sync(
            VALENT_BUS,
            device_path,
            "org.gtk.Actions",
            "Activate",
            params,
            None,
            Gio.DBusCallFlags.NONE,
            5000,
            None,
        )
    except GLib.Error as exc:
        print(f"[valent-send] failed: {exc}")


class ValentSendProvider(GObject.GObject, Nautilus.MenuProvider):
    def _on_activate(self, _menu, device_path, uris):
        _send_to(device_path, uris)

    def get_file_items(self, *args):
        files = args[-1]
        uris = [
            f.get_uri()
            for f in files
            if f.get_uri_scheme() == "file" and not f.is_directory()
        ]
        if not uris:
            return []

        devices = _reachable_devices()
        if not devices:
            return []

        if len(devices) == 1:
            path, name = devices[0]
            item = Nautilus.MenuItem(
                name=f"ValentSend::{path}",
                label=f"Send to {name}",
                icon="phone-symbolic",
            )
            item.connect("activate", self._on_activate, path, uris)
            return [item]

        parent = Nautilus.MenuItem(
            name="ValentSend::menu",
            label="Send to phone",
            icon="phone-symbolic",
        )
        submenu = Nautilus.Menu()
        for path, name in devices:
            sub = Nautilus.MenuItem(
                name=f"ValentSend::{path}",
                label=name,
                icon="phone-symbolic",
            )
            sub.connect("activate", self._on_activate, path, uris)
            submenu.append_item(sub)
        parent.set_submenu(submenu)
        return [parent]
