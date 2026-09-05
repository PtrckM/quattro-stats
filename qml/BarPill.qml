pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Compact multi-stat bar pill: a row of small label/value segments (CPU,
// GPU, MEM, disk I/O, network up/down). Registers as a click target with the
// host bar so tooltip and click-through forwarding work on any bar that
// follows Quattro's bar-widget contract (stock bar and Shibumi alike).
Item {
  id: root

  property var bar: null
  property var tokens: null
  property var segments: [] // [{label, text, color, widthPx}] or [{kind:"dot", color, active}]
  property string tooltipText: ""

  property color foreground: tokens ? tokens.ink
    : (bar ? bar.foreground : Color.foreground)
  property string fontFamily: tokens && tokens.fontFamily
    ? tokens.fontFamily : (bar && bar.fontFamily ? bar.fontFamily : Style.font.family)
  property real labelFontSize: tokens ? tokens.captionSize : Style.font.caption
  property real valueFontSize: tokens ? tokens.captionSize : Style.font.caption

  signal pressed(int button)

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property bool hasVisualContent: segments.length > 0

  visible: hasVisualContent
  implicitWidth: vertical ? barSize : Math.max(12, row.implicitWidth + Style.space(16))
  implicitHeight: vertical ? Math.max(12, row.implicitHeight + Style.space(10)) : barSize

  property var registeredBar: null

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget)
      registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget)
      registeredBar.registerClickTarget(root)
  }

  onBarChanged: syncClickRegistration()
  onVisibleChanged: if (!visible && root.bar) root.bar.hideTooltip(root)
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (registeredBar && registeredBar.unregisterClickTarget)
      registeredBar.unregisterClickTarget(root)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(4)

    Repeater {
      model: root.segments

      delegate: Item {
        id: segmentRoot
        required property var modelData
        readonly property bool isStack: modelData.kind === "stack"
        readonly property bool isBattery: modelData.kind === "battery"
        readonly property bool isGauge: modelData.kind === "gauge"

        // Row (the outer positioner) top-aligns children by default; anchor
        // each segment to its vertical center instead so a short segment
        // (e.g. two dots) doesn't sit stuck to the top while a taller one
        // (e.g. CPU's label+value) defines the row's height.
        anchors.verticalCenter: parent.verticalCenter

        implicitWidth: isStack ? stackColumn.implicitWidth
          : isBattery ? batteryRow.implicitWidth
          : isGauge ? gaugeRow.implicitWidth : textColumn.implicitWidth
        implicitHeight: isStack ? stackColumn.implicitHeight
          : isBattery ? batteryRow.implicitHeight
          : isGauge ? gaugeRow.implicitHeight : textColumn.implicitHeight

        // Gauge segment (CPU/GPU/Memory/Storage, "usage gauge" style): the
        // label to the left, a small vertical capsule to the right whose
        // fill height tracks the percentage.
        Row {
          id: gaugeRow
          visible: segmentRoot.isGauge
          anchors.centerIn: parent
          spacing: Style.space(3)

          VerticalLabel {
            anchors.verticalCenter: parent.verticalCenter
            label: segmentRoot.modelData.label || ""
            textColor: Qt.darker(root.foreground, 1.3)
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: Style.space(16)

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              border.color: Qt.darker(root.foreground, 1.3)
              border.width: 1
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 2
              height: Math.max(2, (parent.height - 4)
                * Math.max(0, Math.min(100, segmentRoot.modelData.percent || 0)) / 100)
              radius: width / 2
              color: segmentRoot.modelData.color || root.foreground
            }
          }
        }

        // Battery segment: a small drawn battery glyph (no font/icon
        // dependency) plus a two-row stack — time-to-10%/time-to-full on
        // top (swapped for a bolt once fully charged), percent below.
        Row {
          id: batteryRow
          visible: segmentRoot.isBattery
          anchors.centerIn: parent
          spacing: Style.space(4)

          Item {
            id: batteryIcon
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(17)
            height: Style.space(9)

            Rectangle {
              id: batteryBody
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width - Style.space(3)
              radius: 2
              color: "transparent"
              border.color: root.foreground
              border.width: 1

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 2
                width: Math.max(1, (parent.width - 4)
                  * Math.max(0, Math.min(100, segmentRoot.modelData.percent || 0)) / 100)
                radius: 1
                color: (segmentRoot.modelData.percent || 0) <= 10 ? "#e74c3c"
                  : (segmentRoot.modelData.charging ? "#2ecc71" : "#4d8bff")
              }
            }

            Rectangle {
              anchors.left: batteryBody.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(2)
              height: parent.height * 0.5
              radius: 1
              color: root.foreground
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Item {
              width: segmentRoot.modelData.widthPx ? segmentRoot.modelData.widthPx : topText.implicitWidth
              height: topText.implicitHeight
              visible: topText.text !== ""

              Text {
                id: topText
                anchors.left: parent.left
                text: segmentRoot.modelData.full ? "⚡" : (segmentRoot.modelData.timeText || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.max(7, root.valueFontSize - 2)
                font.bold: true
                renderType: Text.NativeRendering
              }
            }

            Item {
              width: segmentRoot.modelData.widthPx ? segmentRoot.modelData.widthPx : bottomText.implicitWidth
              height: bottomText.implicitHeight

              Text {
                id: bottomText
                anchors.left: parent.left
                text: segmentRoot.modelData.percentText || ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.max(7, root.valueFontSize - 2)
                font.bold: true
                renderType: Text.NativeRendering
              }
            }
          }
        }

        // Stack segments (disk read/write, network up/download): two rows,
        // each a small pulsing dot plus its rate, stacked vertically. Each
        // row's text sits in a fixed-width box (modelData.widthPx) so the
        // pill's total width never shifts as a number's digit count changes
        // (e.g. "5 B/s" vs "1.23 MB/s").
        Column {
          id: stackColumn
          visible: segmentRoot.isStack
          anchors.centerIn: parent
          spacing: Style.space(1)

          Repeater {
            model: segmentRoot.isStack ? segmentRoot.modelData.rows : []

            delegate: Row {
              required property var modelData
              spacing: Style.space(4)

              Rectangle {
                visible: segmentRoot.modelData.showDot !== false
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(7)
                height: Style.space(7)
                radius: width / 2
                color: modelData.color || root.foreground
                opacity: modelData.active ? 1 : 0.3

                SequentialAnimation on opacity {
                  running: !!modelData.active
                  loops: Animation.Infinite
                  NumberAnimation { from: 1; to: 0.35; duration: 500; easing.type: Easing.InOutQuad }
                  NumberAnimation { from: 0.35; to: 1; duration: 500; easing.type: Easing.InOutQuad }
                }
              }

              Item {
                visible: segmentRoot.modelData.showText !== false
                anchors.verticalCenter: parent.verticalCenter
                width: segmentRoot.modelData.widthPx ? segmentRoot.modelData.widthPx : rowText.implicitWidth
                height: rowText.implicitHeight

                Text {
                  id: rowText
                  anchors.left: parent.left
                  text: modelData.text || ""
                  color: modelData.color || root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(7, root.valueFontSize - 2)
                  font.bold: true
                  renderType: Text.NativeRendering
                }
              }
            }
          }
        }

        Column {
          id: textColumn
          visible: !segmentRoot.isStack && !segmentRoot.isBattery && !segmentRoot.isGauge
          anchors.centerIn: parent
          spacing: 0

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !!segmentRoot.modelData.label
            text: segmentRoot.modelData.label || ""
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Math.max(7, root.labelFontSize - 3)
            font.bold: true
            renderType: Text.NativeRendering
          }

          // Wrapped in a fixed-width Item (sized from modelData.widthPx, the
          // widest value this segment can plausibly show) so the pill's
          // total width doesn't shift as a number's digit count changes
          // (e.g. "5%" vs "100%"). The Text itself stays naturally sized
          // and centered within that fixed box.
          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: segmentRoot.modelData.widthPx ? segmentRoot.modelData.widthPx : valueText.implicitWidth
            height: valueText.implicitHeight

            Text {
              id: valueText
              anchors.centerIn: parent
              text: segmentRoot.modelData.text || ""
              color: segmentRoot.modelData.color || root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.valueFontSize
              font.bold: true
              renderType: Text.NativeRendering
            }
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) { root.pressed(mouse.button) }
  }

  // Renders a short label ("CPU", "GPU", ...) one character per line —
  // matches the compact vertical typography of the reference design instead
  // of a single wide horizontal word.
  component VerticalLabel: Column {
    id: vlabel
    required property string label
    property color textColor: root.foreground
    spacing: -2

    Repeater {
      model: vlabel.label.length

      delegate: Text {
        required property int index
        anchors.horizontalCenter: parent.horizontalCenter
        text: vlabel.label.charAt(index)
        color: vlabel.textColor
        font.family: root.fontFamily
        font.pixelSize: Math.max(6, root.labelFontSize - 5)
        font.bold: true
        renderType: Text.NativeRendering
      }
    }
  }
}
