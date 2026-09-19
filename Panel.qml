import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.sharex.omaxerahs"
  ipcTarget: "omaxerahs"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var uploadService: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.45)

  readonly property string serviceState: uploadService ? String(uploadService.state || "not_ready") : "not_ready"
  readonly property string readinessMessage: uploadService ? String(uploadService.readinessMessage || "") : "OmaXerahs service is not loaded."
  readonly property bool canRetry: uploadService ? uploadService.canRetry === true : false
  readonly property string lastHost: uploadService ? String(uploadService.lastHost || "") : ""
  readonly property string lastFilename: uploadService ? String(uploadService.lastFilename || "") : ""
  readonly property int countdownRemaining: uploadService ? Number(uploadService.countdownRemaining || 0) : 0
  readonly property bool countingDown: serviceState === "countdown"
  readonly property int delaySeconds: {
    var raw = setting("captureDelaySeconds", 3)
    var n = Number(raw)
    if (!isFinite(n) || isNaN(n)) return 3
    n = Math.floor(n)
    if (n < 0) return 0
    if (n > 60) return 60
    return n
  }
  readonly property string delayedButtonLabel: root.countingDown
    ? "Cancel (" + root.countdownRemaining + "s)"
    : (root.delaySeconds > 0 ? "Capture (" + root.delaySeconds + "s)" : "Capture (off)")
  readonly property string lastLine: {
    if (lastHost !== "" && lastFilename !== "") return lastHost + " / " + lastFilename
    if (lastFilename !== "") return lastFilename
    if (lastHost !== "") return lastHost
    return "No screenshot uploaded yet."
  }

  function open() {
    root.controller.show()
    if (uploadService && typeof uploadService.onPanelOpened === "function") uploadService.onPanelOpened()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function captureMode() {
    var mode = setting("captureMode", "smart")
    return mode === undefined || mode === null || mode === "" ? "smart" : String(mode)
  }

  // KeyboardPanel primes WlrKeyboardFocus.Exclusive. If capture starts while
  // that overlay is still open, Hyprland routes keys (including Super+W) and
  // pointer events to it, so slurp never runs and the panel cannot be dismissed.
  function startCapture() {
    var mode = root.captureMode()
    root.close()
    Qt.callLater(function() {
      if (root.uploadService) root.uploadService.capture(mode)
    })
  }

  // Delayed capture keeps the panel open during countdown so the user can
  // abort; only when the timer fires and the actual grim run begins does the
  // overlay drop focus. With delaySeconds <= 0 it degenerates to startCapture.
  function startDelayedCapture() {
    if (root.countingDown) {
      if (root.uploadService) root.uploadService.cancel()
      return
    }
    if (root.delaySeconds <= 0) {
      root.startCapture()
      return
    }
    if (root.uploadService) root.uploadService.captureDelayed(root.captureMode())
  }

  function setDelaySeconds(seconds) {
    var clamped = Number(seconds)
    if (!isFinite(clamped) || isNaN(clamped)) clamped = 3
    clamped = Math.floor(clamped)
    if (clamped < 0) clamped = 0
    if (clamped > 60) clamped = 60
    if (clamped === root.delaySeconds) return

    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry.captureDelaySeconds = clamped

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  onOpenedChanged: if (opened && keyCatcher) Qt.callLater(function() {
    if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
  })

  Connections {
    target: root.uploadService
    function onStateChanged() {
      if (root.opened && root.uploadService && String(root.uploadService.state) === "capturing")
        root.close()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.startCapture()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "c" || t === "C") {
          root.startCapture()
        } else if (t === "d" || t === "D") {
          root.startDelayedCapture()
        } else if (t === "r" || t === "R") {
          if (root.uploadService) root.uploadService.retry()
        } else if (t === "q" || t === "Q") {
          if (root.countingDown && root.uploadService) root.uploadService.cancel()
          else root.close()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "OmaXerahs"
            meta: root.serviceState
            detail: root.lastHost !== "" ? root.lastHost : root.serviceState
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰆣"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            width: parent.width
            visible: root.readinessMessage !== ""
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.readinessMessage
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.lastLine
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: "Capture"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: root.startCapture()
            }

            Button {
              text: root.delayedButtonLabel
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: root.startDelayedCapture()
            }

            Button {
              text: "Cancel"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: {
                if (root.countingDown && root.uploadService) root.uploadService.cancel()
                else root.close()
              }
            }

            Button {
              text: "Retry"
              visible: root.canRetry
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: {
                if (root.uploadService) root.uploadService.retry()
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Capture delay (seconds, 0 = off)"
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            PanelSlider {
              id: delaySlider
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 60
              step: 1
              integer: true
              value: root.delaySeconds
              enabled: !root.countingDown
              onReleased: function(v) { root.setDelaySeconds(v) }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.countingDown
                ? "Capturing in " + root.countdownRemaining + "s (press d or q to cancel)"
                : (root.delaySeconds > 0
                    ? "Capture (d) waits " + root.delaySeconds + "s before invoking grim."
                    : "Capture (d) is off; the delay slider below is also off.")
              color: root.countingDown ? root.contentForeground : root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
