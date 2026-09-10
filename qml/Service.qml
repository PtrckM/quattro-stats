pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "QuattroFormat.js" as Format

// Poller instantiated directly as a child of Panel.qml (not registered as a
// separate "service" plugin kind — the shell's service registry proved
// fragile: it strips manifest.__sourceDir for third-party plugins, and its
// serviceFor() lookup never resolved for this plugin after an Omarchy
// update). Since the widget never allows more than one instance anyway,
// there is nothing a shared service singleton would buy us here.
Item {
  id: root

  // Self-locating: resolve the script relative to this QML file's own
  // location rather than depending on any manifest metadata.
  readonly property string scriptPath: {
    var url = Qt.resolvedUrl("../scripts/quattro-stats.sh")
    return String(url).replace(/^file:\/\//, "")
  }

  property int refreshIntervalMs: 2000
  property int historyLimit: 60
  property int consumers: 0

  property var stats: ({})
  property string error: ""
  property bool refreshPending: false

  property var cpuHistory: []
  property var netHistory: []
  property var diskHistory: []

  readonly property bool wanted: consumers > 0

  function acquire() { root.consumers++ }
  function release() { root.consumers = Math.max(0, root.consumers - 1) }

  // ---- Durable widget settings (barItems / panelSections / usageStyle).
  // These are also written to the widget's inline shell.json entry via
  // persistPluginSetting (so any generic settings UI stays in sync), but
  // that entry does not survive `omarchy plugin disable` — the shell's own
  // PluginRegistry drops a bar-widget's whole layout entry on disable and
  // rebuilds it bare on the next enable. Keeping our own copy here means a
  // disable/enable cycle (or a plugin update) doesn't silently reset the
  // user's choices back to defaults.
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/ptrck.quattro-stats"
  readonly property string statePath: stateDir + "/settings.json"
  property var persistedSettings: ({})
  property bool persistedSettingsReady: false

  function loadPersistedSettings(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && typeof parsed === "object") root.persistedSettings = parsed
    } catch (e) {
      // no valid state yet — start clean
    }
    root.persistedSettingsReady = true
  }

  function savePersistedSetting(name, value) {
    var next = {}
    for (var k in root.persistedSettings) next[k] = root.persistedSettings[k]
    next[name] = value
    root.persistedSettings = next
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  Process {
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: settingsFile.reload()
  }

  FileView {
    id: settingsFile
    path: root.statePath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadPersistedSettings(text())
    onLoadFailed: root.persistedSettingsReady = true
  }

  // ---- High-usage notifications. Fires once when a metric crosses above
  // its threshold, and resets (so it can fire again) only once the metric
  // drops a few points back below it — avoids spamming a notification every
  // poll while hovering right at the line.
  readonly property real alertThreshold: 90
  readonly property real alertHysteresis: 5
  property var alertState: ({ cpu: false, gpu: false, mem: false, storage: false })

  function checkAlert(key, label, value) {
    if (value === undefined || value === null) return
    var wasAlerting = root.alertState[key] === true
    if (!wasAlerting && value >= root.alertThreshold) {
      var next = {}
      for (var k in root.alertState) next[k] = root.alertState[k]
      next[key] = true
      root.alertState = next
      Quickshell.execDetached([
        "omarchy-notification-send",
        "--app-name", "Quattro Stats",
        "--urgency", "critical",
        label + " usage high",
        Math.round(value) + "% used (threshold " + root.alertThreshold + "%)"
      ])
    } else if (wasAlerting && value < root.alertThreshold - root.alertHysteresis) {
      var reset = {}
      for (var k2 in root.alertState) reset[k2] = root.alertState[k2]
      reset[key] = false
      root.alertState = reset
    }
  }

  function refresh() {
    if (!root.wanted || root.scriptPath === "") return
    if (pollProc.running) {
      root.refreshPending = true
      return
    }
    pollProc.running = true
  }

  Process {
    id: pollProc
    command: root.scriptPath !== "" ? [root.scriptPath] : []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed
        try {
          parsed = JSON.parse(text)
        } catch (e) {
          root.error = "invalid collector output"
          return
        }
        root.stats = parsed
        root.error = parsed.ok ? "" : "collector reported an error"

        var cpu = parsed.cpu || {}
        var net = parsed.network || {}
        var diskio = parsed.diskio || {}
        var memory = parsed.memory || {}
        var disk = parsed.disk || {}

        root.cpuHistory = Format.pushHistory(root.cpuHistory,
          { user: cpu.user || 0, system: cpu.system || 0 }, root.historyLimit)
        root.netHistory = Format.pushHistory(root.netHistory,
          { up: net.upBps || 0, down: net.downBps || 0 }, root.historyLimit)
        root.diskHistory = Format.pushHistory(root.diskHistory,
          { read: diskio.readBps || 0, write: diskio.writeBps || 0 }, root.historyLimit)

        root.checkAlert("cpu", "CPU", cpu.total)
        root.checkAlert("gpu", "GPU", parsed.gpu ? parsed.gpu.util : undefined)
        root.checkAlert("mem", "Memory", memory.usedPercent)
        root.checkAlert("storage", "Storage", disk.usedPercent)
      }
    }

    onExited: function(code) {
      if (code !== 0 && Object.keys(root.stats).length === 0)
        root.error = "collector exited with code " + code
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalMs
    running: root.wanted && root.scriptPath !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onWantedChanged: {
    if (!root.wanted) {
      root.refreshPending = false
      pollProc.running = false
    }
  }
}
