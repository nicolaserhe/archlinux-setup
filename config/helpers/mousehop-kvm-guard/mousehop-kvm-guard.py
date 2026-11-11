#!/usr/bin/env python3
"""Keeps Mousehop in step with the USB KVM switch.

Why: after Mousehop hands input to the Windows peer, the local cursor
stays parked exactly on Mousehop's 1 px crossing surface at the screen
edge.  If the USB KVM is then used to switch machines, nothing warps the
cursor away, so the first rightward motion after switching back re-enters
that surface and hands control to Windows again.  Moving the cursor to the
middle of the focused output on every KVM return removes that hair trigger.
Mousehop's deliberate edge crossing (hold Alt, push to the edge) is
unaffected.

The same switch also decides whether Mousehop should be running at all.
While the KVM feeds the other machine, the peer's Mousehop still sees its
own screen edge and will happily hand the cursor back here, so the mouse
"escapes" a machine it no longer belongs to.  Deactivating the client is
not enough: inbound handovers are accepted for any fingerprint in the
authorized list regardless of whether its client is active, so the daemon
is stopped while the devices are absent and started again on return.
"""

import glob
import json
import logging
import os
import re
import subprocess
import sys
import time
from typing import Any

# USB ids of the devices that live behind the KVM hub on this machine.
# 258a:013b Sino Wealth Gaming Keyboard, 3554:f50b Compx VGN Dragonfly
# 2.4G dongle (mouse).  Change these if the hardware changes.
KVM_DEVICES = {
    ("258a", "013b"),
    ("3554", "f50b"),
}

POLL_SECONDS = 0.15
# Repeat the warp a couple of times; the first one can race the peer's
# cursor model or a still-being-torn-down pointer lock.
WARP_DELAYS = (0.0, 0.3)
HELPER = os.path.expanduser("~/.local/bin/mousehop-center-cursor")
# The client whose edge surface points at the Windows machine.
MOUSEHOP_CLIENT_HOST = "win"

log = logging.getLogger("mousehop-kvm-guard")


def usb_devices() -> set[tuple[str, str]]:
    """Return the (idVendor, idProduct) pairs of present USB devices."""
    found = set()
    for vendor_path in glob.glob("/sys/bus/usb/devices/*/idVendor"):
        base = os.path.dirname(vendor_path)
        try:
            with open(vendor_path) as f:
                vendor = f.read().strip().lower()
            with open(os.path.join(base, "idProduct")) as f:
                product = f.read().strip().lower()
        except OSError:
            continue
        found.add((vendor, product))
    return found


def kvm_present() -> bool:
    return bool(usb_devices() & KVM_DEVICES)


def niri_json(*args: str) -> Any:
    out = subprocess.check_output(
        ["niri", "msg", "--json", *args],
        stderr=subprocess.DEVNULL,
        timeout=3,
    )
    return json.loads(out)


def warp_target() -> tuple[int, int, int, int] | None:
    """Center of the focused output plus the layout bbox size.

    The center is relative to the bbox origin because motion_absolute takes
    unsigned coordinates scaled to the passed extent.
    """
    outputs = niri_json("outputs")
    rects = [o["logical"] for o in outputs.values() if o.get("logical")]
    if not rects:
        return None
    x0 = min(r["x"] for r in rects)
    y0 = min(r["y"] for r in rects)
    x1 = max(r["x"] + r["width"] for r in rects)
    y1 = max(r["y"] + r["height"] for r in rects)

    try:
        focused = niri_json("focused-output")
        logical = focused["logical"]
    except (subprocess.SubprocessError, KeyError, ValueError, json.JSONDecodeError):
        logical = None
    if not logical:
        logical = {"x": x0, "y": y0, "width": x1 - x0, "height": y1 - y0}

    # motion_absolute 的 x/y 是无符号的、按传入的 extent 归一化；多屏布局可以
    # 延伸到负坐标（副屏在左/上），所以坐标要减去布局包围盒原点再传。
    tx = int(logical["x"] + logical["width"] / 2 - x0)
    ty = int(logical["y"] + logical["height"] / 2 - y0)
    return tx, ty, x1 - x0, y1 - y0


