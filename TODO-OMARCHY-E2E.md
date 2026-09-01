# Omarchy box: end-to-end capture checklist

Run this on a real Omarchy machine. The Windows workspace cannot exercise grim/slurp, Hyprland binds, `wl-copy`, or `omarchy-shell` IPC.

Native XerahS must already ship `/usr/bin/omaxerahs` (version that contains the OmaXerahs host). Plugin repo: this checkout, or `omarchy plugin add https://github.com/ShareX/omaxerahs.git`.

Mark each item. Do not enable automatic directory watching — v1 has no `autoUploadEnabled`.

## 0. Prerequisites

- [ ] Native `xerahs` package installed (not Flatpak)
- [ ] `command -v omaxerahs` prints `/usr/bin/omaxerahs`
- [ ] `omaxerahs capabilities --json` → `schemaVersion` 1, `capabilities` includes `doctor.image` and `upload.image`
- [ ] XerahS GUI has a configured **Image** destination (and, for routing tests, a separate **File** destination)
- [ ] `omaxerahs doctor --json` → `ok: true`, `image.ready: true`
- [ ] `omarchy plugin validate` against this repo root succeeds
- [ ] Plugin installed and enabled; bar widget visible on one monitor, then two

## 1. No implicit upload

- [ ] Install/enable does **not** upload anything
- [ ] Stock `Print` still runs `omarchy-capture-screenshot` (image clipboard + Omarchy screenshot notification)
- [ ] Plugin settings do not include `autoUploadEnabled`

## 2. Explicit capture-and-upload

- [ ] Bar left-click: region picker, save PNG, one upload, URL on clipboard (`wl-paste`), Omarchy notification with host/filename (not a second image-clipboard from save mode)
- [ ] `omarchy-shell omaxerahs capture smart` returns immediately, then same capture→upload
- [ ] Modes: `region`, `windows`, `fullscreen`
- [ ] Cancel region picker (`Esc` / Print again): no notification, clipboard unchanged, no upload
- [ ] Source PNG remains in the Pictures/screenshot dir; plugin never deletes it

## 3. Keybinds (copyable only — do not let the plugin edit them)

Add, then restore, in `~/.config/hypr/bindings.lua` (or your overlay):

```lua
o.bind("SUPER + SHIFT + PRINT", "Screenshot and upload", "omarchy-shell omaxerahs capture smart")
```

- [ ] Dedicated shortcut coexists with stock Print
- [ ] Optional replace:

```lua
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot and upload", "omarchy-shell omaxerahs capture smart")
```

- [ ] Restore stock:

```lua
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot")
```

## 4. Routing and failure

- [ ] Image dest present + File dest present → PNG goes to **Image** once
- [ ] Disable/break Image dest, File dest still ready → upload fails, **no** File HTTP object
- [ ] Offline / provider reject / expired credentials → Failed + Retry; local PNG kept; clipboard not replaced
- [ ] `omaxerahs` missing from PATH → widget `Not ready` / `cli_missing`, no capture loop
- [ ] Flatpak-only XerahS → `cli_flatpak` message, no silent permission grab

## 5. Process and multi-monitor

- [ ] Two monitors: one service, one `omaxerahs` child at a time
- [ ] Queue: rapid captures bound at 8; duplicate same path collapsed
- [ ] Disable plugin, re-enable, restart `omarchy-shell`, remove plugin while idle and during an upload: no orphan `omaxerahs` / `inotifywait` / grim
- [ ] Paths with spaces and metacharacters in the screenshot directory still upload once

## 6. Clipboard / notify ownership

- [ ] Save-mode capture does **not** copy image/png (plugin copies URL only)
- [ ] `copyUrlToClipboard` off → no `wl-copy`
- [ ] `notifyOnComplete` off → no success notification
- [ ] `openUrlOnNotificationClick` default off; when on, click opens the URL via `--exec xdg-open <url>` as separate argv

## 7. Cleanup

- [ ] `omarchy plugin remove io.github.sharex.omaxerahs`
- [ ] Screenshots, `~/.config/xerahs`, secrets, and history still intact
- [ ] Optional: delete `~/.local/state/omaxerahs/`

When this list is green, marketplace listing can proceed (`Productivity`, public git root with manifest/README/LICENSE).
