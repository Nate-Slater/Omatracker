import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.local/share/omatracker"
  readonly property string dataPath: dataDir + "/data.json"
  readonly property int tickMs: 1000
  readonly property int maxGapMs: 8000

  property bool loaded: false
  property bool dirReady: false
  property bool readyToSave: false
  property var state: Model.emptyState()
  property var snapshot: ({})
  property int revision: 0
  property int warnPercent: 80
  property int idleMinutes: 2
  property var catalog: []

  property string trackingId: ""
  property double lastSampleMs: 0
  property string focusedId: ""
  property string focusedTitle: ""

  readonly property real warnRatio: Math.max(0.5, Math.min(1, warnPercent / 100))

  function applySettings(settings) {
    if (!settings) return
    if (settings.warnPercent !== undefined && settings.warnPercent !== null)
      root.warnPercent = Model.clampInt(settings.warnPercent, 50, 100, root.warnPercent)
    if (settings.idleMinutes !== undefined && settings.idleMinutes !== null)
      root.idleMinutes = Model.clampInt(settings.idleMinutes, 1, 60, root.idleMinutes)
  }

  function refreshCatalog() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { values = [] }
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry) continue
      out.push({
        id: String(entry.id || ""),
        name: String(entry.name || ""),
        icon: String(entry.icon || "")
      })
    }
    root.catalog = out
  }

  function currentFocus() {
    var raw = ""
    var title = ""
    var hypr = null
    try { hypr = Hyprland.activeToplevel } catch (e) { hypr = null }
    if (hypr) {
      var ipc = hypr.lastIpcObject || ({})
      raw = String(ipc["class"] || ipc.initialClass || "")
      title = String(hypr.title || ipc.title || "")
    }
    if (!raw) {
      var top = null
      try { top = ToplevelManager.activeToplevel } catch (e) { top = null }
      if (!top || top.minimized) return null
      raw = String(top.appId || "")
      if (!title) title = String(top.title || "")
    }
    var ident = Model.identityFor(raw, title)
    if (!ident.id) return null
    if (ident.wrapped) return { id: ident.id, name: ident.name, icon: "", matched: true, title: title }
    var looked = Model.lookupApp(root.catalog, raw)
    return {
      id: ident.id,
      name: looked.name || ident.name,
      icon: looked.icon,
      matched: looked.matched,
      title: title
    }
  }

  function publish() {
    root.snapshot = Model.snapshot(
      root.state,
      root.focusedId,
      root.trackingId ? root.lastSampleMs : 0,
      root.focusedTitle,
      root.warnRatio,
      Date.now())
    root.revision++
  }

  function notify(events) {
    for (var i = 0; i < events.length; i++) {
      var ev = events[i]
      var over = ev.type === "over"
      Util.execArgv([
        "omarchy-notification-send",
        "--app-name", "Omatracker",
        "-u", over ? "normal" : "low",
        "-t", over ? "8000" : "5000",
        over ? ev.name + " hit its limit" : ev.name + " is near its limit",
        Model.formatDuration(ev.seconds) + " of " + Model.formatLimit(ev.limitMinutes) + " today"
      ])
    }
  }

  function scheduleSave() {
    if (root.readyToSave) saveTimer.restart()
  }

  function flush() {
    if (!root.readyToSave || !root.dirReady) return
    dataFile.setText(Model.serialize(root.state))
  }

  function adopt(next) {
    root.state = next
    root.loaded = true
    root.readyToSave = true
    root.lastSampleMs = Date.now()
    root.trackingId = ""
    root.refreshCatalog()
    root.sample()
  }

  function ingest(raw, existed) {
    if (!root.dirReady || root.loaded) return
    var parsed = Model.parseState(raw, Date.now())
    if (!parsed.ok && existed) {
      root.readyToSave = false
      quarantineProc.command = ["cp", "-f", "--", root.dataPath, root.dataPath + ".corrupt-" + Date.now()]
      quarantineProc.running = true
      return
    }
    root.adopt(parsed.ok ? parsed.state : Model.emptyState())
  }

  function sample() {
    if (!root.loaded) return
    var now = Date.now()
    var active = root.currentFocus()
    var activeId = active ? active.id : ""
    var idle = idleMonitor.isIdle
    var should = !root.state.paused && !idle && activeId !== ""
    var changed = false
    if (root.lastSampleMs > 0 && root.trackingId) {
      var credited = Model.applyElapsed(root.state, root.trackingId, root.lastSampleMs, now, root.maxGapMs, root.warnRatio)
      if (credited.changed) {
        root.state = credited.state
        changed = true
        if (credited.events.length) root.notify(credited.events)
      }
    }
    if (active) {
      var touched = Model.touchApp(root.state, active.id, active.name, active.icon, active.matched)
      if (touched.changed) {
        root.state = touched.state
        changed = true
      }
      if (!active.matched && root.catalog.length === 0) root.refreshCatalog()
    }
    root.focusedId = activeId
    root.focusedTitle = active ? active.title : ""
    root.trackingId = should ? activeId : ""
    root.lastSampleMs = now
    root.publish()
    if (changed) root.scheduleSave()
  }

  function setPaused(value) {
    if (!root.loaded) return
    root.sample()
    root.state = Model.setPaused(root.state, !!value)
    root.trackingId = ""
    root.lastSampleMs = Date.now()
    root.publish()
    root.flush()
  }

  function setLimit(appId, minutes) {
    if (!root.loaded) return
    var result = Model.setLimit(root.state, appId, minutes, Model.dayKey(new Date()), root.warnRatio)
    if (!result.changed) return
    root.state = result.state
    root.publish()
    root.flush()
    if (result.events.length) root.notify(result.events)
  }

  Component.onDestruction: root.flush()

  IdleMonitor {
    id: idleMonitor
    enabled: root.loaded && !root.state.paused
    timeout: Math.max(30, root.idleMinutes * 60)
    respectInhibitors: true
    onIsIdleChanged: root.sample()
  }

  Timer {
    interval: root.tickMs
    repeat: true
    running: root.loaded
    onTriggered: root.sample()
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.loaded
    onTriggered: root.refreshCatalog()
  }

  Timer {
    id: saveTimer
    interval: 4000
    repeat: false
    onTriggered: root.flush()
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.sample() }
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.dataDir]
    running: true
    onExited: {
      root.dirReady = true
      dataFile.reload()
    }
  }

  Process { id: quarantineProc; onExited: root.adopt(Model.emptyState()) }

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.ingest(text(), true)
    onLoadFailed: root.ingest("", false)
  }
}
