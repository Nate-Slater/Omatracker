const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs
  .readFileSync(path.join(__dirname, "Model.js"), "utf8")
  .replace(/^\.pragma library\n/, "")
const M = vm.createContext({})
vm.runInContext(source, M)

const at = (y, mo, d, h, mi, s) => new Date(y, mo - 1, d, h || 0, mi || 0, s || 0).getTime()
const now = at(2026, 10, 12, 15, 0, 0)

test("wrappers take the window title as the program", () => {
  const game = M.identityFor("gamescope", "StarCraft II")
  assert.equal(game.wrapped, true)
  assert.equal(game.name, "StarCraft II")
  assert.equal(game.id, "gamescope:starcraft-ii")
  assert.equal(M.identityFor("firefox", "Inbox - Mozilla Firefox").wrapped, false)
  assert.equal(M.identityFor("org.omarchy.screensaver", "Screensaver").id, "")
})

test("normalizes and ignores shell surfaces", () => {
  assert.equal(M.normalizeAppId("Org.Mozilla.Firefox.desktop"), "org.mozilla.firefox")
  assert.equal(M.normalizeAppId("/usr/bin/kitty"), "kitty")
  assert.equal(M.isIgnored("org.omarchy.screensaver"), true)
  assert.equal(M.isIgnored("firefox"), false)
  assert.equal(M.prettify("brave-browser"), "Brave Browser")
  assert.equal(M.prettify("org.mozilla.firefox"), "Firefox")
})

test("lookup prefers an exact desktop id", () => {
  const entries = [
    { id: "firefox", name: "Firefox", icon: "firefox" },
    { id: "code", name: "Visual Studio Code", icon: "code" }
  ]
  const hit = M.lookupApp(entries, "FIREFOX")
  assert.equal(hit.name, "Firefox")
  assert.equal(hit.icon, "firefox")
  assert.equal(hit.matched, true)
  assert.equal(M.lookupApp(entries, "com.visualstudio.code").name, "Visual Studio Code")
  assert.equal(M.lookupApp(entries, "unknown-app").matched, false)
})

test("formats durations and limits", () => {
  assert.equal(M.formatDuration(12), "12s")
  assert.equal(M.formatDuration(90), "1m")
  assert.equal(M.formatDuration(3720), "1h 2m")
  assert.equal(M.formatLimit(0), "Off")
  assert.equal(M.formatLimit(90), "1h 30m")
  assert.equal(M.formatCompact(5400), "1h")
})

test("empty and corrupt files", () => {
  assert.equal(M.parseState("", now).ok, true)
  assert.equal(M.parseState("{", now).ok, false)
  assert.equal(M.parseState("[]", now).ok, false)
  assert.equal(M.parseState(JSON.stringify({ version: 2 }), now).ok, false)
  const parsed = M.parseState(JSON.stringify({
    version: 1,
    paused: true,
    apps: { Firefox: { name: "Firefox", icon: "firefox" } },
    days: { "2026-10-12": { firefox: 90, nope: -4 } },
    limits: { firefox: 30 }
  }), now)
  assert.equal(parsed.ok, true)
  assert.equal(parsed.state.paused, true)
  assert.equal(parsed.state.days["2026-10-12"].firefox, 90)
  assert.equal(parsed.state.limits.firefox, 30)
})

test("credits the focused app and splits midnight", () => {
  let state = M.emptyState()
  const start = at(2026, 10, 12, 23, 59, 58)
  const end = at(2026, 10, 13, 0, 0, 3)
  const result = M.applyElapsed(state, "firefox", start, end, 20000, 0.8)
  assert.equal(result.changed, true)
  assert.equal(result.state.days["2026-10-12"].firefox, 2)
  assert.equal(result.state.days["2026-10-13"].firefox, 3)
})

test("drops gaps from sleep", () => {
  const result = M.applyElapsed(M.emptyState(), "firefox", now, now + 60000, 8000, 0.8)
  assert.equal(result.changed, false)
})

test("warns once, then notifies when the limit is crossed", () => {
  let state = M.setLimit(M.emptyState(), "firefox", 1, "2026-10-12", 0.8).state
  state = M.touchApp(state, "firefox", "Firefox", "firefox", true).state
  let first = M.applyElapsed(state, "firefox", now, now + 48000, 60000, 0.8)
  assert.equal(first.events[0].type, "warn")
  let second = M.applyElapsed(first.state, "firefox", now + 48000, now + 60000, 60000, 0.8)
  assert.equal(second.events[0].type, "over")
  let again = M.applyElapsed(second.state, "firefox", now + 60000, now + 70000, 60000, 0.8)
  assert.equal(again.events.length, 0)
  assert.equal(M.applyElapsed(M.emptyState(), "quickshell", now, now + 5000, 20000, 0.8).changed, false)
})

test("setting a limit under today's usage notifies", () => {
  let state = M.applyElapsed(M.emptyState(), "code", now, now + 10000, 20000, 0.8).state
  state.days["2026-10-12"].code = 3600
  const result = M.setLimit(state, "code", 30, "2026-10-12", 0.8)
  assert.equal(result.events[0].type, "over")
  assert.equal(result.state.limits.code, 30)
  const cleared = M.setLimit(result.state, "code", 0, "2026-10-12", 0.8)
  assert.equal(cleared.state.limits.code, undefined)
})

test("snapshot lists limited apps even at zero and builds the week", () => {
  let state = M.setLimit(M.emptyState(), "firefox", 120, "2026-10-12", 0.8).state
  state = M.touchApp(state, "firefox", "Firefox", "firefox", true).state
  const snap = M.snapshot(state, "firefox", now, "inbox", 0.8, now)
  assert.equal(snap.todayKey, "2026-10-12")
  assert.equal(snap.week.length, 7)
  assert.equal(snap.week[6].isToday, true)
  assert.equal(snap.days["2026-10-12"].rows[0].name, "Firefox")
  assert.equal(snap.days["2026-10-12"].rows[0].limitMinutes, 120)
  assert.equal(M.liveSeconds(snap, now + 1500), 2)
  assert.equal(M.barLabel(snap, now + 1500, true, false), "Firefox  2s")
  assert.equal(M.liveStatus(snap, now), "ok")
})

test("bar label names a quiet session Today", () => {
  const snap = M.snapshot(M.emptyState(), "", 0, "", 0.8, now)
  assert.equal(M.barLabel(snap, now, true, false), "Today 0s")
  assert.match(M.tooltip(Object.assign({}, snap, { paused: true }), now), /paused/i)
})
