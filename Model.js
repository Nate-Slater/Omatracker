.pragma library

var VERSION = 1
var KEEP_DAYS = 90
var MAX_LIMIT_MINUTES = 24 * 60
var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var PRESETS = [
  { label: "15m", minutes: 15 },
  { label: "30m", minutes: 30 },
  { label: "1h", minutes: 60 },
  { label: "2h", minutes: 120 },
  { label: "4h", minutes: 240 },
  { label: "Off", minutes: 0 }
]
var IGNORED = {
  "quickshell": true,
  "hyprland": true,
  "org.omarchy.screensaver": true,
  "org.omarchy.lock": true,
  "omarchy-shell": true,
  "omarchy-lock": true
}
var WRAPPERS = {
  gamescope: true,
  steam: true,
  steamwebhelper: true,
  lutris: true,
  heroic: true
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

function dayKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function dayKeyFromMs(ms) {
  return dayKey(new Date(ms))
}

function parseDayKey(key) {
  var parts = String(key || "").split("-")
  if (parts.length !== 3) return null
  var y = Number(parts[0])
  var m = Number(parts[1])
  var d = Number(parts[2])
  if (!isFinite(y) || !isFinite(m) || !isFinite(d)) return null
  return new Date(y, m - 1, d)
}

function startOfNextDay(ms) {
  var date = new Date(ms)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime()
}

function dayLabel(key) {
  var date = parseDayKey(key)
  if (!date) return String(key || "")
  return DAY_NAMES[date.getDay()] + " " + date.getDate()
}

function weekKeys(todayKey, count) {
  var date = parseDayKey(todayKey)
  if (!date) return []
  var n = Math.max(1, count || 7)
  var out = []
  for (var i = n - 1; i >= 0; i--) {
    out.push(dayKey(new Date(date.getFullYear(), date.getMonth(), date.getDate() - i)))
  }
  return out
}

function emptyState() {
  return { version: VERSION, paused: false, apps: {}, days: {}, limits: {}, notices: {} }
}

function clone(state) {
  return JSON.parse(JSON.stringify(state))
}

function normalizeAppId(raw) {
  var s = String(raw || "").replace(/^\s+|\s+$/g, "")
  if (!s) return ""
  if (s.slice(-8).toLowerCase() === ".desktop") s = s.slice(0, -8)
  var slash = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"))
  if (slash >= 0) s = s.slice(slash + 1)
  return s.toLowerCase()
}

function cleanTitle(title) {
  return String(title || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/\s+[-–—]\s+(Steam|Lutris|Heroic|Gamescope)$/i, "")
}

function slug(text) {
  return normalizeAppId(text).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
}

function identityFor(appId, title) {
  var id = normalizeAppId(appId)
  if (!id || isIgnored(id)) return { id: "", name: "", wrapped: false }
  if (!WRAPPERS[id]) return { id: id, name: "", wrapped: false }
  var name = cleanTitle(title)
  var key = slug(name)
  if (!key || key === id) return { id: id, name: name, wrapped: false }
  return { id: id + ":" + key, name: name, wrapped: true }
}

function isIgnored(id) {
  var key = normalizeAppId(id)
  if (!key || IGNORED[key]) return true
  return key.indexOf("screensaver") >= 0
}

function tailId(id) {
  var parts = normalizeAppId(id).split(".")
  return parts[parts.length - 1] || ""
}

function prettify(raw) {
  var tail = tailId(raw) || normalizeAppId(raw)
  tail = tail.replace(/[-_]+/g, " ").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  if (!tail) return "Unknown"
  var words = tail.split(" ")
  for (var i = 0; i < words.length; i++) {
    if (!words[i]) continue
    words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
  }
  return words.join(" ")
}

function lookupApp(entries, rawId) {
  var key = normalizeAppId(rawId)
  var best = null
  var bestScore = 0
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry) continue
    var id = normalizeAppId(entry.id)
    if (!id) continue
    var score = 0
    if (id === key) score = 100
    else if (key && id.length > key.length && id.slice(-key.length - 1) === "." + key) score = 80
    else if (key && key.length > id.length && id.length > 2 && key.slice(-id.length - 1) === "." + id) score = 75
    else if (tailId(id).length > 2 && tailId(id) === tailId(key)) score = 60
    if (score > bestScore) {
      bestScore = score
      best = entry
    }
  }
  if (!best || bestScore < 55) return { name: prettify(rawId), icon: "", matched: false }
  return {
    name: String(best.name || prettify(rawId)),
    icon: String(best.icon || ""),
    matched: true
  }
}

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function warnRatioOf(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0 || n > 1) return 0.8
  return n
}

