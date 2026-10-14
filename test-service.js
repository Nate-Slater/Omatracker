const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

// Exercise the service's real JS handlers with I/O boundaries replaced by
// spies. Filesystem/ACL and actual QSaveFile behavior have separate tests.
const source = fs.readFileSync(path.join(__dirname, "Service.qml"), "utf8")
const functions = source.match(/^  function \w+\([^\n]*\) \{[\s\S]*?^  \}/gm)
function harness() {
  const commands = [], writes = [], reads = [], later = []
  const root = {
    loaded: false, permsReady: false, readyToSave: false, writing: false,
    saveQueued: false, permAction: "", savedText: "", trackerState: { version: 1 },
    restrictScript: "/plugin/restrict-store.sh", dataDir: "/home/test/omatracker",
    dataPath: "/home/test/omatracker/data.json"
  }
  const dataFile = { setText: text => writes.push(text) }
  Object.defineProperty(dataFile, "path", { set: value => reads.push(value) })
  const saveTimer = {
    running: false, starts: 0,
    start() { this.running = true; this.starts++ },
    stop() { this.running = false }
  }
  const context = vm.createContext({
    root, dataFile, saveTimer, console: { warn() {} },
    Model: { serialize: JSON.stringify },
    permProc: { exec: args => commands.push(Array.from(args)) },
    Qt: { callLater: fn => later.push(fn) }
  })
  vm.runInContext(functions.join("\n"), context)
  for (const key of Object.keys(context)) if (typeof context[key] === "function") root[key] = context[key]
  return { root, reads, writes, commands, saveTimer, later }
}

test("no history read or write until permission preparation succeeds", () => {
  const h = harness()
  h.root.flush()
  assert.equal(h.commands.length, 0)
  assert.equal(h.writes.length, 0)
  assert.equal(h.reads.length, 0)
  h.root.execPerm("prepare")
  assert.equal(h.reads.length, 0)
  h.root.finishPerm(0, 0)
  assert.deepEqual(h.reads, [h.root.dataPath])
})

test("failed preparation and signal termination never authorize a read", () => {
  for (const [code, status] of [[1, 0], [0, 1]]) {
    const h = harness()
    h.root.execPerm("prepare")
    h.root.finishPerm(code, status)
    h.root.flush()
    assert.equal(h.reads.length, 0)
    assert.equal(h.writes.length, 0)
    assert.equal(h.root.readyToSave, false)
  }
})

test("each save waits for successful permission verification, including first save", () => {
  const h = harness()
  Object.assign(h.root, { loaded: true, permsReady: true, readyToSave: true })
  h.root.flush()
  assert.equal(h.commands[0][2], "tighten")
  assert.equal(h.writes.length, 0)
  h.root.finishPerm(0, 0)
  assert.deepEqual(h.writes, ['{"version":1}'])
  h.root.noteSaved()
  assert.equal(h.commands.length, 1, "no post-write chmod")
})

test("failed pre-write check disables persistence and tracking", () => {
  const h = harness()
  Object.assign(h.root, { loaded: true, permsReady: true, readyToSave: true })
  h.root.flush()
  h.root.finishPerm(1, 0)
  h.root.flush()
  assert.equal(h.writes.length, 0)
  assert.equal(h.root.loaded, false)
  assert.equal(h.root.readyToSave, false)
})

test("failed corrupt backup does not adopt an empty state", () => {
  const h = harness()
  h.root.adopt = () => assert.fail("must not overwrite unrecoverable history")
  h.root.execPerm("quarantine", h.root.dataPath + ".corrupt-42")
  h.root.finishPerm(1, 0)
  assert.equal(h.writes.length, 0)
  assert.equal(h.root.readyToSave, false)
})

test("one-second samples do not indefinitely postpone periodic saving", () => {
  const h = harness()
  h.root.readyToSave = true
  for (let i = 0; i < 10; i++) h.root.scheduleSave()
  assert.equal(h.saveTimer.starts, 1)
})
