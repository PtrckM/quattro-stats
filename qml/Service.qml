pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "QuattroFormat.js" as Format

// One process-wide poller shared by every Quattro Stats widget instance.
// Widgets call acquire() while mounted and release() when destroyed, so the
// collector only runs while something on screen is reading it.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property int contractVersion: 1
  readonly property bool ready: true

  readonly property string scriptPath: manifest && manifest.__sourceDir
    ? manifest.__sourceDir + "/scripts/quattro-stats.sh" : ""

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

  onManifestChanged: Qt.callLater(root.refresh)

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
