pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "QuattroFormat.js" as Format

// Quattro Stats widget + popup. Root is a qs.Ui.Panel (the bar pill lives on
// it, plus the dashboard popup), matching the pattern documented by
// dev.deoxizn.devicebattstats: the KeyboardPanel is a direct child of this
// root so the Shibumi host's compatibility adapter can re-anchor and re-size
// the popup card correctly. Don't bury it in a Loader or an inner Item.
Panel {
  id: root
  moduleName: "ptrck.quattro-stats"
  ipcTarget: ""
  manageIpc: false

  readonly property string serviceId: "ptrck.quattro-stats"
  readonly property var service: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(serviceId) : null

  readonly property var stats: service ? service.stats : ({})
  readonly property var cpu: stats.cpu || {}
  readonly property var gpu: stats.gpu || null
  readonly property var memory: stats.memory || {}
  readonly property var disk: stats.disk || {}
  readonly property var diskio: stats.diskio || {}
  readonly property var network: stats.network || {}
  readonly property var load: stats.load || {}
  readonly property var battery: stats.battery || null
  readonly property var fans: stats.fans || {}
  readonly property string fanSummary: {
    var names = Object.keys(root.fans)
    if (names.length === 0) return ""
    var maxRpm = 0
    for (var i = 0; i < names.length; i++) maxRpm = Math.max(maxRpm, root.fans[names[i]] || 0)
    return Math.round(maxRpm) + " RPM"
  }
  readonly property var ping: stats.ping || {}
  readonly property var uptimeSeconds: stats.uptimeSeconds !== undefined ? stats.uptimeSeconds : null

  readonly property var cpuHistory: service ? service.cpuHistory : []
  readonly property var netHistory: service ? service.netHistory : []
  readonly property var diskHistory: service ? service.diskHistory : []
  readonly property string collectorError: service ? service.error : ""

  // ---- Theming: prefer the bar's own tokens (Shibumi VisualTokens) so
  // per-widget color fills configured in Shibumi settings keep working;
  // fall back to the built-in adapter for the stock bar and other hosts.
  HostTokens {
    id: hostTokens
    bar: root.bar
  }

  readonly property var tokens: bar && "visualTokens" in bar && bar.visualTokens
    ? bar.visualTokens : hostTokens

  readonly property color contentForeground: tokens && tokens.ink
    ? tokens.ink : (bar ? bar.foreground : Color.foreground)
  readonly property string contentFontFamily: tokens && tokens.fontFamily
    ? tokens.fontFamily : (bar ? bar.fontFamily : Style.font.family)
  readonly property int labelSize: tokens ? tokens.labelSize : Style.font.body
  readonly property int captionSize: tokens ? tokens.captionSize : Style.font.caption

  readonly property color upColor: "#ff5f8f"
  readonly property color downColor: "#4d8bff"

  function alpha(color, amount) {
    return Qt.rgba(color.r, color.g, color.b, amount)
  }

  // ---- Collapsible sections. Every card starts collapsed (its header still
  // shows a quick glanceable stat); expanding one is a per-session toggle,
  // not persisted.
  property var expandedSections: ({})

  function isCollapsed(key) {
    return root.expandedSections[key] !== true
  }

  function toggleSection(key) {
    var next = {}
    for (var k in root.expandedSections) next[k] = root.expandedSections[k]
    next[key] = root.isCollapsed(key)
    root.expandedSections = next
  }

  // ---- Service acquisition. The service is ensured by the shell at
  // startup, but the widget can mount before it exists; retry a short
  // window.
  property bool serviceClaimed: false
  property int serviceTries: 0

  function tryClaimService() {
    if (root.service && !root.serviceClaimed) {
      if (typeof root.service.acquire === "function") root.service.acquire()
      root.serviceClaimed = true
      root.serviceTries = 0
      serviceRetry.stop()
    } else if (!root.service && root.serviceTries < 30) {
      root.serviceTries++
      serviceRetry.restart()
    }
  }

  onServiceChanged: tryClaimService()
  Component.onCompleted: tryClaimService()
  Component.onDestruction: {
    if (root.serviceClaimed && root.service
        && typeof root.service.release === "function")
      root.service.release()
    serviceRetry.stop()
  }

  Timer {
    id: serviceRetry
    interval: 500
    onTriggered: root.tryClaimService()
  }

  // ---- Settings: which stats show in the bar pill / dashboard. Configured
  // through the plugin's settings UI (manifest schema: barItems /
  // panelSections); both default to "everything" when unset.
  readonly property var defaultBarItems: ["cpu", "gpu", "mem", "up", "down"]
  readonly property var defaultPanelSections: ["cpu", "gpu", "memory", "storage", "network", "fans", "battery", "uptime", "ping"]
  readonly property var barItems: root.setting("barItems", root.defaultBarItems)
  readonly property string usageStyleValue: root.setting("usageStyle", "Percentage text")
  readonly property bool useGaugeStyle: root.usageStyleValue === "Usage gauge (bar)"

  function setUsageStyle(value) {
    root.persistPluginSetting("usageStyle", value)
  }
  readonly property var panelSections: root.setting("panelSections", root.defaultPanelSections)

  function barItemEnabled(key) {
    return Array.isArray(root.barItems) && root.barItems.indexOf(key) !== -1
  }

  function sectionEnabled(key) {
    return Array.isArray(root.panelSections) && root.panelSections.indexOf(key) !== -1
  }

  readonly property var barItemOptions: [
    { key: "cpu", label: "CPU %" },
    { key: "gpu", label: "GPU %" },
    { key: "mem", label: "Memory %" },
    { key: "storage", label: "Storage used %" },
    { key: "battery", label: "Battery (icon + time + %)" },
    { key: "fans", label: "Fan speed (RPM)" },
    { key: "uptime", label: "Load average" },
    { key: "io", label: "Disk I/O activity (read/write dots)" },
    { key: "up", label: "Network upload activity (dot)" },
    { key: "down", label: "Network download activity (dot)" }
  ]

  readonly property var panelSectionOptions: [
    { key: "cpu", label: "CPU" },
    { key: "gpu", label: "GPU" },
    { key: "memory", label: "Memory" },
    { key: "storage", label: "Storage" },
    { key: "network", label: "Network" },
    { key: "fans", label: "Fans" },
    { key: "battery", label: "Battery" },
    { key: "uptime", label: "Uptime & Load" },
    { key: "ping", label: "Ping" }
  ]

  // Writes straight to this widget's inline shell.json entry (same mechanism
  // the built-in Argus plugin uses for its per-metric toggles) — bypasses
  // `omarchy bar set --json`, which mishandles array values.
  function persistPluginSetting(name, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id" && key !== name) entry[key] = root.settings[key]
    entry[name] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleArrayValue(array, value) {
    var next = Array.isArray(array) ? array.slice(0) : []
    var idx = next.indexOf(value)
    if (idx === -1) next.push(value)
    else next.splice(idx, 1)
    return next
  }

  function toggleBarItem(key) {
    root.persistPluginSetting("barItems", root.toggleArrayValue(root.barItems, key))
  }

  function moveBarItem(key, direction) {
    var arr = Array.isArray(root.barItems) ? root.barItems.slice(0) : []
    var idx = arr.indexOf(key)
    var newIdx = idx + direction
    if (idx === -1 || newIdx < 0 || newIdx >= arr.length) return
    var tmp = arr[newIdx]
    arr[newIdx] = arr[idx]
    arr[idx] = tmp
    root.persistPluginSetting("barItems", arr)
  }

  function barItemOptionByKey(key) {
    for (var i = 0; i < root.barItemOptions.length; i++)
      if (root.barItemOptions[i].key === key) return root.barItemOptions[i]
    return null
  }

  // Enabled items first (in their current bar order, reorderable), then
  // disabled ones below in their declared order.
  function orderedBarItemRows() {
    var rows = []
    var enabled = Array.isArray(root.barItems) ? root.barItems : []
    for (var i = 0; i < enabled.length; i++) {
      var opt = root.barItemOptionByKey(enabled[i])
      if (opt) rows.push({ key: enabled[i], label: opt.label, enabled: true })
    }
    for (var j = 0; j < root.barItemOptions.length; j++) {
      var o = root.barItemOptions[j]
      if (enabled.indexOf(o.key) === -1) rows.push({ key: o.key, label: o.label, enabled: false })
    }
    return rows
  }

  function togglePanelSection(key) {
    root.persistPluginSetting("panelSections", root.toggleArrayValue(root.panelSections, key))
  }

  // ---- Bar pill segments (CPU / GPU / MEM / disk I/O / network up-down)
  readonly property real percentWidthPx: 22
  readonly property real gaugeLabelWidthPx: 24

  // CPU/GPU/Memory/Storage each render as either a percent-text segment or
  // a small vertical usage gauge with the label to its left, per the
  // usageStyle setting.
  function percentSegment(label, value, color) {
    if (root.useGaugeStyle) {
      return { kind: "gauge", label: label, percent: value || 0, color: color, widthPx: root.gaugeLabelWidthPx }
    }
    return { label: label, text: Format.formatPercent(value), widthPx: root.percentWidthPx }
  }
  // Sized for the common case ("999.9 KB/s"), not the rare MB/s spike — that
  // occasional bigger jump is a fair trade for not padding every normal
  // reading with empty space.
  readonly property real rateWidthPx: 46
  readonly property real fanWidthPx: 28
  readonly property real loadWidthPx: 26
  readonly property real batteryWidthPx: 26

  // Below this rate, a dot is considered idle (dim, no pulse) rather than
  // actively transferring — background chatter shouldn't read as "busy".
  readonly property real activityThresholdBps: 8192

  // Bar items are shown in the order they appear in root.barItems itself —
  // enabling/disabling and reordering are both just edits to that one array
  // (see toggleBarItem / moveBarItem).
  function buildSegments() {
    var segs = []
    var order = Array.isArray(root.barItems) ? root.barItems : root.defaultBarItems
    var networkHandled = false

    for (var i = 0; i < order.length; i++) {
      var key = order[i]

      if (key === "cpu") {
        segs.push(root.percentSegment("CPU", root.cpu.total, root.upColor))
      } else if (key === "gpu" && root.gpu) {
        segs.push(root.percentSegment("GPU", root.gpu.util, root.downColor))
      } else if (key === "mem") {
        segs.push(root.percentSegment("MEM", root.memory.usedPercent, root.downColor))
      } else if (key === "storage") {
        segs.push(root.percentSegment("DISK", root.disk.usedPercent, root.downColor))
      } else if (key === "battery" && root.battery) {
        var bat = root.battery
        var timeText = ""
        if (bat.full) timeText = ""
        else if (bat.charging && bat.timeToFullMin !== null && bat.timeToFullMin !== undefined) timeText = Format.formatHM(bat.timeToFullMin)
        else if (!bat.charging && bat.timeToTenMin !== null && bat.timeToTenMin !== undefined) timeText = Format.formatHM(bat.timeToTenMin)
        segs.push({
          kind: "battery", widthPx: root.batteryWidthPx,
          percent: bat.percent || 0, charging: bat.charging, full: bat.full,
          timeText: timeText, percentText: (bat.percent || 0) + "%"
        })
      } else if (key === "fans" && root.fanSummary !== "") {
        var maxRpm = 0
        var fanNames = Object.keys(root.fans)
        for (var fi = 0; fi < fanNames.length; fi++) maxRpm = Math.max(maxRpm, root.fans[fanNames[fi]] || 0)
        segs.push({ label: "FAN", text: Math.round(maxRpm) + "", widthPx: root.fanWidthPx })
      } else if (key === "uptime" && root.load.one !== undefined) {
        segs.push({ label: "LOAD", text: root.load.one.toFixed(2), widthPx: root.loadWidthPx })
      } else if (key === "io") {
        var readBps = root.diskio.readBps || 0
        var writeBps = root.diskio.writeBps || 0
        segs.push({
          kind: "stack", showDot: true, showText: false,
          rows: [
            { color: root.downColor, active: readBps > root.activityThresholdBps },
            { color: root.upColor, active: writeBps > root.activityThresholdBps }
          ]
        })
      } else if ((key === "up" || key === "down") && !networkHandled) {
        networkHandled = true
        var netRows = []
        if (root.barItemEnabled("up")) {
          var upBps = root.network.upBps || 0
          netRows.push({ color: root.upColor, text: Format.formatRate(upBps), active: upBps > root.activityThresholdBps })
        }
        if (root.barItemEnabled("down")) {
          var downBps = root.network.downBps || 0
          netRows.push({ color: root.downColor, text: Format.formatRate(downBps), active: downBps > root.activityThresholdBps })
        }
        if (netRows.length > 0)
          segs.push({ kind: "stack", widthPx: root.rateWidthPx, showDot: true, showText: true, rows: netRows })
      }
    }

    return segs
  }

  readonly property var segments: buildSegments()

  function buildTooltip() {
    var lines = []
    lines.push("CPU " + Format.formatPercent(root.cpu.total)
      + (root.cpu.tempC !== undefined && root.cpu.tempC !== null ? " (" + Format.formatTemp(root.cpu.tempC) + ")" : ""))
    if (root.gpu) lines.push("GPU " + Format.formatPercent(root.gpu.util) + " (" + Format.formatTemp(root.gpu.tempC) + ")")
    lines.push("Memory " + Format.formatPercent(root.memory.usedPercent))
    lines.push("Disk " + Format.formatPercent(root.disk.usedPercent) + " used"
      + " (R " + Format.formatRate(root.diskio.readBps || 0) + " / W " + Format.formatRate(root.diskio.writeBps || 0) + ")")
    lines.push("Net ↑" + Format.formatRate(root.network.upBps || 0) + " ↓" + Format.formatRate(root.network.downBps || 0))
    if (root.battery) lines.push("Battery " + root.battery.percent + "%" + (root.battery.charging ? " (charging)" : ""))
    return lines.join("\n")
  }

  visible: root.segments.length > 0
  implicitWidth: pill.implicitWidth
  implicitHeight: pill.implicitHeight

  BarPill {
    id: pill
    bar: root.bar
    tokens: root.tokens
    segments: root.segments
    tooltipText: root.buildTooltip()
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.toggle()
      else if (button === Qt.RightButton && root.service) root.service.refresh()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: pill
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(
      Math.min(dashboard.implicitHeight + Style.space(20), Style.space(900)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) { if (t === "r" || t === "R") { if (root.service) root.service.refresh() } }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: dashboard.implicitHeight + Style.space(20)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      ColumnLayout {
        id: dashboard
        x: Style.space(10)
        y: Style.space(10)
        width: scroll.width - Style.space(20)
        spacing: Style.space(10)

        // ---- CPU -------------------------------------------------------
        CollapsibleCard {
          sectionKey: "cpu"
          visible: root.sectionEnabled("cpu")
          title: "CPU"
          headerRightText: Format.formatTemp(root.cpu.tempC) + ", " + Format.formatPercent(root.cpu.total)

          HistoryChart {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(60)
            mode: "stacked"
            maxValue: 100
            seriesA: Format.pluck(root.cpuHistory, "user")
            seriesB: Format.pluck(root.cpuHistory, "system")
            colorA: root.downColor
            colorB: root.upColor
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)
            Rectangle { width: Style.space(8); height: Style.space(8); radius: width / 2; color: root.downColor }
            Text {
              text: "User " + Format.formatPercent(root.cpu.user)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.captionSize
            }
            Item { Layout.preferredWidth: Style.space(10) }
            Rectangle { width: Style.space(8); height: Style.space(8); radius: width / 2; color: root.upColor }
            Text {
              text: "System " + Format.formatPercent(root.cpu.system)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.captionSize
            }
          }
        }

        // ---- GPU ---------------------------------------------------------
        CollapsibleCard {
          sectionKey: "gpu"
          title: "GPU"
          headerRightText: root.gpu ? (Format.formatTemp(root.gpu.tempC) + ", " + Format.formatPercent(root.gpu.util)) : ""
          visible: root.gpu !== null && root.sectionEnabled("gpu")

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)

            RingStat {
              percent: root.gpu ? (root.gpu.util || 0) : 0
              valueText: Format.formatPercent(root.gpu ? root.gpu.util : 0)
              caption: "UTIL"
              ringColor: root.upColor
              trackColor: root.alpha(root.contentForeground, 0.12)
              textColor: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                text: "Temp " + Format.formatTemp(root.gpu ? root.gpu.tempC : null)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.labelSize
              }
              Text {
                text: "Clock " + Format.formatFreq(root.gpu ? root.gpu.clockMHz : null)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
              }
              Text {
                text: "Memory " + (root.gpu ? Math.round(root.gpu.memUsedMB) + " / " + Math.round(root.gpu.memTotalMB) + " MB" : "--")
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
              }
            }
          }
        }

        // ---- Memory --------------------------------------------------
        CollapsibleCard {
          sectionKey: "memory"
          visible: root.sectionEnabled("memory")
          title: "MEMORY"
          headerRightText: Format.formatPercent(root.memory.usedPercent)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)

            RingStat {
              percent: root.memory.usedPercent || 0
              valueText: Format.formatPercent(root.memory.usedPercent)
              caption: "USED"
              ringColor: root.downColor
              trackColor: root.alpha(root.contentForeground, 0.12)
              textColor: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                text: Format.formatBytes(root.memory.usedBytes) + " / " + Format.formatBytes(root.memory.totalBytes)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.labelSize
              }
              Text {
                text: "Cached " + Format.formatBytes(root.memory.cachedBytes)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
              }
              Text {
                text: "Free " + Format.formatBytes(root.memory.freeBytes)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
              }
            }
          }
        }

        // ---- Storage ---------------------------------------------------
        CollapsibleCard {
          sectionKey: "storage"
          visible: root.sectionEnabled("storage")
          title: "STORAGE"
          headerRightText: Format.formatPercent(root.disk.usedPercent) + " used"

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)

            RingStat {
              percent: root.disk.usedPercent || 0
              valueText: Format.formatPercent(root.disk.usedPercent)
              caption: "USED"
              ringColor: root.contentForeground
              trackColor: root.alpha(root.contentForeground, 0.12)
              textColor: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                text: Format.formatBytes(root.disk.availBytes) + " available"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.labelSize
              }
              Text {
                text: (root.disk.mount || "/") + " on " + (root.disk.source || "--")
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
                elide: Text.ElideMiddle
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Rectangle { width: Style.space(8); height: Style.space(8); radius: width / 2; color: root.upColor }
            Text {
              text: "Read " + Format.formatRate(root.diskio.readBps || 0)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.captionSize
            }
            Item { Layout.preferredWidth: Style.space(10) }
            Rectangle { width: Style.space(8); height: Style.space(8); radius: width / 2; color: root.downColor }
            Text {
              text: "Write " + Format.formatRate(root.diskio.writeBps || 0)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.captionSize
            }
          }

          HistoryChart {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(36)
            mode: "mirror"
            seriesA: Format.pluck(root.diskHistory, "read")
            seriesB: Format.pluck(root.diskHistory, "write")
            colorA: root.upColor
            colorB: root.downColor
          }
        }

        // ---- Network ---------------------------------------------------
        CollapsibleCard {
          sectionKey: "network"
          visible: root.sectionEnabled("network")
          title: "NETWORK"
          headerRightText: root.network.iface || "--"

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Rectangle { width: Style.space(8); height: Style.space(8); radius: width / 2; color: root.upColor }
            Text {
              text: "Upload " + Format.formatRate(root.network.upBps || 0)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.labelSize
            }
            Item { Layout.preferredWidth: Style.space(10) }
            Rectangle { width: Style.space(8); height: Style.space(8); radius: width / 2; color: root.downColor }
            Text {
              text: "Download " + Format.formatRate(root.network.downBps || 0)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.labelSize
            }
          }

          HistoryChart {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(48)
            mode: "mirror"
            seriesA: Format.pluck(root.netHistory, "up")
            seriesB: Format.pluck(root.netHistory, "down")
            colorA: root.upColor
            colorB: root.downColor
          }
        }

        // ---- Fans / Sensors ---------------------------------------------
        CollapsibleCard {
          sectionKey: "fans"
          title: "FANS"
          headerRightText: root.fanSummary
          visible: Object.keys(root.fans).length > 0 && root.sectionEnabled("fans")

          Repeater {
            model: Object.keys(root.fans)
            delegate: RowLayout {
              required property string modelData
              Layout.fillWidth: true
              Text {
                text: modelData
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
              }
              Item { Layout.fillWidth: true }
              Text {
                text: Math.round(root.fans[modelData]) + " RPM"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.captionSize
              }
            }
          }
        }

        // ---- Battery -----------------------------------------------------
        CollapsibleCard {
          sectionKey: "battery"
          title: "BATTERY"
          headerRightText: root.battery ? (root.battery.percent + "%" + (root.battery.charging ? " charging" : "")) : ""
          visible: root.battery !== null && root.sectionEnabled("battery")

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)

            RingStat {
              percent: root.battery ? (root.battery.percent || 0) : 0
              valueText: root.battery ? root.battery.percent + "%" : "--"
              caption: root.battery && root.battery.charging ? "CHARGING" : "CHARGE"
              ringColor: root.downColor
              trackColor: root.alpha(root.contentForeground, 0.12)
              textColor: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            RingStat {
              visible: root.battery && root.battery.health !== null
              percent: root.battery && root.battery.health !== null ? root.battery.health : 0
              valueText: root.battery && root.battery.health !== null ? root.battery.health + "%" : "--"
              caption: "HEALTH"
              ringColor: root.upColor
              trackColor: root.alpha(root.contentForeground, 0.12)
              textColor: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                text: root.battery ? root.battery.status : "--"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.labelSize
              }
            }
          }
        }

        // ---- Uptime & Load ------------------------------------------------
        CollapsibleCard {
          sectionKey: "uptime"
          headerRightText: (root.load.one !== undefined ? "load " + root.load.one.toFixed(2) : "")
          visible: root.sectionEnabled("uptime")
          title: "UPTIME & LOAD"

          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "Uptime"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: root.captionSize
            }
            Item { Layout.fillWidth: true }
            Text {
              text: Format.formatUptime(root.uptimeSeconds)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.labelSize
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "Load"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: root.captionSize
            }
            Item { Layout.fillWidth: true }
            Text {
              text: (root.load.one !== undefined ? root.load.one.toFixed(2) : "--")
                + "  " + (root.load.five !== undefined ? root.load.five.toFixed(2) : "--")
                + "  " + (root.load.fifteen !== undefined ? root.load.fifteen.toFixed(2) : "--")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.labelSize
            }
          }
        }

        // ---- Ping ----------------------------------------------------------
        CollapsibleCard {
          sectionKey: "ping"
          visible: root.sectionEnabled("ping")
          title: "PING"
          headerRightText: root.ping.ok ? Format.formatMs(root.ping.ms) : "timeout"

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(8); height: Style.space(8); radius: width / 2
              color: root.ping.ok ? "#2ecc71" : "#e74c3c"
            }

            Text {
              text: (root.ping.host || "--")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.labelSize
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.ping.ok ? Format.formatMs(root.ping.ms) : "timeout"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: root.labelSize
            }
          }
        }

        // ---- Settings ----------------------------------------------------
        CollapsibleCard {
          sectionKey: "settings"
          title: "SETTINGS"

          Text {
            text: "CPU/GPU/Memory/Storage style"
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            font.bold: true
          }

          SettingRow {
            Layout.fillWidth: true
            label: "Percentage"
            checked: root.usageStyleValue === "Percentage text"
            onToggled: root.setUsageStyle("Percentage text")
          }

          SettingRow {
            Layout.fillWidth: true
            label: "Gauge"
            checked: root.usageStyleValue === "Usage gauge (bar)"
            onToggled: root.setUsageStyle("Usage gauge (bar)")
          }

          Item { Layout.preferredHeight: Style.space(4) }

          Text {
            text: "Bar stats"
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            font.bold: true
          }

          Repeater {
            model: root.orderedBarItemRows()
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(2)

              SettingRow {
                Layout.fillWidth: true
                label: modelData.label
                checked: modelData.enabled
                onToggled: root.toggleBarItem(modelData.key)
              }

              ReorderButton {
                visible: modelData.enabled
                glyph: "▲"
                enabled: root.barItems.indexOf(modelData.key) > 0
                onTapped: root.moveBarItem(modelData.key, -1)
              }

              ReorderButton {
                visible: modelData.enabled
                glyph: "▼"
                enabled: root.barItems.indexOf(modelData.key) < root.barItems.length - 1
                onTapped: root.moveBarItem(modelData.key, 1)
              }
            }
          }

          Item { Layout.preferredHeight: Style.space(4) }

          Text {
            text: "Dashboard sections"
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            font.bold: true
          }

          Repeater {
            model: root.panelSectionOptions
            delegate: SettingRow {
              required property var modelData
              Layout.fillWidth: true
              label: modelData.label
              checked: root.sectionEnabled(modelData.key)
              onToggled: root.togglePanelSection(modelData.key)
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.collectorError !== ""
          text: root.collectorError
          color: "#e74c3c"
          font.family: root.contentFontFamily
          font.pixelSize: root.captionSize
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // ---- Reusable settings checkbox row ---------------------------------
  component SettingRow: Item {
    id: settingRow

    required property string label
    required property bool checked
    signal toggled()

    implicitHeight: Style.space(28)

    RowLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      Rectangle {
        Layout.preferredWidth: Style.space(16)
        Layout.preferredHeight: Style.space(16)
        radius: Style.space(3)
        color: settingRow.checked ? Color.accent : "transparent"
        border.color: settingRow.checked ? Color.accent : Qt.darker(root.contentForeground, 1.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          visible: settingRow.checked
          text: "✓"
          color: "white"
          font.pixelSize: root.captionSize
          font.bold: true
        }
      }

      Text {
        Layout.fillWidth: true
        text: settingRow.label
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: root.captionSize
      }
    }

    TapHandler {
      onTapped: settingRow.toggled()
    }

    HoverHandler {
      cursorShape: Qt.PointingHandCursor
    }
  }

  // ---- Small ▲/▼ button used to reorder an enabled bar-stat row. Uses the
  // Item's own built-in `enabled` (disabling it also disables the handlers
  // below automatically) rather than a custom property of the same name.
  component ReorderButton: Item {
    id: reorderButton

    required property string glyph
    signal tapped()

    Layout.preferredWidth: Style.space(20)
    Layout.preferredHeight: Style.space(20)

    Text {
      anchors.centerIn: parent
      text: reorderButton.glyph
      color: reorderButton.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 2.2)
      font.pixelSize: Math.max(7, root.captionSize - 2)
    }

    TapHandler {
      onTapped: reorderButton.tapped()
    }

    HoverHandler {
      cursorShape: Qt.PointingHandCursor
    }
  }

  // ---- Reusable card: header (title + optional right-aligned text +
  // collapse chevron) that toggles the body's visibility on click. Content
  // placed inside a CollapsibleCard { ... } instance becomes the body via
  // the default alias.
  component CollapsibleCard: BorderSurface {
    id: card

    property string sectionKey: ""
    property string title: ""
    property string headerRightText: ""
    readonly property bool collapsed: root.isCollapsed(sectionKey)

    default property alias bodyContent: bodyColumn.children

    Layout.fillWidth: true
    implicitHeight: outer.implicitHeight + Style.space(24)
    color: root.alpha(root.contentForeground, 0.03)
    borderSpec: Border.flat(root.alpha(root.contentForeground, 0.08), 1)
    radius: Style.cornerRadius

    ColumnLayout {
      id: outer
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      Item {
        id: headerHit
        Layout.fillWidth: true
        implicitHeight: Math.max(headerRow.implicitHeight, Style.space(22))

        RowLayout {
          id: headerRow
          anchors.fill: parent

          Text {
            text: card.title
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            font.bold: true
            font.letterSpacing: 1
          }
          Item { Layout.fillWidth: true }
          Text {
            visible: card.headerRightText !== ""
            text: card.headerRightText
            color: Qt.darker(root.contentForeground, 1.2)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
          }
          Text {
            text: card.collapsed ? "▸" : "▾"
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
          }
        }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: root.toggleSection(card.sectionKey)
        }

        HoverHandler {
          cursorShape: Qt.PointingHandCursor
        }
      }

      ColumnLayout {
        id: bodyColumn
        Layout.fillWidth: true
        visible: !card.collapsed
        spacing: Style.space(8)
      }
    }
  }

  // ---- Reusable ring stat: value ring + big percent + caption below ----
  component RingStat: ColumnLayout {
    id: ringStat

    property real percent: 0
    property string valueText: "--"
    property string caption: ""
    property color ringColor: "white"
    property color trackColor: "gray"
    property color textColor: "white"
    property string fontFamily: ""

    spacing: Style.space(4)

    Item {
      Layout.preferredWidth: Style.space(72)
      Layout.preferredHeight: Style.space(72)

      Gauge {
        anchors.fill: parent
        percent: ringStat.percent
        valueColor: ringStat.ringColor
        trackColor: ringStat.trackColor
        thickness: Style.space(6)
      }

      Text {
        anchors.centerIn: parent
        text: ringStat.valueText
        color: ringStat.textColor
        font.family: ringStat.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Text {
      Layout.alignment: Qt.AlignHCenter
      text: ringStat.caption
      color: Qt.darker(ringStat.textColor, 1.5)
      font.family: ringStat.fontFamily
      font.pixelSize: Style.font.caption - 1
      font.letterSpacing: 1
    }
  }
}
