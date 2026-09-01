// Pure queue, path, and JSON helpers for the OmaXerahs service.
// Qt-free so tests can load this file under node without QML.

var PLUGIN_ID = "io.github.sharex.omaxerahs"
var SCHEMA_VERSION = 1
var QUEUE_BOUND = 8
var CAPTURE_MODES = ["smart", "region", "windows", "fullscreen"]
var TRANSIENT_CODES = ["network", "timeout"]
var NO_AUTO_RETRY_CODES = ["auth", "not_ready", "secret_store"]
var SCREENSHOT_BASENAME = /^screenshot-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.png$/

function isCaptureMode(mode) {
  var value = String(mode === undefined || mode === null ? "" : mode)
  for (var i = 0; i < CAPTURE_MODES.length; i++) {
    if (CAPTURE_MODES[i] === value) return true
  }
  return false
}

function basename(path) {
  var value = String(path === undefined || path === null ? "" : path)
  var cut = value.lastIndexOf("/")
  if (cut === -1) cut = value.lastIndexOf("\\")
  return cut === -1 ? value : value.substring(cut + 1)
}

function isHttpUrl(url) {
  if (typeof url !== "string") return false
  return url.indexOf("http://") === 0 || url.indexOf("https://") === 0
}

function hostFromUrl(url) {
  if (!isHttpUrl(url)) return ""
  var rest = url.substring(url.indexOf("://") + 3)
  var slash = rest.indexOf("/")
  var hostport = slash === -1 ? rest : rest.substring(0, slash)
  var at = hostport.lastIndexOf("@")
  if (at !== -1) hostport = hostport.substring(at + 1)
  return hostport
}

function errorObject(code, message) {
  return {
    ok: false,
    error: {
      code: String(code || "provider"),
      message: String(message || code || "error")
    }
  }
}

function errorJson(code, message) {
  return JSON.stringify(errorObject(code, message))
}

function acceptedJson(state, extra) {
  var payload = {
    ok: true,
    accepted: true,
    schemaVersion: SCHEMA_VERSION,
    pluginId: PLUGIN_ID,
    state: String(state || "")
  }
  if (extra && typeof extra === "object") {
    for (var key in extra) payload[key] = extra[key]
  }
  return JSON.stringify(payload)
}

function parseOneJsonObject(text) {
  var raw = String(text === undefined || text === null ? "" : text)
  var trimmed = raw.replace(/^\uFEFF/, "").trim()
  if (!trimmed) return errorObject("invalid_json", "stdout was empty")

  var value
  try {
    value = JSON.parse(trimmed)
  } catch (e) {
    return errorObject("invalid_json", "stdout was not exactly one JSON object")
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return errorObject("invalid_json", "stdout was not a JSON object")
  }

  return { ok: true, value: value }
}

function acceptUpload(exitCode, stdout) {
  var parsed = parseOneJsonObject(stdout)
  if (Number(exitCode) !== 0) {
    if (parsed.ok && parsed.value && parsed.value.error) {
      return errorObject(parsed.value.error.code || "provider", parsed.value.error.message || "omaxerahs upload failed")
    }
    if (!parsed.ok) return parsed
    return errorObject("provider", "omaxerahs upload failed")
  }

  if (!parsed.ok) return parsed
  var value = parsed.value
  if (value.ok !== true) {
    if (value.error) {
      return errorObject(value.error.code || "provider", value.error.message || "upload was not successful")
    }
    return errorObject("provider", "upload was not successful")
  }

  if (!isHttpUrl(value.url)) {
    return errorObject("provider", "upload result did not include an http(s) URL")
  }

  return { ok: true, value: value }
}

function validateScreenshotPath(path) {
  var value = String(path === undefined || path === null ? "" : path)
  if (value !== value.trim()) {
    return errorObject("invalid_path", "path has surrounding whitespace")
  }
  if (!value) return errorObject("invalid_path", "path is empty")
  if (value.indexOf("\0") !== -1 || value.indexOf("\n") !== -1 || value.indexOf("\r") !== -1) {
    return errorObject("invalid_path", "path contains invalid characters")
  }
  if (value.charAt(0) !== "/") {
    return errorObject("invalid_path", "path is not absolute")
  }
  var name = basename(value)
  if (!SCREENSHOT_BASENAME.test(name)) {
    return errorObject("invalid_path", "basename is not an Omarchy screenshot PNG")
  }
  return { ok: true, path: value, filename: name }
}

function capabilitiesCompatible(obj) {
  if (!obj || typeof obj !== "object") return false
  if (obj.schemaVersion === undefined || obj.schemaVersion === null) return false
  var min = obj.minPluginProtocol
  if (min !== undefined && min !== null && Number(min) > 1) return false
  return true
}

function doctorReady(obj) {
  return !!(obj && obj.ok === true && obj.image && obj.image.ready === true)
}

function isTransientError(code) {
  var value = String(code || "")
  for (var i = 0; i < TRANSIENT_CODES.length; i++) {
    if (TRANSIENT_CODES[i] === value) return true
  }
  return false
}

function noAutoRetry(code) {
  var value = String(code || "")
  for (var i = 0; i < NO_AUTO_RETRY_CODES.length; i++) {
    if (NO_AUTO_RETRY_CODES[i] === value) return true
  }
  return false
}