function formatDuration(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  m = m % 60
  return m ? h + "h " + m + "m" : h + "h"
}

function formatCompact(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  return Math.floor(m / 60) + "h"
}

function formatLimit(minutes) {
  var n = Math.round(Number(minutes) || 0)
  if (n <= 0) return "Off"
  return formatDuration(n * 60)
}

function truncate(text, max) {
  var s = String(text || "")
  if (s.length <= max) return s
  return s.slice(0, Math.max(1, max - 1)) + "…"
}

function statusFor(seconds, limitSeconds, warnRatio) {
  if (!(limitSeconds > 0)) return "open"
  var ratio = warnRatioOf(warnRatio)
  if (seconds >= limitSeconds) return "over"
  if (seconds >= limitSeconds * ratio) return "warn"
  return "ok"
}

function sanitizeApps(raw) {
  var out = {}
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  for (var id in raw) {
    var key = normalizeAppId(id)
    var app = raw[id]
    if (!key || !app || typeof app !== "object") continue
    out[key] = {
      name: String(app.name || prettify(key)),
      icon: String(app.icon || "")
    }
  }
  return out
}

function sanitizeDays(raw) {
  var out = {}
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  for (var key in raw) {
    if (!parseDayKey(key)) continue
    var usage = raw[key]
    if (!usage || typeof usage !== "object" || Array.isArray(usage)) continue
    var day = {}
    for (var id in usage) {
      var appId = normalizeAppId(id)
      var seconds = clampInt(usage[id], 0, 24 * 60 * 60, -1)
      if (!appId || seconds < 0 || isIgnored(appId)) continue
      day[appId] = seconds
    }
    if (Object.keys(day).length) out[key] = day
  }
  return out
}

function sanitizeLimits(raw) {
  var out = {}
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  for (var id in raw) {
    var key = normalizeAppId(id)
    var minutes = clampInt(raw[id], 1, MAX_LIMIT_MINUTES, -1)
    if (!key || minutes < 0 || isIgnored(key)) continue
    out[key] = minutes
  }
  return out
}

function sanitizeNotices(raw) {
  var out = {}
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  for (var key in raw) {
    if (!parseDayKey(key)) continue
    var apps = raw[key]
    if (!apps || typeof apps !== "object" || Array.isArray(apps)) continue
    var day = {}
    for (var id in apps) {
      var appId = normalizeAppId(id)
      var note = apps[id]
      if (!appId || !note || typeof note !== "object") continue
      day[appId] = { warn: note.warn === true, over: note.over === true }
    }
    if (Object.keys(day).length) out[key] = day
  }
  return out
}

function prune(state, todayKey, keepDays) {
  var today = parseDayKey(todayKey)
  if (!today) return state
  var next = clone(state)
  var keep = Math.max(1, keepDays || KEEP_DAYS)
  var oldest = new Date(today.getFullYear(), today.getMonth(), today.getDate() - (keep - 1)).getTime()
  var days = {}
  for (var key in next.days) {
    var date = parseDayKey(key)
    if (date && date.getTime() >= oldest && date.getTime() <= today.getTime()) days[key] = next.days[key]
  }
  next.days = days
  var keptNotices = {}
  for (var noticeKey in next.notices) {
    var noticeDate = parseDayKey(noticeKey)
    if (noticeDate && noticeDate.getTime() >= oldest && noticeDate.getTime() <= today.getTime())
      keptNotices[noticeKey] = next.notices[noticeKey]
  }
  next.notices = keptNotices
  return next
}

function parseState(text, nowMs) {
  var raw = String(text || "").replace(/^\s+|\s+$/g, "")
  if (!raw) return { ok: true, state: emptyState() }
  var data
  try { data = JSON.parse(raw) } catch (e) { return { ok: false, state: emptyState() } }
  if (!data || typeof data !== "object" || Array.isArray(data)) return { ok: false, state: emptyState() }
  if (data.version !== undefined && data.version !== VERSION) return { ok: false, state: emptyState() }
  var state = emptyState()
  state.paused = data.paused === true
  state.apps = sanitizeApps(data.apps)
  state.days = sanitizeDays(data.days)
  state.limits = sanitizeLimits(data.limits)
  state.notices = sanitizeNotices(data.notices)
  return { ok: true, state: prune(state, dayKey(new Date(nowMs || Date.now())), KEEP_DAYS) }
}

function serialize(state) {
  return JSON.stringify(state, null, 2) + "\n"
}

