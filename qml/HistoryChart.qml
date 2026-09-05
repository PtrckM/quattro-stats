import QtQuick

// Two-series bar history chart.
//
// mode "stacked": seriesA is stacked on top of seriesB, both scaled against
//   maxValue (e.g. CPU user% over system%).
// mode "mirror": seriesA grows up from a center baseline, seriesB grows down
//   from it, both auto-scaled to the largest sample (e.g. net upload/download,
//   disk read/write).
Canvas {
  id: root

  property string mode: "stacked"
  property var seriesA: []
  property var seriesB: []
  property color colorA: "#ff5f8f"
  property color colorB: "#4d8bff"
  property real maxValue: 100

  antialiasing: false

  onSeriesAChanged: requestPaint()
  onSeriesBChanged: requestPaint()
  onModeChanged: requestPaint()
  onMaxValueChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var a = Array.isArray(seriesA) ? seriesA : []
    var b = Array.isArray(seriesB) ? seriesB : []
    var n = Math.max(a.length, b.length)
    if (n === 0) return

    var barW = width / n

    if (mode === "stacked") {
      var maxV = Math.max(1, maxValue)
      for (var i = 0; i < n; i++) {
        var av = Math.max(0, Number(a[i] || 0))
        var bv = Math.max(0, Number(b[i] || 0))
        var x = i * barW
        var hb = Math.min(height, (bv / maxV) * height)
        var ha = Math.min(height - hb, (av / maxV) * height)
        ctx.fillStyle = colorB
        ctx.fillRect(x, height - hb, Math.max(1, barW - 1), hb)
        ctx.fillStyle = colorA
        ctx.fillRect(x, height - hb - ha, Math.max(1, barW - 1), ha)
      }
    } else {
      var peak = 1
      for (var j = 0; j < n; j++)
        peak = Math.max(peak, Number(a[j] || 0), Number(b[j] || 0))

      var mid = height / 2
      for (var k = 0; k < n; k++) {
        var av2 = Math.max(0, Number(a[k] || 0))
        var bv2 = Math.max(0, Number(b[k] || 0))
        var x2 = k * barW
        var hUp = Math.min(mid, (av2 / peak) * mid)
        var hDown = Math.min(mid, (bv2 / peak) * mid)
        ctx.fillStyle = colorA
        ctx.fillRect(x2, mid - hUp, Math.max(1, barW - 1), hUp)
        ctx.fillStyle = colorB
        ctx.fillRect(x2, mid, Math.max(1, barW - 1), hDown)
      }
    }
  }
}
