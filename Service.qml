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
  // An empty or relative HOME would land the history in the process cwd, which
  // may be traversable by other accounts. Fail closed instead.
  readonly property bool storageOk: home.length > 0 && home.charAt(0) === "/"
  readonly property string dataDir: home + "/.local/share/omatracker"
  readonly property string dataPath: dataDir + "/data.json"
  property string restrictScript: ""
  readonly property int tickMs: 1000
  readonly property int maxGapMs: 8000

  property bool loaded: false
  // True only after the tracker directory is 0700 and existing history and
  // corrupt backups are 0600. Nothing may read or write before that.
  property bool permsReady: false
  property bool readyToSave: false
  property bool writing: false
  property bool saveQueued: false
  property string permAction: ""
  property string savedText: ""
  property var trackerState: Model.emptyState()
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
      root.trackerState,
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
    if (root.readyToSave && !saveTimer.running) saveTimer.start()
  }

  function fileUrlPath(url) {
    var value = String(url || "")
    var prefix = "file://"
    if (value.indexOf(prefix) !== 0) return ""
    var path = decodeURIComponent(value.slice(prefix.length))
    return path.charAt(0) === "/" ? path : ""
  }

  function failClosed(message) {
    root.permsReady = false
    root.readyToSave = false
    root.loaded = false
    root.trackingId = ""
    root.writing = false
    root.saveQueued = false
    root.permAction = ""
    saveTimer.stop()
    console.warn(message)
  }

  function execPerm(action, extra) {
    var args = ["bash", root.restrictScript, action, root.dataDir, root.dataPath]
    if (extra) args.push(extra)
    root.permAction = action
    permProc.exec(args)
  }

  function prepareStorage() {
    root.restrictScript = root.fileUrlPath(Qt.resolvedUrl("restrict-store.sh"))
    if (!root.storageOk || !root.restrictScript) {
      root.failClosed("omatracker: not reading usage history; home or restrict script is unusable")
      return
    }
    root.execPerm("prepare")
  }

  // The helper seeds missing files at 0600 and verifies owner-only ACLs before
  // this write. QSaveFile preserves that mode; no post-save chmod is needed.
  function beginSave() {
    if (root.writing || root.permAction !== "") return
    if (!root.saveQueued || !root.readyToSave || !root.permsReady) return
    root.saveQueued = false
    root.execPerm("tighten")
  }

  function flush() {
    if (!root.readyToSave || !root.permsReady) return
    root.saveQueued = true
    root.beginSave()
  }

  function noteSaved() {
    root.writing = false
    // FileView completes its operation after emitting saved.
    Qt.callLater(root.beginSave)
  }

  function finishPerm(exitCode, exitStatus) {
    var action = root.permAction
    root.permAction = ""
    if (exitCode !== 0 || exitStatus !== 0) {
      root.failClosed("omatracker: not reading or writing usage history; could not keep it private")
      return
    }
    if (action === "prepare") {
      root.permsReady = true
      dataFile.path = root.dataPath
      return
    }
    if (action === "quarantine") {
      root.adopt(Model.emptyState())
      return
    }
    if (action === "tighten") {
      var text = Model.serialize(root.trackerState)
      if (text !== root.savedText) {
        root.writing = true
        root.savedText = text
        dataFile.setText(text)
      } else {
        Qt.callLater(root.beginSave)
      }
    }
  }

  function adopt(next) {
    root.trackerState = next
    root.loaded = true
    root.readyToSave = true
    root.lastSampleMs = Date.now()
    root.trackingId = ""
    root.refreshCatalog()
    root.sample()
  }

  function ingest(raw, existed) {
    if (!root.permsReady || root.loaded) return
    root.savedText = raw
    var parsed = Model.parseState(raw, Date.now())
    if (!parsed.ok && existed) {
      // Do not replace the corrupt file until its backup is mode 0600.
      root.readyToSave = false
      if (root.permAction !== "" || root.writing) {
        root.failClosed("omatracker: not writing usage history; could not quarantine a corrupt file privately")
        return
      }
      var stamp = String(Math.round(Date.now()))
      if (!/^[0-9]+$/.test(stamp)) {
        root.failClosed("omatracker: not writing usage history; could not name a private corrupt backup")
        return
      }
      root.execPerm("quarantine", root.dataPath + ".corrupt-" + stamp)
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
    var should = !root.trackerState.paused && !idle && activeId !== ""
    var changed = false
    if (root.lastSampleMs > 0 && root.trackingId) {
      var credited = Model.applyElapsed(root.trackerState, root.trackingId, root.lastSampleMs, now, root.maxGapMs, root.warnRatio)
      if (credited.changed) {
        root.trackerState = credited.state
        changed = true
        if (credited.events.length) root.notify(credited.events)
      }
    }
    if (active) {
      var touched = Model.touchApp(root.trackerState, active.id, active.name, active.icon, active.matched)
      if (touched.changed) {
        root.trackerState = touched.state
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
    root.trackerState = Model.setPaused(root.trackerState, !!value)
    root.trackingId = ""
    root.lastSampleMs = Date.now()
    root.publish()
    root.flush()
  }

  function setLimit(appId, minutes) {
    if (!root.loaded) return
    var result = Model.setLimit(root.trackerState, appId, minutes, Model.dayKey(new Date()), root.warnRatio)
    if (!result.changed) return
    root.trackerState = result.state
    root.publish()
    root.flush()
    if (result.events.length) root.notify(result.events)
  }

  Component.onCompleted: root.prepareStorage()

  Component.onDestruction: {
    // Only finish an already validated write. Do not bypass the permission
    // gate during teardown; the periodic timer bounds unsaved activity to 4s.
    if (root.writing) dataFile.waitForJob()
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.loaded && !root.trackerState.paused
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
    id: permProc
    onExited: function(exitCode, exitStatus) {
      root.finishPerm(exitCode, exitStatus)
    }
    // FailedToStart does not emit exited. Without this, a missing bash would
    // leave permAction set and tracking disabled with no warning.
    onRunningChanged: {
      if (!running) Qt.callLater(function() {
        if (!permProc.running && root.permAction !== "")
          root.failClosed("omatracker: not reading or writing usage history; could not run the permission check")
      })
    }
  }

  // Empty path prevents eager reads until the permission migration succeeds.
  FileView {
    id: dataFile
    path: ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.ingest(text(), true)
    // The helper has already created data.json: ANY read failure is an error,
    // not a first run. Never replace unreadable history with an empty state.
    onLoadFailed: root.failClosed("omatracker: could not read private usage history")
    onSaved: root.noteSaved()
    onSaveFailed: root.failClosed("omatracker: could not save private usage history")
  }
}