function touchApp(state, id, name, icon, matched) {
  var key = normalizeAppId(id)
  if (!key || isIgnored(key)) return { state: state, changed: false }
  var prev = state.apps[key] || {}
  var nextName = prev.name || name || prettify(key)
  var nextIcon = prev.icon || icon || ""
  if (matched && name) nextName = name
  if (matched && icon) nextIcon = icon
  if (prev.name === nextName && prev.icon === nextIcon) return { state: state, changed: false }
  var next = clone(state)
  next.apps[key] = { name: nextName, icon: nextIcon }
  return { state: next, changed: true }
}

function noteFor(state, day, id) {
  if (!state.notices[day]) state.notices[day] = {}
  if (!state.notices[day][id]) state.notices[day][id] = { warn: false, over: false }
  return state.notices[day][id]
}

function clearNotice(state, day, id, kind) {
  if (!state.notices[day] || !state.notices[day][id]) return
  state.notices[day][id][kind] = false
}

function takeThresholds(state, id, day, before, after, warnRatio) {
  var limitMin = state.limits[id] || 0
  if (!(limitMin > 0)) return []
  var limitSec = limitMin * 60
  var ratio = warnRatioOf(warnRatio)
  var warnAt = limitSec * ratio
  var note = noteFor(state, day, id)
  var name = (state.apps[id] && state.apps[id].name) || prettify(id)
  var event = {
    id: id,
    name: name,
    seconds: after,
    limitMinutes: limitMin
  }
  if (after >= limitSec && before < limitSec && !note.over) {
    note.over = true
    note.warn = true
    event.type = "over"
    return [event]
  }
  if (after >= warnAt && before < warnAt && !note.warn && after < limitSec) {
    note.warn = true
    event.type = "warn"
    return [event]
  }
  return []
}

function applyElapsed(state, appId, startMs, endMs, maxGapMs, warnRatio) {
  var id = normalizeAppId(appId)
  if (!id || isIgnored(id)) return { state: state, events: [], changed: false }
  var elapsed = endMs - startMs
  if (!(elapsed > 0) || elapsed > maxGapMs) return { state: state, events: [], changed: false }
  var next = clone(state)
  var events = []
  var changed = false
  var cursor = startMs
  while (cursor < endMs) {
    var sliceEnd = Math.min(endMs, startOfNextDay(cursor))
    var add = Math.round((sliceEnd - cursor) / 1000)
    if (add > 0) {
      var key = dayKeyFromMs(cursor)
      if (!next.days[key]) next.days[key] = {}
      var before = next.days[key][id] || 0
      var after = Math.min(24 * 60 * 60, before + add)
      if (after !== before) {
        next.days[key][id] = after
        var fired = takeThresholds(next, id, key, before, after, warnRatio)
        for (var i = 0; i < fired.length; i++) events.push(fired[i])
        changed = true
      }
    }
    if (sliceEnd <= cursor) break
    cursor = sliceEnd
  }
  if (!changed) return { state: state, events: [], changed: false }
  return { state: prune(next, dayKeyFromMs(endMs), KEEP_DAYS), events: events, changed: true }
}

function setPaused(state, paused) {
  if (!!state.paused === !!paused) return state
  var next = clone(state)
  next.paused = !!paused
  return next
}

function setLimit(state, appId, minutes, dayKey, warnRatio) {
  var id = normalizeAppId(appId)
  if (!id || isIgnored(id)) return { state: state, events: [], changed: false }
  var next = clone(state)
  var n = Math.round(Number(minutes) || 0)
  if (n <= 0) delete next.limits[id]
  else next.limits[id] = Math.max(1, Math.min(MAX_LIMIT_MINUTES, n))
  if (!next.apps[id]) next.apps[id] = { name: prettify(id), icon: "" }
  var used = (next.days[dayKey] && next.days[dayKey][id]) || 0
  var limitSec = (next.limits[id] || 0) * 60
  var ratio = warnRatioOf(warnRatio)
  if (!(limitSec > 0) || used < limitSec) clearNotice(next, dayKey, id, "over")
  if (!(limitSec > 0) || used < limitSec * ratio) clearNotice(next, dayKey, id, "warn")
  var events = takeThresholds(next, id, dayKey, 0, used, ratio)
  return { state: next, events: events, changed: true }
}

