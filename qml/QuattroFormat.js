.pragma library

function formatRate(bytesPerSec) {
  if (bytesPerSec === undefined || bytesPerSec === null) return "--"
  var kbs = bytesPerSec / 1024
  if (kbs < 1) return Math.round(bytesPerSec) + " B/s"
  if (kbs < 1024) return kbs.toFixed(kbs < 10 ? 1 : 0) + " KB/s"
  return (kbs / 1024).toFixed(2) + " MB/s"
}

function formatBytes(bytes, digits) {
  if (bytes === undefined || bytes === null) return "--"
  var gb = bytes / (1024 * 1024 * 1024)
  if (gb >= 1) return gb.toFixed(digits === undefined ? 1 : digits) + " GB"
  var mb = bytes / (1024 * 1024)
  return mb.toFixed(0) + " MB"
}

function formatUptime(seconds) {
  if (seconds === undefined || seconds === null) return "--"
  var totalMinutes = Math.floor(seconds / 60)
  var hours = Math.floor(totalMinutes / 60)
  var minutes = totalMinutes % 60
  return hours + (hours === 1 ? " hour, " : " hours, ")
    + minutes + (minutes === 1 ? " minute" : " minutes")
}

function formatPercent(value) {
  if (value === undefined || value === null) return "--"
  return Math.round(value) + "%"
}

function formatTemp(celsius) {
  if (celsius === undefined || celsius === null) return "--"
  return Math.round(celsius) + "°"
}

function formatMs(ms) {
  if (ms === undefined || ms === null) return "--"
  return Math.round(ms) + "ms"
}

function formatHM(totalMinutes) {
  if (totalMinutes === undefined || totalMinutes === null) return "--"
  var h = Math.floor(totalMinutes / 60)
  var m = Math.round(totalMinutes % 60)
  return h + ":" + (m < 10 ? "0" + m : String(m))
}

function formatFreq(mhz) {
  if (mhz === undefined || mhz === null) return "--"
  return (mhz / 1000).toFixed(2) + " GHz"
}

function pushHistory(history, entry, limit) {
  var next = Array.isArray(history) ? history.slice(0) : []
  next.push(entry)
  if (next.length > limit) next.splice(0, next.length - limit)
  return next
}

function pluck(history, key) {
  var out = []
  for (var i = 0; i < history.length; i++) out.push(Number(history[i][key] || 0))
  return out
}
