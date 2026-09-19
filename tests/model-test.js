#!/usr/bin/env node
"use strict"

const path = require("path")
const assert = require("assert")
const model = require(path.join(__dirname, "..", "Model.js"))

function pass(name) {
  console.log("ok - " + name)
}

function fail(name, detail) {
  console.error("not ok - " + name)
  if (detail) console.error(detail)
  process.exit(1)
}

function check(name, condition, detail) {
  if (condition) pass(name)
  else fail(name, detail)
}

function deepEqual(name, actual, expected) {
  try {
    assert.deepStrictEqual(actual, expected)
    pass(name)
  } catch (e) {
    fail(name, e.message)
  }
}

check("smart is a capture mode", model.isCaptureMode("smart"))
check("region is a capture mode", model.isCaptureMode("region"))
check("windows is a capture mode", model.isCaptureMode("windows"))
check("fullscreen is a capture mode", model.isCaptureMode("fullscreen"))
check("slurp is not a capture mode", !model.isCaptureMode("slurp"))
check("empty mode is invalid", !model.isCaptureMode(""))

const good = "/home/user/Pictures/screenshot-2026-09-02_14-22-05.png"
check("absolute Omarchy PNG is accepted", model.validateScreenshotPath(good).ok === true)
check("relative path is rejected", model.validateScreenshotPath("screenshot-2026-09-02_14-22-05.png").ok === false)
check("empty path is rejected", model.validateScreenshotPath("").ok === false)
check("non-png is rejected", model.validateScreenshotPath("/home/user/Pictures/screenshot-2026-09-02_14-22-05.jpg").ok === false)
check("wrong basename is rejected", model.validateScreenshotPath("/home/user/Pictures/shot.png").ok === false)
check("uppercase PNG is rejected", model.validateScreenshotPath("/home/user/Pictures/screenshot-2026-09-02_14-22-05.PNG").ok === false)
check("path with newline is rejected", model.validateScreenshotPath(good + "\n/etc/passwd").ok === false)
check("windows-style relative path is rejected", model.validateScreenshotPath("C:\\Pictures\\screenshot-2026-09-02_14-22-05.png").ok === false)

check("http URL is accepted", model.isHttpUrl("http://i.example.invalid/abc.png"))
check("https URL is accepted", model.isHttpUrl("https://i.example.invalid/abc.png"))
check("HTTPS uppercase scheme is rejected", !model.isHttpUrl("HTTPS://i.example.invalid/abc.png"))
check("ftp URL is rejected", !model.isHttpUrl("ftp://i.example.invalid/abc.png"))
check("missing url is rejected", !model.isHttpUrl(undefined))
check("host is parsed", model.hostFromUrl("https://i.example.invalid/abc.png") === "i.example.invalid")

const oneObject = model.parseOneJsonObject('{"ok":true,"url":"https://i.example.invalid/a.png"}')
check("single JSON object parses", oneObject.ok === true && oneObject.value.ok === true)

const extra = model.parseOneJsonObject('{"ok":true} extra')
check("extra tokens fail closed", extra.ok === false && extra.error.code === "invalid_json")

const toast = model.parseOneJsonObject('[NOTIFICATION] uploaded\n{"ok":true}')
check("toast-prefixed JSON fails closed", toast.ok === false)

const emptyJson = model.parseOneJsonObject("   ")
check("empty stdout fails closed", emptyJson.ok === false)

const arrayJson = model.parseOneJsonObject("[{\"ok\":true}]")
check("JSON array fails closed", arrayJson.ok === false)

const twoObjects = model.parseOneJsonObject('{"ok":true}\n{"ok":false}')
check("two JSON values fail closed", twoObjects.ok === false)

const success = model.acceptUpload(0, JSON.stringify({
  ok: true,
  url: "https://i.example.invalid/abc.png"
}))
check("exit 0 + ok + https URL is accepted", success.ok === true)

const badScheme = model.acceptUpload(0, JSON.stringify({
  ok: true,
  url: "HTTPS://i.example.invalid/abc.png"
}))
check("exit 0 with uppercase scheme fails closed", badScheme.ok === false)

const okFalse = model.acceptUpload(0, JSON.stringify({
  ok: false,
  error: { code: "provider", message: "nope" }
}))
check("exit 0 with ok false fails closed", okFalse.ok === false && okFalse.error.code === "provider")

const nonemptyFail = model.acceptUpload(1, JSON.stringify({
  ok: false,
  error: { code: "network", message: "offline" }
}))
check("nonzero exit uses CLI error code", nonemptyFail.ok === false && nonemptyFail.error.code === "network")

const malformedFail = model.acceptUpload(0, "not json")
check("malformed success stdout fails closed", malformedFail.ok === false)

check("network is transient", model.isTransientError("network"))
check("timeout is transient", model.isTransientError("timeout"))
check("auth is not transient", !model.isTransientError("auth"))
check("auth has no auto retry", model.noAutoRetry("auth"))
check("not_ready has no auto retry", model.noAutoRetry("not_ready"))
check("secret_store has no auto retry", model.noAutoRetry("secret_store"))
check("first retry waits 2s", model.retryDelayMs(1) === 2000)
check("second retry waits 8s", model.retryDelayMs(2) === 8000)
check("three attempts then stop", model.canRetryAttempt(2, "network") === true)
check("fourth attempt is not scheduled", model.canRetryAttempt(3, "network") === false)
check("auth is not auto-retried even on first failure", model.canRetryAttempt(1, "auth") === false)

