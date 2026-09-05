pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Theme adapter so the widget looks native on either bar host.
//
// - On the Shibumi bar the host exposes its own VisualTokens through
//   bar.visualTokens (labelSize, iconSize, ink, seal, ...); Panel.qml prefers
//   that object so per-widget color fills configured in Shibumi settings
//   keep working.
// - On the stock Omarchy bar (and any bar following Quattro's bar-widget
//   contract) this object derives the same values from the bar's standard
//   properties -- fontFamily, foreground, urgent, background, barSize,
//   vertical -- and falls back to the active theme's Style/Color singletons.
Item {
  id: root

  property var bar: null

  readonly property string fontFamily: bar
    && "fontFamily" in bar && String(bar.fontFamily || "") !== ""
    ? String(bar.fontFamily) : Style.font.family

  readonly property int labelSize: Style.font.body
  readonly property int captionSize: Style.font.caption
  readonly property int iconSize: Style.space(15)

  readonly property int barHeight: bar
    && "barSize" in bar && Number(bar.barSize) > 0
    ? Number(bar.barSize) : Style.space(35)
  readonly property bool vertical: bar ? !!bar.vertical : false

  readonly property color paper: bar && "background" in bar
    ? bar.background : Color.background
  readonly property color ink: bar && "foreground" in bar
    ? bar.foreground : Color.foreground
  readonly property color seal: bar && "urgent" in bar
    ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color mutedInk: Color.muted

  visible: false
  width: 0
  height: 0
}
