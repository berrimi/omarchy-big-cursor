import QtQuick
import Quickshell
import Quickshell.Io

// Shake-to-find cursor. cursor-bridge.py streams pointer positions from
// Hyprland; this service detects a shake from how much path the pointer covers
// inside a small area, and grows the real compositor cursor while it lasts.
Item {
  id: root

  readonly property string pluginId: "io.github.gabrielforster.big-cursor"
  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string bridgePath: decodeURIComponent(
    String(Qt.resolvedUrl("cursor-bridge.py")).replace(/^file:\/\//, ""))

  // Settings. Defaults below; overridden by this plugin's entry in the
  // `plugins` array of ~/.config/omarchy/shell.json (hot-reloaded).
  property int maxSize: 96
  property real sensitivity: 2.5
  property int growMs: 300
  property int holdMs: 500
  property int shrinkMs: 350
  property int baseSize: root.environmentSize()
  property string theme: root.environmentTheme()

  // Shake detection works on the last few hundred milliseconds of movement.
  readonly property int shakeWindowMs: 500
  readonly property int minimumShakeSpan: 80
  readonly property int minimumReversals: 2

  property var samples: []
  property real level: 0
  property bool animating: false
  property double lastShakeMs: 0
  property double lastTickMs: 0

  // Starting at baseSize means the plugin never touches the cursor until the
  // first shake.
  property int sentSize: root.baseSize

  function environmentSize() {
    var size = Number(Quickshell.env("HYPRCURSOR_SIZE") || Quickshell.env("XCURSOR_SIZE"))
    return isFinite(size) && size > 0 ? Math.round(size) : 24
  }

  function environmentTheme() {
    return String(Quickshell.env("HYPRCURSOR_THEME") || Quickshell.env("XCURSOR_THEME") || "default")
  }

  function numberSetting(entry, key, fallback, minimum, maximum) {
    var value = Number(entry[key])
    if (entry[key] === undefined || !isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function applySettings(raw) {
    var entry = {}
    try {
      var config = JSON.parse(String(raw || "{}"))
      var plugins = Array.isArray(config.plugins) ? config.plugins : []
      for (var i = 0; i < plugins.length; i++) {
        if (plugins[i] && plugins[i].id === root.pluginId) entry = plugins[i]
      }
    } catch (error) {
      // Keep the current settings while shell.json is mid-edit.
      return
    }

    var nextBase = Math.round(root.numberSetting(entry, "baseSize", root.environmentSize(), 8, 256))
    var nextTheme = typeof entry.theme === "string" && /^[^\s]+$/.test(entry.theme)
      ? entry.theme : root.environmentTheme()

    // Changing the base or theme while at rest would leave the old cursor
    // applied, so restore against the new values right away.
    var restore = nextBase !== root.baseSize || nextTheme !== root.theme
    root.baseSize = nextBase
    root.theme = nextTheme
    root.maxSize = Math.round(root.numberSetting(entry, "maxSize", 96, root.baseSize, 256))
    root.sensitivity = root.numberSetting(entry, "sensitivity", 2.5, 1.5, 10)
    root.growMs = Math.round(root.numberSetting(entry, "growMs", 300, 16, 5000))
    root.holdMs = Math.round(root.numberSetting(entry, "holdMs", 500, 0, 10000))
    root.shrinkMs = Math.round(root.numberSetting(entry, "shrinkMs", 350, 16, 5000))
    if (restore) root.setSize(root.baseSize, true)
  }

  function addSample(line) {
    var parts = String(line || "").trim().split(/\s+/)
    var x = Number(parts[0])
    var y = Number(parts[1])
    if (parts.length !== 2 || !isFinite(x) || !isFinite(y)) return

    var next = root.samples
    next.push({ x: x, y: y, t: Date.now() })
    root.samples = next
    root.animating = true
  }

  function pruneSamples(now) {
    var next = root.samples
    while (next.length > 0 && now - next[0].t > root.shakeWindowMs) next.shift()
    root.samples = next
  }

  // A shake covers far more distance than the box it stays inside, and keeps
  // turning back. One fast flick is long but straight; a single there-and-back
  // has only one reversal.
  function isShaking() {
    var points = root.samples
    if (points.length < 4) return false

    var distance = 0
    var left = points[0].x, right = points[0].x
    var top = points[0].y, bottom = points[0].y
    var reversalsX = 0, reversalsY = 0
    var lastDx = 0, lastDy = 0

    for (var i = 1; i < points.length; i++) {
      var dx = points[i].x - points[i - 1].x
      var dy = points[i].y - points[i - 1].y
      distance += Math.sqrt(dx * dx + dy * dy)
      left = Math.min(left, points[i].x)
      right = Math.max(right, points[i].x)
      top = Math.min(top, points[i].y)
      bottom = Math.max(bottom, points[i].y)

      // Ignore jitter when counting changes of direction.
      if (Math.abs(dx) >= 4) {
        if (lastDx !== 0 && (dx > 0) !== (lastDx > 0)) reversalsX++
        lastDx = dx
      }
      if (Math.abs(dy) >= 4) {
        if (lastDy !== 0 && (dy > 0) !== (lastDy > 0)) reversalsY++
        lastDy = dy
      }
    }

    var span = Math.sqrt((right - left) * (right - left) + (bottom - top) * (bottom - top))
    if (span < root.minimumShakeSpan) return false
    if (Math.max(reversalsX, reversalsY) < root.minimumReversals) return false
    return distance / span >= root.sensitivity
  }

  function tick() {
    var now = Date.now()
    var dt = root.lastTickMs > 0 ? Math.min(100, now - root.lastTickMs) : 16
    root.lastTickMs = now

    root.pruneSamples(now)
    if (root.isShaking()) root.lastShakeMs = now

    // Grow for as long as the shake continues, so a longer shake gets a
    // bigger cursor, then hold briefly before shrinking back.
    if (now - root.lastShakeMs < 60) root.level = Math.min(1, root.level + dt / root.growMs)
    else if (now - root.lastShakeMs > root.holdMs) root.level = Math.max(0, root.level - dt / root.shrinkMs)

    var eased = 1 - Math.pow(1 - root.level, 3)
    root.setSize(Math.round(root.baseSize + (root.maxSize - root.baseSize) * eased), false)

    if (root.level === 0 && root.samples.length === 0) {
      root.animating = false
      root.lastTickMs = 0
    }
  }

  function setSize(size, force) {
    if (!force && size === root.sentSize) return
    root.sentSize = size
    if (bridge.running) bridge.write("setcursor " + root.theme + " " + size + "\n")
  }

  Timer {
    interval: 16
    repeat: true
    running: root.animating
    onTriggered: root.tick()
  }

  Process {
    id: bridge
    command: ["python3", "-u", root.bridgePath]
    running: true
    stdinEnabled: true

    stdout: SplitParser {
      onRead: line => root.addSample(line)
    }

    // Hyprland restarts or a crash in the bridge should not end the plugin.
    onExited: bridgeRestart.restart()
  }

  Timer {
    id: bridgeRestart
    interval: 2000
    onTriggered: bridge.running = true
  }

  FileView {
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySettings(text())
    // text() is stale inside the change signal, so reload and parse on load.
    onFileChanged: reload()
  }

  Component.onDestruction: {
    if (root.sentSize !== root.baseSize)
      Quickshell.execDetached(["hyprctl", "setcursor", root.theme, String(root.baseSize)])
  }
}