check("delay zero is allowed", model.clampDelaySeconds(0) === 0)
check("delay default for missing", model.clampDelaySeconds(undefined) === model.CAPTURE_DELAY_DEFAULT)
check("delay clamps above max", model.clampDelaySeconds(999) === model.CAPTURE_DELAY_MAX)
check("delay clamps below min", model.clampDelaySeconds(-7) === model.CAPTURE_DELAY_MIN)
check("delay floors floats", model.clampDelaySeconds(2.9) === 2)
check("delay ignores NaN", model.clampDelaySeconds(NaN) === model.CAPTURE_DELAY_DEFAULT)
check("delay ignores non-finite", model.clampDelaySeconds(Infinity) === model.CAPTURE_DELAY_DEFAULT)

let queue = []
for (let i = 0; i < 8; i++) {
  const p = "/tmp/screenshot-2026-09-02_14-22-0" + i + ".png"
  const decision = model.canEnqueue(queue, "", p)
  check("queue accepts item " + (i + 1), decision.ok === true)
  queue = model.enqueue(queue, p, 0)
}
check("queue bound is 8", queue.length === model.QUEUE_BOUND)
const ninth = model.canEnqueue(queue, "", "/tmp/screenshot-2026-09-02_14-22-09.png")
check("ninth item is queue_full", ninth.ok === false && ninth.error.code === "queue_full")

const dup = model.canEnqueue(queue, "", "/tmp/screenshot-2026-09-02_14-22-00.png")
check("queued path is deduped", dup.ok === false && dup.error.code === "duplicate")

const inflight = model.canEnqueue([], "/tmp/screenshot-2026-09-02_14-22-00.png", "/tmp/screenshot-2026-09-02_14-22-00.png")
check("in-flight path is deduped", inflight.ok === false && inflight.error.code === "duplicate")

const claimed = model.claimPath({}, good)
check("claimPath records canonical path", claimed[good] === true)

const capsMissingSchema = model.capabilitiesCompatible({ minPluginProtocol: 1, capabilities: ["upload.image"] })
check("capabilities without schemaVersion are incompatible", capsMissingSchema === false)
const capsNewProtocol = model.capabilitiesCompatible({ schemaVersion: 1, minPluginProtocol: 2 })
check("minPluginProtocol > 1 is incompatible", capsNewProtocol === false)
const capsWrongSchema = model.capabilitiesCompatible({ schemaVersion: 2, minPluginProtocol: 1, capabilities: ["doctor.image", "upload.image"] })
check("unsupported schemaVersion is incompatible", capsWrongSchema === false)
const capsMissingDoctor = model.capabilitiesCompatible({ schemaVersion: 1, minPluginProtocol: 1, capabilities: ["upload.image"] })
check("missing doctor.image capability is incompatible", capsMissingDoctor === false)
const capsMissingUpload = model.capabilitiesCompatible({ schemaVersion: 1, minPluginProtocol: 1, capabilities: ["doctor.image"] })
check("missing upload.image capability is incompatible", capsMissingUpload === false)
const capsOk = model.capabilitiesCompatible({ schemaVersion: 1, minPluginProtocol: 1, capabilities: ["doctor.image", "upload.image"] })
check("schemaVersion 1 protocol 1 is compatible", capsOk === true)

check("doctor requires image.ready", model.doctorReady({ ok: true, image: { ready: false } }) === false)
check("doctor ok when image.ready", model.doctorReady({ ok: true, image: { ready: true } }) === true)

const status = model.statusPayload({
  state: "idle",
  readiness: "ready",
  queueLength: 0,
  copyUrlToClipboard: true,
  notifyOnComplete: true,
  openUrlOnNotificationClick: false,
  captureMode: "smart",
  delaySeconds: 7,
  countdownRemaining: 0,
  last: null
})
check("status JSON has no autoUploadEnabled", !Object.prototype.hasOwnProperty.call(status, "autoUploadEnabled"))
check("status plugin id matches", status.pluginId === "io.github.sharex.omaxerahs")
check("status schemaVersion is 1", status.schemaVersion === 1)
check("status exposes clamped delaySeconds", status.delaySeconds === 7)

const countdownStatus = model.statusPayload({
  state: "countdown",
  readiness: "ready",
  queueLength: 0,
  copyUrlToClipboard: true,
  notifyOnComplete: true,
  openUrlOnNotificationClick: false,
  captureMode: "smart",
  delaySeconds: 5,
  countdownRemaining: 3,
  last: null
})
check("status carries countdownRemaining", countdownStatus.countdownRemaining === 3)

const idleStatus = model.statusPayload({
  state: "idle",
  readiness: "ready",
  queueLength: 0,
  captureMode: "smart",
  last: null
})
check("idle status zeroes countdownRemaining", idleStatus.countdownRemaining === 0)

const invalidMode = JSON.parse(model.errorJson("invalid_mode", "nope"))
check("invalid_mode error JSON", invalidMode.ok === false && invalidMode.error.code === "invalid_mode")

const accepted = JSON.parse(model.acceptedJson("capturing"))
check("capture accept JSON returns immediately-shaped payload", accepted.ok === true && accepted.accepted === true && accepted.state === "capturing")

pass("all model tests")