function rowsFor(state, key, includeEmptyLimits, warnRatio) {
  var usage = state.days[key] || {}
  var seen = {}
  var rows = []
  function push(id) {
    if (seen[id]) return
    seen[id] = true
    var seconds = usage[id] || 0
    var limitMinutes = state.limits[id] || 0
    if (seconds <= 0 && !(includeEmptyLimits && limitMinutes > 0)) return
    var app = state.apps[id] || {}
    rows.push({
      id: id,
      name: app.name || prettify(id),
      icon: app.icon || "",
      seconds: seconds,
      limitMinutes: limitMinutes,
      status: statusFor(seconds, limitMinutes * 60, warnRatio)
    })
  }
  for (var id in usage) push(id)
  if (includeEmptyLimits) for (var lid in state.limits) push(lid)
  rows.sort(function(a, b) {
    if (b.seconds !== a.seconds) return b.seconds - a.seconds
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })
  return rows
}

function dayTotal(rows) {
  var total = 0
  for (var i = 0; i < rows.length; i++) total += rows[i].seconds
  return total
}

function dayOver(rows) {
  for (var i = 0; i < rows.length; i++) if (rows[i].status === "over") return true
  return false
}

function snapshot(state, focusedId, since, title, warnRatio, nowMs) {
  var ratio = warnRatioOf(warnRatio)
  var today = dayKey(new Date(nowMs || Date.now()))
  var keys = weekKeys(today, 7)
  var days = {}
  var week = []
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var rows = rowsFor(state, key, key === today, ratio)
    var total = dayTotal(rows)
    days[key] = { total: total, rows: rows }
    week.push({
      key: key,
      label: dayLabel(key),
      seconds: total,
      over: dayOver(rows),
      isToday: key === today
    })
  }
  var focused = normalizeAppId(focusedId)
  var focusedApp = focused && state.apps[focused] ? state.apps[focused] : null
  var todayRows = days[today] ? days[today].rows : []
  var overCount = 0
  for (var r = 0; r < todayRows.length; r++) if (todayRows[r].status === "over") overCount++
  return {
    paused: state.paused === true,
    focusedId: focused,
    focusedName: focusedApp ? focusedApp.name : (focused ? prettify(focused) : ""),
    focusedTitle: String(title || ""),
    since: since > 0 ? since : 0,
    todayKey: today,
    warnRatio: ratio,
    week: week,
    days: days,
    limits: clone(state).limits,
    apps: clone(state).apps,
    overCount: overCount
  }
}

function bankedSeconds(snap, id) {
  if (!snap || !id) return 0
  var day = snap.days && snap.days[snap.todayKey]
  var rows = day && day.rows ? day.rows : []
  for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i].seconds
  return 0
}

function liveSeconds(snap, nowMs) {
  if (!snap || !snap.focusedId) return 0
  var seconds = bankedSeconds(snap, snap.focusedId)
  if (snap.since > 0 && nowMs > snap.since) seconds += Math.max(0, Math.round((nowMs - snap.since) / 1000))
  return seconds
}

function displaySeconds(snap, nowMs) {
  if (snap && snap.focusedId) return liveSeconds(snap, nowMs)
  var day = snap && snap.days && snap.days[snap.todayKey]
  return day ? day.total : 0
}

function liveStatus(snap, nowMs) {
  if (!snap || !snap.focusedId) return "open"
  var limitMin = snap.limits && snap.limits[snap.focusedId] ? snap.limits[snap.focusedId] : 0
  return statusFor(liveSeconds(snap, nowMs), limitMin * 60, snap.warnRatio)
}

function barLabel(snap, nowMs, showName, vertical) {
  if (!snap) return ""
  if (snap.paused) return vertical ? "–" : "Paused"
  var seconds = displaySeconds(snap, nowMs)
  var time = vertical ? formatCompact(seconds) : formatDuration(seconds)
  if (!snap.focusedId) return vertical ? time : "Today " + time
  if (!showName || vertical || !snap.focusedName) return time
  return truncate(snap.focusedName, 16) + "  " + time
}

function tooltip(snap, nowMs) {
  if (!snap) return "Omatracker"
  if (snap.paused) return "Omatracker is paused. Right-click to resume."
  var parts = []
  if (snap.focusedName) parts.push(snap.focusedName)
  if (snap.focusedId) {
    var bit = formatDuration(liveSeconds(snap, nowMs))
    var limit = snap.limits && snap.limits[snap.focusedId] ? snap.limits[snap.focusedId] : 0
    if (limit > 0) bit += " of " + formatLimit(limit)
    parts.push(bit)
  }
  var day = snap.days && snap.days[snap.todayKey]
  parts.push("today " + formatDuration(day ? day.total : 0))
  if (snap.overCount > 0) parts.push(snap.overCount + (snap.overCount === 1 ? " app over its limit" : " apps over their limit"))
  parts.push("Right-click pauses")
  return parts.join(" · ")
}