function retryDelayMs(attemptsAlreadyMade) {
  if (Number(attemptsAlreadyMade) <= 1) return 2000
  return 8000
}

function canRetryAttempt(attemptsAlreadyMade, code) {
  if (noAutoRetry(code) || !isTransientError(code)) return false
  return Number(attemptsAlreadyMade) < 3
}

function queueContains(queue, path) {
  var list = Array.isArray(queue) ? queue : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].path === path) return true
  }
  return false
}

function isClaimed(queue, inFlightPath, path) {
  if (!path) return false
  if (inFlightPath && inFlightPath === path) return true
  return queueContains(queue, path)
}

function canEnqueue(queue, inFlightPath, path) {
  var check = validateScreenshotPath(path)
  if (!check.ok) return check
  if (isClaimed(queue, inFlightPath, check.path)) {
    return errorObject("duplicate", "path is already queued or in flight")
  }
  var list = Array.isArray(queue) ? queue : []
  if (list.length >= QUEUE_BOUND) {
    return errorObject("queue_full", "Upload queue is full (" + QUEUE_BOUND + ")")
  }
  return { ok: true, path: check.path, filename: check.filename }
}

function enqueue(queue, path, attempts) {
  var list = Array.isArray(queue) ? queue.slice() : []
  list.push({
    path: path,
    attempts: Number(attempts || 0)
  })
  return list
}

function dequeue(queue) {
  var list = Array.isArray(queue) ? queue : []
  if (list.length === 0) return { queue: list, item: null }
  return { queue: list.slice(1), item: list[0] }
}

function claimPath(claimed, path) {
  var next = {}
  var existing = claimed && typeof claimed === "object" ? claimed : {}
  for (var key in existing) next[key] = existing[key]
  next[path] = true
  return next
}

function readinessMessage(code) {
  switch (String(code || "")) {
    case "ready":
      return ""
    case "cli_missing":
      return "omaxerahs is not on PATH. Install native XerahS so /usr/bin/omaxerahs exists."
    case "cli_incompatible":
      return "omaxerahs is too old or incompatible. Update the native XerahS package."
    case "cli_flatpak":
      return "Flatpak XerahS is not supported. Install native xerahs so /usr/bin/omaxerahs is on PATH."
    case "image_not_ready":
      return "Configure an image destination in the XerahS GUI, then run omaxerahs doctor --json."
    case "secret_store":
      return "The XerahS secret store is not ready. Unlock libsecret or re-enter destination credentials."
    case "secret_store_fallback":
      return "XerahS is using the AES secret-store fallback instead of libsecret."
    default:
      return "OmaXerahs is not ready."
  }
}

function lastResult(fields) {
  var src = fields && typeof fields === "object" ? fields : {}
  return {
    ok: src.ok === true,
    localPath: src.localPath ? String(src.localPath) : "",
    host: src.host ? String(src.host) : "",
    filename: src.filename ? String(src.filename) : "",
    at: src.at ? String(src.at) : "",
    errorCode: src.errorCode === undefined ? null : src.errorCode
  }
}

function persistableLast(last) {
  var row = lastResult(last)
  return {
    ok: row.ok,
    localPath: row.localPath,
    host: row.host,
    filename: row.filename,
    at: row.at,
    errorCode: row.errorCode
  }
}

function statusPayload(fields) {
  var src = fields && typeof fields === "object" ? fields : {}
  return {
    schemaVersion: SCHEMA_VERSION,
    pluginId: PLUGIN_ID,
    state: String(src.state || "not_ready"),
    readiness: String(src.readiness || "cli_missing"),
    queueLength: Number(src.queueLength || 0),
    copyUrlToClipboard: src.copyUrlToClipboard !== false,
    notifyOnComplete: src.notifyOnComplete !== false,
    openUrlOnNotificationClick: src.openUrlOnNotificationClick === true,
    captureMode: isCaptureMode(src.captureMode) ? String(src.captureMode) : "smart",
    last: src.last === undefined ? null : src.last
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    SCHEMA_VERSION: SCHEMA_VERSION,
    QUEUE_BOUND: QUEUE_BOUND,
    CAPTURE_MODES: CAPTURE_MODES,
    SCREENSHOT_BASENAME: SCREENSHOT_BASENAME,
    isCaptureMode: isCaptureMode,
    basename: basename,
    isHttpUrl: isHttpUrl,
    hostFromUrl: hostFromUrl,
    errorObject: errorObject,
    errorJson: errorJson,
    acceptedJson: acceptedJson,
    parseOneJsonObject: parseOneJsonObject,
    acceptUpload: acceptUpload,
    validateScreenshotPath: validateScreenshotPath,
    capabilitiesCompatible: capabilitiesCompatible,
    doctorReady: doctorReady,
    isTransientError: isTransientError,
    noAutoRetry: noAutoRetry,
    retryDelayMs: retryDelayMs,
    canRetryAttempt: canRetryAttempt,
    queueContains: queueContains,
    isClaimed: isClaimed,
    canEnqueue: canEnqueue,
    enqueue: enqueue,
    dequeue: dequeue,
    claimPath: claimPath,
    readinessMessage: readinessMessage,
    lastResult: lastResult,
    persistableLast: persistableLast,
    statusPayload: statusPayload
  }
}
