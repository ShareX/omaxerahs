import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.sharex.omaxerahs"

  readonly property var uploadService: bar?.shell?.serviceFor("io.github.sharex.omaxerahs")
  readonly property string captureMode: Model.isCaptureMode(setting("captureMode", "smart"))
    ? String(setting("captureMode", "smart"))
    : "smart"

  readonly property string serviceState: uploadService ? String(uploadService.state || "not_ready") : "not_ready"
  readonly property string lastHost: uploadService ? String(uploadService.lastHost || "") : ""

  readonly property string statusGlyph: {
    if (serviceState === "uploading" || serviceState === "queued") return "󰇚"
    if (serviceState === "capturing") return "󰹑"
    if (serviceState === "failed" || serviceState === "not_ready") return "󰅙"
    if (serviceState === "succeeded") return "󰄬"
    return "󰆣"
  }

  readonly property string statusLabel: {
    if (serviceState === "uploading" || serviceState === "queued") return "Uploading"
    if (serviceState === "capturing") return "Capture"
    if (serviceState === "failed") return "Failed"
    if (serviceState === "not_ready") return "Not ready"
    if (lastHost !== "") return lastHost
    return "Ready"
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("uploadService" in target) target.uploadService = root.uploadService
  }

  function syncSettings() {
    if (!uploadService || typeof uploadService.applySettings !== "function") return
    uploadService.applySettings({
      copyUrlToClipboard: root.setting("copyUrlToClipboard", true),
      notifyOnComplete: root.setting("notifyOnComplete", true),
      openUrlOnNotificationClick: root.setting("openUrlOnNotificationClick", false),
      captureMode: root.captureMode
    })
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function togglePanel() {
    root.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    root.injectPanel()
    root.syncSettings()
  }
  onSettingsChanged: {
    root.injectPanel()
    root.syncSettings()
  }
  onUploadServiceChanged: {
    root.injectPanel()
    root.syncSettings()
  }

  Component.onCompleted: root.syncSettings()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : (root.statusGlyph + " " + root.statusLabel)
    labelVisible: !root.vertical
    hasVisualContent: true
    dimmed: root.serviceState === "not_ready"
    active: root.serviceState === "uploading" || root.serviceState === "queued" || root.serviceState === "capturing"
    tooltipText: "Left-click captures and uploads · Right-click opens the panel"
    foreground: {
      if (!root.bar) return Color.foreground
      if (root.serviceState === "uploading" || root.serviceState === "queued") return Color.accent
      if (root.serviceState === "not_ready" || root.serviceState === "failed") return Qt.darker(root.bar.barForeground, 1.5)
      return root.bar.barForeground
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.togglePanel()
        return
      }
      if (b === Qt.MiddleButton) {
        if (root.uploadService) root.uploadService.retry()
        return
      }
      if (root.uploadService) root.uploadService.capture(root.captureMode)
    }

    OpticalGlyph {
      visible: root.vertical
      anchors.centerIn: parent
      text: root.statusGlyph
      fontFamily: button.fontFamily
      fontSize: button.fontSize
      color: button.foreground
    }
  }
}