def warp_to_center(delays: tuple[float, ...] = WARP_DELAYS) -> None:
    try:
        target = warp_target()
    except (subprocess.SubprocessError, ValueError, json.JSONDecodeError) as exc:
        log.warning("cannot read niri output layout: %s", exc)
        return
    if target is None:
        log.warning("no niri outputs reported; not warping")
        return
    tx, ty, w, h = target
    started = time.monotonic()
    warped = False
    for delay in delays:
        remaining = delay - (time.monotonic() - started)
        if remaining > 0:
            time.sleep(remaining)
        try:
            result = subprocess.run(
                [HELPER, str(tx), str(ty), str(w), str(h)],
                check=False,
                capture_output=True,
                timeout=2,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            log.warning("cursor warp failed: %s", exc)
            continue
        if result.returncode != 0:
            log.warning(
                "cursor warp helper exited %d: %s",
                result.returncode,
                result.stderr.decode(errors="replace").strip(),
            )
            continue
        warped = True
    if warped:
        log.info("centered cursor at (%d, %d) in %dx%d layout", tx, ty, w, h)
    else:
        log.warning("cursor was not recentered; it may still sit on the edge")


def mousehop_cli(
    *args: str, quiet: bool = False
) -> subprocess.CompletedProcess[bytes] | None:
    try:
        return subprocess.run(
            ["mousehop", "cli", *args],
            capture_output=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        if not quiet:
            log.warning("mousehop cli %s failed: %s", " ".join(args), exc)
        return None


def mousehop_client_id(quiet: bool = False) -> str | None:
    """Id of the client that points at the Windows machine, or None."""
    result = mousehop_cli("list", quiet=quiet)
    if result is None:
        return None
    for line in result.stdout.decode(errors="replace").splitlines():
        match = re.match(r"id\s+(\d+):\s*([^:]+):", line.strip())
        if match and match.group(2).strip() == MOUSEHOP_CLIENT_HOST:
            return match.group(1)
    if not quiet:
        log.warning("mousehop has no client named %r", MOUSEHOP_CLIENT_HOST)
    return None


def activate_mousehop_client() -> bool:
    client = mousehop_client_id(quiet=True)
    if client is None:
        return False
    result = mousehop_cli("activate", client)
    if result is None or result.returncode != 0:
        log.warning("could not activate mousehop client %s", client)
        return False
    log.info("mousehop client %s active", client)
    return True


def stop_mousehop() -> None:
    """Stop the daemon entirely while the KVM feeds the other machine.

    Deactivating the client is not enough: inbound handovers are accepted
    for any fingerprint in the authorized list, regardless of whether its
    client is active, so the peer could still pull the cursor over here.
    With the daemon stopped there is neither a crossing surface nor a
    listener, which is exactly the behaviour the hardware switch implies.
    """
    result = subprocess.run(
        ["systemctl", "--user", "stop", "mousehop.service"],
        check=False,
        capture_output=True,
        timeout=10,
    )
    if result.returncode != 0:
        log.warning("stopping mousehop.service failed (rc=%d)", result.returncode)
    else:
        log.info("stopped mousehop.service")


def start_mousehop() -> bool:
    result = subprocess.run(
        ["systemctl", "--user", "start", "mousehop.service"],
        check=False,
        capture_output=True,
        timeout=10,
    )
    if result.returncode != 0:
        log.warning("starting mousehop.service failed (rc=%d)", result.returncode)
        return False
    # The IPC socket only answers once the daemon is up; the peer may also
    # need a moment to reconnect.
    for _ in range(20):
        if mousehop_client_id(quiet=True) is not None:
            activate_mousehop_client()
            log.info("mousehop.service is back")
            return True
        time.sleep(0.5)
    log.warning("mousehop.service did not answer after start")
    return False


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    present = kvm_present()
    log.info("watching KVM devices %s (present=%s)", sorted(KVM_DEVICES), present)
    # Line Mousehop up with where the hardware switch is right now; the
    # service may have been left stopped by a previous run.
    if present:
        if not activate_mousehop_client():
            start_mousehop()
    else:
        stop_mousehop()
    while True:
        try:
            time.sleep(POLL_SECONDS)
            now = kvm_present()
        except Exception as exc:  # keep the guard alive on any scan hiccup
            log.warning("device scan failed: %s", exc)
            time.sleep(1.0)
            continue
        if now == present:
            continue
        if now:
            log.info(
                "KVM returned to this machine; starting mousehop "
                "and recentering cursor"
            )
            start_mousehop()
            warp_to_center()
        else:
            log.info("KVM left this machine; stopping mousehop")
            stop_mousehop()
        present = now


if __name__ == "__main__":
    main()
