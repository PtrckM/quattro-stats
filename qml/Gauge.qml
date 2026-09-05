import QtQuick

// Circular ring gauge (iStat-style): a track ring plus a value arc starting
// at 12 o'clock. Purely visual -- callers overlay their own center label.
Canvas {
  id: root

  property real percent: 0
  property color trackColor: "#332b2b2b"
  property color valueColor: "black"
  property real thickness: 6

  antialiasing: true

  onPercentChanged: requestPaint()
  onTrackColorChanged: requestPaint()
  onValueColorChanged: requestPaint()
  onThicknessChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var cx = width / 2
    var cy = height / 2
    var r = Math.min(width, height) / 2 - root.thickness / 2 - 1
    if (r <= 0) return

    var start = -Math.PI / 2
    var pct = Math.max(0, Math.min(100, root.percent)) / 100
    var end = start + Math.PI * 2 * pct

    ctx.lineWidth = root.thickness
    ctx.lineCap = "round"

    ctx.strokeStyle = root.trackColor
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.stroke()

    if (pct > 0) {
      ctx.strokeStyle = root.valueColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, start, end)
      ctx.stroke()
    }
  }
}
