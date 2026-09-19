import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null
  property var pluginRegistry: null

  property bool copyUrlToClipboard: true
  property bool notifyOnComplete: true
  property bool openUrlOnNotificationClick: false
  property string captureMode: "smart"
  property int delaySeconds: Model.CAPTURE_DELAY_DEFAULT
  property int countdownRemaining: 0
  property string pendingDelayedMode: ""

  property string state: "not_ready"
  property string readiness: "cli_missing"
  property string readinessMessage: Model.readinessMessage("cli_missing")
  property bool secretStoreFallback: false
  property bool tearingDown: false
  property bool queueFullNotified: false
  property bool captureTimedOut: false
  property bool uploadTimedOut: false

  property var uploadQueue: []
  property string inFlightPath: ""
  property int inFlightAttempts: 0
  readonly property int queueLength: Array.isArray(uploadQueue) ? uploadQueue.length : 0

  property bool lastOk: false
  property string lastLocalPath: ""
  property string lastHost: ""
  property string lastFilename: ""
  property string lastAt: ""
  property var lastErrorCode: null
  readonly property bool canRetry: !lastOk && lastLocalPath !== ""

  property string probeKind: ""
  property string pathAction: ""
  property string pathSubject: ""
  property string pendingPath: ""
  property string pendingPathAction: ""
  property string captureOutput: ""
  property string uploadOutput: ""
  property string probeOutput: ""
  property string pathOutput: ""

  readonly property string pluginId: Model.PLUGIN_ID
  readonly property string home: Quickshell.env("HOME")
  readonly property string xdgStateHome: Quickshell.env("XDG_STATE_HOME")
  readonly property string stateDir: xdgStateHome && xdgStateHome !== ""
    ? (xdgStateHome + "/omaxerahs/")
    : (home + "/.local/state/omaxerahs/")
  readonly property int stdoutCapBytes: 65536
  readonly property int probeTimeoutSec: 15
  readonly property int pathTimeoutSec: 10
  readonly property int captureTimeoutSec: 120
  readonly property int uploadTimeoutSec: 300
  readonly property int supervisorTimeoutExit: 124
  readonly property int supervisorOverflowExit: 125
  readonly property string boundedRunner: {
    var raw = String(Qt.resolvedUrl("run-bounded"))
    if (raw.indexOf("file://") === 0) return decodeURIComponent(raw.substring(7))
    return raw
  }

  function boundedCommand(timeoutSec, argv) {
    var cmd = [
      root.boundedRunner,
      "--timeout", String(timeoutSec),
      "--max-bytes", String(root.stdoutCapBytes),
      "--"
    ]
    for (var i = 0; i < argv.length; i++) cmd.push(argv[i])
    return cmd
  }

  function applySettings(obj) {
    if (!obj || typeof obj !== "object") return
    if ("copyUrlToClipboard" in obj) copyUrlToClipboard = !!obj.copyUrlToClipboard
    if ("notifyOnComplete" in obj) notifyOnComplete = !!obj.notifyOnComplete
    if ("openUrlOnNotificationClick" in obj) openUrlOnNotificationClick = !!obj.openUrlOnNotificationClick
    if ("captureMode" in obj && Model.isCaptureMode(obj.captureMode)) captureMode = String(obj.captureMode)
    if ("captureDelaySeconds" in obj) delaySeconds = Model.clampDelaySeconds(obj.captureDelaySeconds)
  }

  function statusJson() {
    return JSON.stringify(Model.statusPayload({
      state: root.state,
      readiness: root.readiness,
      queueLength: root.queueLength,
      copyUrlToClipboard: root.copyUrlToClipboard,
      notifyOnComplete: root.notifyOnComplete,
      openUrlOnNotificationClick: root.openUrlOnNotificationClick,
      captureMode: root.captureMode,
      delaySeconds: root.delaySeconds,
      countdownRemaining: root.state === "countdown" ? root.countdownRemaining : 0,
      last: root.lastLocalPath === "" && root.lastAt === "" ? null : {
        ok: root.lastOk,
        localPath: root.lastLocalPath,
        host: root.lastHost,
        filename: root.lastFilename,
        at: root.lastAt,
        errorCode: root.lastErrorCode
      }
    }))
  }

  function capture(mode) {
    var value = String(mode === undefined || mode === null ? "" : mode)
    if (!Model.isCaptureMode(value)) {
      return Model.errorJson("invalid_mode", "mode must be smart, region, windows, or fullscreen")
    }
    if (root.tearingDown) {
      return Model.errorJson("cancelled", "service is shutting down")
    }
    if (root.readiness !== "ready") {
      root.startReadiness()
      return Model.errorJson(root.readiness, root.readinessMessage || "OmaXerahs is not ready")
    }
    if (captureProc.running || root.state === "capturing") {
      return Model.errorJson("busy", "A capture is already in progress")
    }
    if (root.queueLength >= Model.QUEUE_BOUND) {
      root.notifyQueueFull()
      return Model.errorJson("queue_full", "Upload queue is full (" + Model.QUEUE_BOUND + ")")
    }

    root.state = "capturing"
    root.captureTimedOut = false
    captureTimeout.restart()
    captureProc.command = root.boundedCommand(root.captureTimeoutSec, ["omarchy", "capture", "screenshot", value, "save"])
    captureProc.running = true
    return Model.acceptedJson("capturing")
  }

  function captureDelayed(mode) {
    var value = String(mode === undefined || mode === null ? "" : mode)
    if (!Model.isCaptureMode(value)) {
      return Model.errorJson("invalid_mode", "mode must be smart, region, windows, or fullscreen")
    }
    if (root.tearingDown) {
      return Model.errorJson("cancelled", "service is shutting down")
    }
    if (root.state === "countdown") {
      return Model.errorJson("busy", "A timed capture is already counting down")
    }
    if (captureProc.running || root.state === "capturing") {
      return Model.errorJson("busy", "A capture is already in progress")
    }

    var seconds = Model.clampDelaySeconds(root.delaySeconds)
    if (seconds <= 0) return root.capture(value)

    root.pendingDelayedMode = value
    root.countdownRemaining = seconds
    root.state = "countdown"
    countdownTimer.restart()
    return Model.acceptedJson("countdown", {
      countdownRemaining: root.countdownRemaining,
      captureMode: value
    })
  }

  function cancelCapture() {
    if (root.state !== "countdown") {
      return Model.acceptedJson(root.state === "capturing" ? "capturing" : root.state)
    }
    countdownTimer.stop()
    root.pendingDelayedMode = ""
    root.countdownRemaining = 0
    if (root.lastErrorCode && !root.lastOk) root.state = "failed"
    else if (root.readiness !== "ready") root.state = "not_ready"
    else root.state = "idle"
    return Model.acceptedJson(root.state)
  }

  function onCountdownTick() {
    if (root.state !== "countdown") return
    root.countdownRemaining = Math.max(0, root.countdownRemaining - 1)
    if (root.countdownRemaining > 0) return

    var mode = root.pendingDelayedMode
    root.pendingDelayedMode = ""
    if (!Model.isCaptureMode(mode)) {
      cancelCapture()
      return
    }
    var result = root.capture(mode)
    if (result && typeof result === "string") {
      var parsed = Model.parseOneJsonObject(result)
      if (!parsed.ok) {
        root.countdownRemaining = 0
        if (root.lastErrorCode && !root.lastOk) root.state = "failed"
        else if (root.readiness !== "ready") root.state = "not_ready"
        else root.state = "idle"
      }
    }
  }

  function retry() {
    if (root.tearingDown) return Model.errorJson("cancelled", "service is shutting down")
    if (!root.canRetry) return Model.errorJson("nothing_to_retry", "No failed local screenshot to retry")

    var decision = Model.canEnqueue(root.uploadQueue, root.inFlightPath, root.lastLocalPath)
    if (!decision.ok && decision.error && decision.error.code === "duplicate") {
      root.pumpWorker()
      return Model.acceptedJson(root.state === "capturing" ? "capturing" : (uploadProc.running ? "uploading" : "queued"))
    }
    if (!decision.ok) {
      if (decision.error && decision.error.code === "queue_full") root.notifyQueueFull()
      return JSON.stringify(decision)
    }

    root.uploadQueue = Model.enqueue(root.uploadQueue, decision.path, 0)
    root.queueFullNotified = false
    if (root.state !== "capturing") root.state = "queued"
    root.pumpWorker()
    return Model.acceptedJson(root.state)
  }

  function onPanelOpened() {
    if (root.state === "not_ready" || root.readiness !== "ready") root.startReadiness()
  }

  function refreshReadiness() {
    root.startReadiness()
  }

  function startReadiness() {
    if (root.tearingDown || probeProc.running) return
    root.probeKind = "which"
    probeProc.command = root.boundedCommand(root.probeTimeoutSec, ["which", "omaxerahs"])
    probeProc.running = true
  }

  function setNotReady(code) {
    root.readiness = String(code || "cli_missing")
    root.readinessMessage = Model.readinessMessage(root.readiness)
    if (root.state === "capturing" || root.state === "uploading" || root.state === "queued") return
    if (root.inFlightPath !== "" || root.queueLength > 0) return
    root.state = "not_ready"
  }

  function setReady() {
    root.readiness = "ready"
    root.readinessMessage = root.secretStoreFallback ? Model.readinessMessage("secret_store_fallback") : ""
    if (root.state === "not_ready") root.state = "idle"
  }

  function restoreStateAfterCapture() {
    if (uploadProc.running || root.inFlightPath !== "") {
      if (root.state !== "capturing") root.state = "uploading"
      return
    }
    if (root.queueLength > 0) {
      root.state = "queued"
      root.pumpWorker()
      return
    }
    if (root.lastErrorCode) root.state = "failed"
    else if (root.readiness !== "ready") root.state = "not_ready"
    else root.state = "idle"
  }

  function setLast(fields) {
    var row = Model.lastResult(fields)
    root.lastOk = row.ok
    root.lastLocalPath = row.localPath
    root.lastHost = row.host
    root.lastFilename = row.filename
    root.lastAt = row.at || new Date().toISOString()
    root.lastErrorCode = row.errorCode
    lastFile.setText(JSON.stringify(Model.persistableLast({
      ok: root.lastOk,
      localPath: root.lastLocalPath,
      host: root.lastHost,
      filename: root.lastFilename,
      at: root.lastAt,
      errorCode: root.lastErrorCode
    }), null, 2) + "\n")
  }

  function hydrateLast(raw) {
    var parsed = Model.parseOneJsonObject(raw)
    if (!parsed.ok || !parsed.value) return
    var row = Model.lastResult(parsed.value)
    if (!row.localPath && !row.filename && !row.at) return
    root.lastOk = row.ok
    root.lastLocalPath = row.localPath
    root.lastHost = row.host
    root.lastFilename = row.filename
    root.lastAt = row.at
    root.lastErrorCode = row.errorCode
  }

  function sendNotification(urgency, glyph, headline, body, imagePath, urlForClick) {
    if (root.tearingDown) return
    var args = ["omarchy-notification-send", "--app-name", "OmaXerahs", "-g", String(glyph || "󰆣"), "-u", String(urgency || "normal"), String(headline || "OmaXerahs")]
    if (body) args.push(String(body))
    if (imagePath) {
      args.push("--image")
      args.push(String(imagePath))
    }
    if (urlForClick && root.openUrlOnNotificationClick) {
      args.push("--exec")
      args.push("xdg-open")
      args.push(String(urlForClick))
    }
    Quickshell.execDetached(args)
  }

  function notifyQueueFull() {
    if (root.queueFullNotified) return
    root.queueFullNotified = true
    root.sendNotification("normal", "󰅙", "Upload queue full", "Wait for an upload to finish before capturing again.", "", "")
  }

  function failCapture(code, message) {
    root.setLast({
      ok: false,
      localPath: "",
      host: "",
      filename: "",
      at: new Date().toISOString(),
      errorCode: code || "provider"
    })
    root.sendNotification("critical", "󰹑", "Screenshot capture failed", message || "grim did not write a screenshot.", "", "")
    if (uploadProc.running || root.inFlightPath !== "") root.state = "uploading"
    else root.state = "failed"
    root.startReadiness()
  }

  function onCaptureExited(exitCode, stdout) {
    captureTimeout.stop()
    if (root.tearingDown) return
    if (root.captureTimedOut) {
      root.captureTimedOut = false
      root.failCapture("timeout", "screenshot capture timed out")
      return
    }

    var text = String(stdout || "").trim()
    var code = Number(exitCode)
    if (code === root.supervisorTimeoutExit || root.captureTimedOut) {
      root.captureTimedOut = false
      root.failCapture("timeout", "screenshot capture timed out")
      return
    }
    if (code === root.supervisorOverflowExit) {
      root.failCapture("invalid_json", "capture stdout exceeded the byte cap")
      return
    }
    if (code === 0 && text === "") {
      root.restoreStateAfterCapture()
      root.startReadiness()
      return
    }
    if (code !== 0) {
      root.failCapture("provider", "grim failed to capture a screenshot.")
      return
    }

    var check = Model.validateScreenshotPath(text)
    if (!check.ok) {
      root.failCapture("invalid_path", check.error ? check.error.message : "screenshot path was rejected")
      return
    }

    root.startPathCheck(check.path, "accept")
  }

  function startPathCheck(path, action) {
    if (root.tearingDown) return
    if (pathProc.running || statProc.running) {
      root.pendingPath = path
      root.pendingPathAction = action
      return
    }
    root.pathAction = action
    root.pathSubject = path
    pathProc.command = root.boundedCommand(root.pathTimeoutSec, ["realpath", "--canonicalize-existing", "--", path])
    pathProc.running = true
  }

  function flushPendingPathCheck() {
    if (root.pendingPath === "") return
    var path = root.pendingPath
    var action = root.pendingPathAction
    root.pendingPath = ""
    root.pendingPathAction = ""
    root.startPathCheck(path, action)
  }

  function onPathResolved(exitCode, stdout) {
    if (root.tearingDown) return
    var canonical = String(stdout || "").trim()
    var code = Number(exitCode)
    if (code === root.supervisorTimeoutExit || code === root.supervisorOverflowExit) {
      if (root.pathAction === "accept") root.failCapture("timeout", "path check timed out")
      else root.failUpload("timeout", "path check timed out", root.pathSubject)
      root.flushPendingPathCheck()
      return
    }
    if (code !== 0 || canonical === "") {
      if (root.pathAction === "accept") root.failCapture("invalid_path", "screenshot path could not be canonicalized")
      else root.failUpload("invalid_path", "file disappeared before upload", root.pathSubject)
      root.flushPendingPathCheck()
      return
    }

    var check = Model.validateScreenshotPath(canonical)
    if (!check.ok) {
      if (root.pathAction === "accept") root.failCapture("invalid_path", check.error ? check.error.message : "canonical path was rejected")
      else root.failUpload("invalid_path", "canonical path was rejected", root.pathSubject)
      root.flushPendingPathCheck()
      return
    }

    if (root.pathAction === "restat" && canonical !== root.pathSubject) {
      root.failUpload("invalid_path", "path changed before upload", root.pathSubject)
      root.flushPendingPathCheck()
      return
    }

    root.pathSubject = canonical
    statProc.command = ["test", "-f", canonical]
    statProc.running = true
  }

  function onStatExited(exitCode) {
    if (root.tearingDown) return
    if (Number(exitCode) !== 0) {
      if (root.pathAction === "accept") root.failCapture("invalid_path", "screenshot is not a regular file")
      else root.failUpload("invalid_path", "screenshot is not a regular file", root.pathSubject)
      root.flushPendingPathCheck()
      return
    }

    if (root.pathAction === "accept") {
      var decision = Model.canEnqueue(root.uploadQueue, root.inFlightPath, root.pathSubject)
      if (!decision.ok) {
        if (decision.error && decision.error.code === "duplicate") {
          root.restoreStateAfterCapture()
          root.flushPendingPathCheck()
          return
        }
        if (decision.error && decision.error.code === "queue_full") {
          root.notifyQueueFull()
          root.failCapture("queue_full", decision.error.message)
          root.flushPendingPathCheck()
          return
        }
        root.failCapture(decision.error ? decision.error.code : "invalid_path", decision.error ? decision.error.message : "could not queue screenshot")
        root.flushPendingPathCheck()
        return
      }
      root.uploadQueue = Model.enqueue(root.uploadQueue, decision.path, 0)
      root.queueFullNotified = false
      root.restoreStateAfterCapture()
      root.pumpWorker()
      root.flushPendingPathCheck()
      return
    }

    root.startUpload(root.pathSubject)
    root.flushPendingPathCheck()
  }

  function pumpWorker() {
    if (root.tearingDown) return
    if (uploadProc.running || pathProc.running || statProc.running) return
    if (root.inFlightPath !== "") return
    if (retryTimer.running) return
    if (root.queueLength === 0) {
      if (root.state === "queued" || root.state === "uploading" || root.state === "succeeded") {
        if (root.lastErrorCode && !root.lastOk) root.state = "failed"
        else if (root.readiness !== "ready") root.state = "not_ready"
        else root.state = "idle"
      }
      return
    }

    var next = Model.dequeue(root.uploadQueue)
    root.uploadQueue = next.queue
    if (!next.item || !next.item.path) {
      root.pumpWorker()
      return
    }
    root.inFlightPath = next.item.path
    root.inFlightAttempts = Number(next.item.attempts || 0)
    if (root.state !== "capturing") root.state = "uploading"
    root.startPathCheck(root.inFlightPath, "restat")
  }

  function startUpload(path) {
    if (root.tearingDown) {
      root.clearInFlight()
      return
    }
    if (root.state !== "capturing") root.state = "uploading"
    root.uploadTimedOut = false
    uploadTimeout.restart()
    uploadProc.command = root.boundedCommand(root.uploadTimeoutSec, ["omaxerahs", "upload", "--json", "--", path])
    uploadProc.running = true
  }

  function clearInFlight() {
    root.inFlightPath = ""
    root.inFlightAttempts = 0
  }

  function failUpload(code, message, path) {
    uploadTimeout.stop()
    var errorCode = String(code || "provider")
    var filename = Model.basename(path || root.inFlightPath)
    root.setLast({
      ok: false,
      localPath: path || root.inFlightPath,
      host: "",
      filename: filename,
      at: new Date().toISOString(),
      errorCode: errorCode
    })

    if (Model.canRetryAttempt(root.inFlightAttempts + 1, errorCode)) {
      var attempts = root.inFlightAttempts + 1
      var retryPath = path || root.inFlightPath
      root.clearInFlight()
      retryTimer.interval = Model.retryDelayMs(attempts)
      retryTimer.retryPath = retryPath
      retryTimer.retryAttempts = attempts
      retryTimer.restart()
      if (root.state !== "capturing") root.state = "queued"
      return
    }

    root.sendNotification("critical", "󰅙", "Screenshot upload failed", message || errorCode, path || "", "")
    if (errorCode === "not_ready" || errorCode === "secret_store") {
      root.setNotReady(errorCode === "secret_store" ? "secret_store" : "image_not_ready")
    }
    root.clearInFlight()
    if (root.state !== "capturing") root.state = "failed"
    root.startReadiness()
  }

  function succeedUpload(value, path) {
    uploadTimeout.stop()
    var url = value && value.url ? String(value.url) : ""
    var filename = (value && value.filename) ? String(value.filename) : Model.basename(path)
    var host = Model.hostFromUrl(url)
    root.setLast({
      ok: true,
      localPath: path,
      host: host,
      filename: filename,
      at: new Date().toISOString(),
      errorCode: null
    })
    if (root.copyUrlToClipboard) Quickshell.execDetached(["wl-copy", url])
    if (root.notifyOnComplete) {
      root.sendNotification("normal", "󰆣", "Screenshot uploaded", host + " / " + filename, path, url)
    }
    root.clearInFlight()
    if (root.queueLength > 0) {
      if (root.state !== "capturing") root.state = "queued"
      root.pumpWorker()
      return
    }
    if (root.state !== "capturing") {
      root.state = "succeeded"
      idleAfterSuccess.restart()
    }
  }

  function onUploadExited(exitCode, stdout) {
    if (root.tearingDown) {
      root.clearInFlight()
      return
    }
    var code = Number(exitCode)
    if (code === root.supervisorTimeoutExit || root.uploadTimedOut) {
      root.uploadTimedOut = false
      root.failUpload("timeout", "upload timed out", root.inFlightPath)
      return
    }
    if (code === root.supervisorOverflowExit) {
      root.failUpload("invalid_json", "upload stdout exceeded the byte cap", root.inFlightPath)
      return
    }
    var accepted = Model.acceptUpload(exitCode, stdout)
    var path = root.inFlightPath
    if (!accepted.ok) {
      root.failUpload(accepted.error ? accepted.error.code : "provider", accepted.error ? accepted.error.message : "upload failed", path)
      return
    }
    root.succeedUpload(accepted.value, path)
  }

  function stopProcess(proc) {
    if (proc && proc.running) proc.running = false
  }

  function onProbeExited(exitCode, stdout) {
    if (root.tearingDown) return
    var text = String(stdout || "").trim()
    var kind = root.probeKind

    var code = Number(exitCode)
    if (code === root.supervisorTimeoutExit || code === root.supervisorOverflowExit) {
      root.setNotReady(kind === "which" ? "cli_missing" : "cli_incompatible")
      return
    }

    if (kind === "which") {
      if (code === 0 && text !== "") {
        root.probeKind = "capabilities"
        probeProc.command = root.boundedCommand(root.probeTimeoutSec, ["omaxerahs", "capabilities", "--json"])
        probeProc.running = true
        return
      }
      var flatpakId = String(Quickshell.env("FLATPAK_ID") || "")
      if (flatpakId.toLowerCase().indexOf("xerahs") !== -1) {
        root.setNotReady("cli_flatpak")
        return
      }
      root.probeKind = "flatpak"
      probeProc.command = root.boundedCommand(root.probeTimeoutSec, ["flatpak", "info", "com.xerahs.XerahS"])
      probeProc.running = true
      return
    }

    if (kind === "flatpak") {
      root.setNotReady(code === 0 ? "cli_flatpak" : "cli_missing")
      return
    }

    if (kind === "capabilities") {
      var caps = Model.parseOneJsonObject(stdout)
      if (code !== 0 || !caps.ok || !Model.capabilitiesCompatible(caps.value)) {
        root.setNotReady("cli_incompatible")
        return
      }
      root.probeKind = "doctor"
      probeProc.command = root.boundedCommand(root.probeTimeoutSec, ["omaxerahs", "doctor", "--json"])
      probeProc.running = true
      return
    }

    if (kind === "doctor") {
      var doctor = Model.parseOneJsonObject(stdout)
      if (code !== 0 || !doctor.ok || !Model.doctorReady(doctor.value)) {
        var code = "image_not_ready"
        if (doctor.ok && doctor.value && doctor.value.error && doctor.value.error.code === "secret_store") {
          code = "secret_store"
        }
        root.setNotReady(code)
        return
      }
      root.secretStoreFallback = !!(doctor.value.secretStore && doctor.value.secretStore.fallback)
      root.setReady()
    }
  }

  Component.onCompleted: {
    mkdirProc.command = ["mkdir", "-p", root.stateDir]
    mkdirProc.running = true
    root.startReadiness()
  }

  Component.onDestruction: {
    root.tearingDown = true
    captureTimeout.stop()
    uploadTimeout.stop()
    retryTimer.stop()
    doctorTimer.stop()
    idleAfterSuccess.stop()
    countdownTimer.stop()
    root.uploadQueue = []
    root.clearInFlight()
    root.stopProcess(captureProc)
    root.stopProcess(uploadProc)
    root.stopProcess(probeProc)
    root.stopProcess(pathProc)
    root.stopProcess(statProc)
    root.stopProcess(mkdirProc)
  }

  Timer {
    id: doctorTimer
    interval: 60000
    repeat: true
    running: root.state === "not_ready" && !root.tearingDown
    onTriggered: root.startReadiness()
  }

  Timer {
    id: captureTimeout
    interval: 120000
    repeat: false
    onTriggered: {
      root.captureTimedOut = true
      root.stopProcess(captureProc)
    }
  }

  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    onTriggered: root.onCountdownTick()
  }

  Timer {
    id: uploadTimeout
    interval: 300000
    repeat: false
    onTriggered: {
      root.uploadTimedOut = true
      root.stopProcess(uploadProc)
    }
  }

  Timer {
    id: retryTimer
    interval: 2000
    repeat: false
    property string retryPath: ""
    property int retryAttempts: 0
    onTriggered: {
      if (root.tearingDown || retryPath === "") return
      var decision = Model.canEnqueue(root.uploadQueue, root.inFlightPath, retryPath)
      if (decision.ok) root.uploadQueue = Model.enqueue(root.uploadQueue, retryPath, retryAttempts)
      root.pumpWorker()
    }
  }

  Timer {
    id: idleAfterSuccess
    interval: 1200
    repeat: false
    onTriggered: {
      if (root.tearingDown) return
      if (root.state !== "succeeded") return
      if (root.queueLength > 0) {
        root.state = "queued"
        root.pumpWorker()
        return
      }
      root.state = "idle"
    }
  }

  Process {
    id: mkdirProc
    running: false
    onExited: lastFile.reload()
  }

  Process {
    id: probeProc
    running: false
    stdout: StdioCollector {
      id: probeStdout
      waitForEnd: true
      onStreamFinished: root.probeOutput = text
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.onProbeExited(exitCode, root.probeOutput || probeStdout.text)
        root.probeOutput = ""
      })
    }
  }

  Process {
    id: captureProc
    running: false
    stdout: StdioCollector {
      id: captureStdout
      waitForEnd: true
      onStreamFinished: root.captureOutput = text
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.onCaptureExited(exitCode, root.captureOutput || captureStdout.text)
        root.captureOutput = ""
      })
    }
  }

  Process {
    id: pathProc
    running: false
    stdout: StdioCollector {
      id: pathStdout
      waitForEnd: true
      onStreamFinished: root.pathOutput = text
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.onPathResolved(exitCode, root.pathOutput || pathStdout.text)
        root.pathOutput = ""
      })
    }
  }

  Process {
    id: statProc
    running: false
    onExited: function(exitCode) { root.onStatExited(exitCode) }
  }

  Process {
    id: uploadProc
    running: false
    stdout: StdioCollector {
      id: uploadStdout
      waitForEnd: true
      onStreamFinished: root.uploadOutput = text
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.onUploadExited(exitCode, root.uploadOutput || uploadStdout.text)
        root.uploadOutput = ""
      })
    }
  }

  FileView {
    id: lastFile
    path: root.stateDir + "last.json"
    printErrors: false
    atomicWrites: true
    onLoaded: root.hydrateLast(text())
    onLoadFailed: { }
  }

  IpcHandler {
    target: "omaxerahs"

    function capture(mode: string): string {
      return root.capture(mode)
    }

    function captureDelayed(mode: string): string {
      return root.captureDelayed(mode)
    }

    function cancel(): string {
      return root.cancelCapture()
    }

    function status(): string {
      return root.statusJson()
    }

    function retry(): string {
      return root.retry()
    }
  }
}
