# OmaXerahs

Omarchy plugin that captures a screenshot with Omarchy, then uploads that exact PNG through the native `omaxerahs` CLI to your configured XerahS **image** destination.

Version 1 is **explicit capture-and-upload only**. It does not watch directories, does not watch the clipboard, and does not enable automatic upload on install.

Plugin id: `io.github.sharex.omaxerahs`  
IPC target: `omaxerahs`

## Install

```
omarchy plugin add https://github.com/ShareX/omaxerahs.git
```

The plugin is an adapter. It does not ship the uploader. Install **native** XerahS (not Flatpak) so `/usr/bin/omaxerahs` is on `PATH`.

```
command -v omaxerahs
```

## First run

1. Open the XerahS GUI and configure an **image** destination.
2. Confirm the CLI agrees:

   ```
   omaxerahs doctor --json
   ```

   `ok` must be true and `image.ready` must be true. A File-category destination is not enough.
3. Add and enable this plugin. Nothing is uploaded until you click the bar button or invoke IPC.

The plugin never runs `omaxerahs doctor --fix` and never uses `sudo`.

## Explicit vs future automatic

v1 uploads only after:

- a left-click on the bar widget, or
- `omarchy-shell omaxerahs capture <mode>`

It does **not** watch the screenshot directory. Automatic directory observation is specified for a later version and stays off until that work ships. There is no `autoUploadEnabled` setting in v1.

## Keybinds

The plugin never edits Hyprland bindings. Copy these into your bindings file yourself.

Dedicated shortcut (stock Print is unchanged):

```
o.bind("SUPER + SHIFT + PRINT", "Screenshot and upload", "omarchy-shell omaxerahs capture smart")
```

Replace Print:

```
-- PRINT is normally bound to omarchy-capture-screenshot.
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot and upload", "omarchy-shell omaxerahs capture smart")
```

Restore stock Print:

```
hl.unbind("PRINT")
o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot")
```

Other modes: `region`, `windows`, `fullscreen`.

```
omarchy-shell omaxerahs capture region
omarchy-shell omaxerahs status
omarchy-shell omaxerahs retry
```

Bar: left-click captures with the widget's `captureMode` (default `smart`) and uploads. Right-click opens the panel. The panel has Capture and Retry (Retry only after a failed upload of a still-present file).

Canceling the region picker is silent: no notification, no clipboard change, no upload.

## Privacy

This plugin observes **selected screenshot paths** that Omarchy just wrote, then launches `omarchy` (capture, save mode) and `omaxerahs` (upload). It does not read XerahS credentials, does not implement providers, and does not put tokens in QML.

Plugins run **unsandboxed** inside `omarchy-shell` with your user account. Marketplace listing is a schema/listing check, **not** a security review. Only add repos you are willing to run.

Local PNGs are never deleted, moved, or rewritten. Persistent UI shows host + filename, not the full URL. The URL is copied with `wl-copy` only after a successful `http://` or `https://` result, and only when `copyUrlToClipboard` is on.

## Disable / remove

```
omarchy plugin disable io.github.sharex.omaxerahs
omarchy plugin remove io.github.sharex.omaxerahs
```

Removal deletes the plugin checkout under `~/.config/omarchy/plugins/io.github.sharex.omaxerahs/`. You may also delete `~/.local/state/omaxerahs/`. XerahS settings, secrets, and upload history stay in place.

## Settings

Bar-widget settings in `shell.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `copyUrlToClipboard` | `true` | `wl-copy` the URL after a successful upload |
| `notifyOnComplete` | `true` | Omarchy notification on success |
| `openUrlOnNotificationClick` | `false` | Only then is `--exec xdg-open <url>` added |
| `captureMode` | `smart` | `smart`, `region`, `windows`, or `fullscreen` |

v1 does not watch directories.
