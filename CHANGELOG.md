# OmaXerahs (Omarchy plugin) changelog

OmaXerahs is the Quickshell-side plugin that surfaces the `omaxerahs` upload
host on the Omarchy status bar. It is **not** the `.NET` CLI — that one
lives in `KovaForge/XerahS` and has its own
`docs/CHANGELOG_omaxerahs.md`. This file tracks the plugin code that runs
inside `omarchy-shell` and is hot-loaded by Quickshell.

A plugin install lives at `~/.config/omarchy/plugins/<id>/` and is
discovered through `manifest.json`. The current install is
`io.github.sharex.omaxerahs`, shipped as both a `service` (the upload host
that talks to the CLI) and a `bar-widget` (the capture button on the
Omarchy status bar).

Versions are recorded in `manifest.json`. The plugin and the CLI share
their version number so the Omarchy shell can detect a mismatch via
`omaxerahs capabilities`.

---

## v0.1.4 — in progress (Capture delay)

**Adds a configurable 3-second delayed-capture button alongside the
existing immediate Capture button.** New `captureDelaySeconds` setting
(defaults to 3, range 0–60, 0 disables the timer) controls how long the
plugin waits before invoking `omarchy-capture-screenshot`. The button
shows the configured delay, e.g. `Capture (3s)`, and switches to
`Cancel (Ns)` with a live countdown once started. Pressing it again
or hitting `Esc` during the countdown cancels the capture without
dropping the panel. The Service exposes `captureDelayed(mode)` and
`cancelCapture()` over its IPC; the Panel wires both into the
existing keyboard catcher (`d` / `D` triggers a delayed capture,
`q` / `Q` cancels during countdown before it falls through to
`close()`).

Key new pieces:

- `Service.qml`: `delaySeconds`, `countdownRemaining`, `pendingDelayedMode`
  properties; `captureDelayed(mode)` and `cancelCapture()` functions; a
  `Timer` driving `onCountdownTick()`; new `countdown` service state.
- `Panel.qml`: `delaySeconds`, `countingDown`, `countdownRemaining` readonly
  properties; `delayedButtonLabel` derives the button text from the live
  countdown; `startDelayedCapture()` re-uses `startCapture()` when the
  delay is zero so the UX stays identical to v0.1.3 in that mode.
- `Model.js`: `CAPTURE_DELAY_DEFAULT`, `clampDelaySeconds(seconds)`,
  `isCaptureMode(value)` (used by both the immediate and delayed paths).
- `manifest.json`: new `captureDelaySeconds` schema entry on the bar
  widget with default 3, min 0, max 60, step 1; bumped version to
  `0.1.4`.
- `tests/model-test.js`: regression coverage for the clamp helper.

## v0.1.3 — 2026-09-17

Hardening and lifecycle fixes in response to the Omarchy Marketplace
review and the first round of Omarchy-box testing.

### Capture lifecycle

- **Panel stays out of the way during capture.** `92ea25c` dismisses the
  OmaXerahs panel before invoking the screenshot helper, primes the
  keyboard catcher so `Esc` still closes the panel after capture, and
  accepts `q` / `Q` as an in-panel dismiss. Without this, the
  `KeyboardPanel` prime of `WlrKeyboardFocus.Exclusive` stole
  `Super+W` and pointer events from the rest of the desktop while a
  capture was running.
- **Cancel button on the panel.** `ad74fd6` adds an in-panel Cancel
  button so users can drop the keyboard-exclusive overlay without
  rebooting. `Esc` and `Super+W` are not delivered to the compositor
  while the `KeyboardPanel` holds exclusive focus, so the panel
  itself has to provide a clickable escape hatch.

### Helper process supervision

- **Bounded stdout and process-group kill on timeout.** `3f26c42` wraps
  `probe`, `capture`, `path`, and `upload` helpers in a supervisor
  that caps stdout / stderr before buffering, starts each helper in
  a private process group, and terminates / reaps the whole group on
  deadline or buffer overflow. Marketplace review caught the previous
  behaviour where a stuck helper could hang the upload pipeline
  indefinitely.

## v0.1.2 — 2026-09-17

- **README documents license, runtime dependencies, install command, and
  a marketplace preview.** `0aca795` adds `preview.png` (a crop of the
  live Omarchy bar widget), makes the MIT license explicit, lists the
  `xerahs` + `omaxerahs` + `wl-clipboard` runtime deps, and surfaces the
  `omarchy plugin install --enable` install path plus the local
  `omarchy-plugin-validate` and `tests/model-test.sh` invocations.

## v0.1.1 — 2026-09-02

Lifecycle / readiness fixes for the first round of Omarchy-box
testing.

- **Harden Omarchy capture readiness and lifecycle.** `ca4c3bc`
  tightens the readiness state machine so the bar widget reports the
  correct status during capture and on retry, and refuses to start a
  second capture while one is in flight.
- **Omarchy-box end-to-end capture checklist.** `8d8ff7a` adds
  `TODO-OMARCHY-E2E.md` describing the manual capture flow that the
  Marketplace review used to validate the plugin on a real Omarchy
  install.
- **Show "Not ready" instead of "Failed" when the CLI is missing.**
  `2b531c2` distinguishes a missing `omaxerahs` CLI on `PATH` (an
  installation problem, not an upload failure) from an actual upload
  failure, so the bar widget stops painting a red error state when
  the host is simply not installed yet.

## v0.1.0 — 2026-09-02 (inception)

Inception commit `97894a7` (`Add v1 OmaXerahs Omarchy screenshot
upload plugin.`).

The first cut shipped 10 files / ~1,740 lines:

- `manifest.json` — plugin manifest with id `io.github.sharex.omaxerahs`,
  kinds `["service", "bar-widget"]`, `keepLoaded: true`, an entry
  per QML file, and the bar widget schema (copy-URL-on-clipboard,
  notify-on-complete, open-URL-on-notification-click, capture-mode).
- `Service.qml` — the upload-host service. Wraps the `omaxerahs`
  CLI, exposes a JSON IPC, runs the capture via
  `omarchy-capture-screenshot`, and uploads through the configured
  XerahS image destination.
- `BarWidget.qml` — the bar widget. Calls into the service for
  capture / upload and renders the status (ready / capturing /
  uploaded / failed).
- `Panel.qml` — the keyboard-driven panel with `c` for capture,
  `r` for retry, and `q` for close.
- `Model.js` — small JSON helpers used by both QML files.
- `tests/model-test.js` + `tests/model-test.sh` — runner-agnostic
  model tests.
- `LICENSE` (MIT), `README.md`, `.gitignore`.

The plugin was built around the Omarchy `capture-menu` model and
shipped with the v1 capability published to the bar widget so the
plugin could be added via `omarchy plugin install
io.github.sharex.omaxerahs` and immediately expose a single
"capture and upload" action.