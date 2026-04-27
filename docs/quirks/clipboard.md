# Clipboard quirks (`scripts/core/clipboard.sh`)

## Architecture (v2 — unified daemon)

One Python daemon replaces the old 6-service stack:

```
unified-clipboard.service
└── unified-clipboard (Python, ~450 lines)
    ├── CLIPBOARD Wayland ↔ X11 (text + image + file URI)
    ├── PRIMARY  Wayland ↔ X11 (text only, via XFIXES)
    └── file_only mode (WeChat file paste)
```

**Key design decisions:**
- Always holds X11 CLIPBOARD (no inter-daemon races).
- `select()` on 3 fds: `wl-paste --watch` (clipboard), `wl-paste --primary --watch` (primary), X11 display.
- Content hash prevents feedback loops.
- Magic-byte validation for `image/*` and `text/uri-list` — `xclip -in` serves the same text data for every target, so we must verify before accepting.

## file_only mode

When Wayland CLIPBOARD has `text/uri-list` **without** `image/*`:
- Expose only `TARGETS`, `TIMESTAMP`, `text/uri-list`, `x-special/gnome-copied-files` on X11.
- Refuse all `text/*` targets — forces WeChat Flatpak to fall back to `text/uri-list` → correct file paste.
- Other X11 apps that request `text/plain` get nothing (regression from multicliprelay for this specific edge case; acceptable trade-off).

## X11→Wayland single-MIME limitation

`wl-copy` can only set one MIME type. When X11 clipboard has multiple types (e.g. image + text), Wayland only gets the first valid one (priority: image > URI > text). In practice multi-type X11 clipboards are rare.
