const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const script = path.join(__dirname, "restrict-store.sh")
const scratchDirs = []
test.after(() => scratchDirs.forEach(dir => fs.rmSync(dir, { recursive: true, force: true })))

function mode(target) {
  return (fs.statSync(target).mode & 0o777).toString(8)
}

function run(args, umask = "022") {
  return execFileSync("bash", ["-c", 'umask "$1"; shift; exec bash "$@"', "bash", umask, script, ...args], {
    encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]
  })
}

function fail(args, umask = "022") {
  assert.throws(() => run(args, umask))
}

function scratch() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omatracker-restrict-"))
  scratchDirs.push(dir)
  return dir
}

test("prepare creates and verifies an empty private file before any history write", () => {
  const root = scratch()
  const dir = path.join(root, "missing", "omatracker")
  const file = path.join(dir, "data.json")
  run(["prepare", dir, file], "022")
  assert.equal(mode(dir), "700")
  assert.equal(mode(file), "600")
  assert.equal(fs.readFileSync(file, "utf8"), "")
  assert.equal(mode(path.join(root, "missing")), "700")
})

test("prepare migrates a umask-022 tree before returning", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  const backup = file + ".corrupt-1700000000000"
  const leftover = file + ".AbCdEf"
  fs.mkdirSync(dir, { mode: 0o755 })
  fs.writeFileSync(file, "{\"version\":1}\n", { mode: 0o644 })
  fs.writeFileSync(backup, "corrupt\n", { mode: 0o644 })
  fs.writeFileSync(leftover, "partial\n", { mode: 0o644 })
  fs.chmodSync(dir, 0o755)
  run(["prepare", dir, file], "022")
  assert.equal(mode(dir), "700")
  assert.equal(mode(file), "600")
  assert.equal(mode(backup), "600")
  assert.equal(mode(leftover), "600")
  assert.equal(fs.readFileSync(file, "utf8"), "{\"version\":1}\n")
})

test("tighten is idempotent and clears group and other bits", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  fs.mkdirSync(dir, { mode: 0o777 })
  fs.writeFileSync(file, "x\n", { mode: 0o666 })
  fs.chmodSync(dir, 0o777)
  run(["tighten", dir, file], "000")
  assert.equal(mode(dir), "700")
  assert.equal(mode(file), "600")
  run(["tighten", dir, file], "022")
  assert.equal(mode(dir), "700")
  assert.equal(mode(file), "600")
})

test("quarantine backup is 0600 even when umask is 022", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  const dest = file + ".corrupt-42"
  fs.mkdirSync(dir, { mode: 0o755 })
  fs.writeFileSync(file, "secret history\n", { mode: 0o644 })
  fs.chmodSync(dir, 0o755)
  run(["quarantine", dir, file, dest], "022")
  assert.equal(mode(dir), "700")
  assert.equal(mode(file), "600")
  assert.equal(mode(dest), "600")
  assert.equal(fs.readFileSync(dest, "utf8"), "secret history\n")
})

test("quarantine never overwrites an earlier recovery copy", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  const dest = file + ".corrupt-7"
  fs.mkdirSync(dir, { mode: 0o700 })
  fs.writeFileSync(file, "history\n", { mode: 0o600 })
  fs.writeFileSync(dest, "old\n", { mode: 0o644 })
  fail(["quarantine", dir, file, dest], "022")
  assert.equal(mode(dest), "600")
  assert.equal(fs.readFileSync(dest, "utf8"), "old\n")
})

test("refuses a symlink directory without chmod of the target", () => {
  const root = scratch()
  const real = path.join(root, "real")
  const link = path.join(root, "omatracker")
  fs.mkdirSync(real, { mode: 0o755 })
  fs.symlinkSync(real, link)
  fail(["prepare", link, path.join(link, "data.json")])
  assert.equal(mode(real), "755")
})

test("refuses a symlink history file without chmod of the target", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const outside = path.join(root, "outside.json")
  const file = path.join(dir, "data.json")
  fs.mkdirSync(dir, { mode: 0o755 })
  fs.writeFileSync(outside, "other\n", { mode: 0o644 })
  fs.symlinkSync(outside, file)
  fail(["prepare", dir, file])
  assert.equal(mode(outside), "644")
  assert.equal(fs.lstatSync(file).isSymbolicLink(), true)
})

test("refuses a symlink corrupt backup without chmod of the target", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const outside = path.join(root, "outside.json")
  const file = path.join(dir, "data.json")
  const backup = file + ".corrupt-1"
  fs.mkdirSync(dir, { mode: 0o700 })
  fs.writeFileSync(file, "history\n", { mode: 0o600 })
  fs.writeFileSync(outside, "other\n", { mode: 0o644 })
  fs.symlinkSync(outside, backup)
  fail(["prepare", dir, file])
  assert.equal(mode(outside), "644")
})

test("refuses a quarantine destination outside the history name", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  const outside = path.join(root, "escaped")
  fs.mkdirSync(dir, { mode: 0o700 })
  fs.writeFileSync(file, "history\n", { mode: 0o600 })
  fail(["quarantine", dir, file, outside])
  fail(["quarantine", dir, file, file + ".corrupt-12/../../escaped"])
  fail(["quarantine", dir, file, file + ".corrupt-12abc"])
  assert.equal(fs.existsSync(outside), false)
  assert.equal(fs.readFileSync(file, "utf8"), "history\n")
})

test("refuses a history path that is not the tracker data.json", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  fs.mkdirSync(dir, { mode: 0o755 })
  fail(["prepare", dir, path.join(dir, "other.json")])
  fail(["prepare", "omatracker", "omatracker/data.json"])
})

function acl(target) {
  return execFileSync("getfacl", ["-cpE", "--", target], { encoding: "utf8" }).trim()
}

test("named and default ACL grants are removed before reading or creating history", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  // Inherit a grant for another account, independent of the process umask.
  execFileSync("setfacl", ["-m", "d:u::rwx,d:u:65534:rwx,d:g::r-x,d:m::rwx,d:o::r-x", root])
  fs.mkdirSync(dir)
  fs.writeFileSync(file, "secret")
  const backup = file + ".corrupt-1"
  fs.writeFileSync(backup, "older secret")
  assert.match(acl(file), /user:nobody:|user:65534:/)
  run(["prepare", dir, file], "000")
  const privateFile = "user::rw-\ngroup::---\nother::---"
  assert.equal(acl(file), privateFile)
  assert.equal(acl(backup), privateFile)
  assert.equal(acl(dir), "user::rwx\ngroup::---\nother::---\ndefault:user::rwx\ndefault:group::---\ndefault:other::---")
  assert.equal(fs.readFileSync(file, "utf8"), "secret")
  // Even a future creator using 0666/umask 000 inherits owner-only access.
  const oldMask = process.umask(0)
  try { fs.writeFileSync(file + ".new", "new", { mode: 0o666 }) }
  finally { process.umask(oldMask) }
  assert.equal(mode(file + ".new"), "600")
  assert.equal(acl(file + ".new"), privateFile)
})

test("deleted history is re-seeded privately on the next pre-write check", () => {
  const dir = path.join(scratch(), "omatracker")
  const file = path.join(dir, "data.json")
  run(["prepare", dir, file])
  fs.unlinkSync(file)
  run(["tighten", dir, file], "000")
  assert.equal(mode(file), "600")
  assert.equal(fs.readFileSync(file, "utf8"), "")
})

test("refuses hard links without changing the external inode", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  fs.mkdirSync(dir)
  fs.writeFileSync(path.join(root, "outside"), "other", { mode: 0o644 })
  fs.linkSync(path.join(root, "outside"), file)
  fail(["prepare", dir, file])
  assert.equal(mode(file), "644")
})

test("a filesystem that reports unchanged permissions fails closed", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  fs.mkdirSync(dir)
  fs.chmodSync(dir, 0o755)
  const bin = path.join(root, "bin")
  fs.mkdirSync(bin)
  // Emulate a filesystem accepting but ignoring chmod/ACL changes.
  for (const cmd of ["chmod", "setfacl"]) fs.writeFileSync(path.join(bin, cmd), "#!/bin/sh\nexit 0\n", { mode: 0o755 })
  assert.throws(() => execFileSync("bash", [script, "prepare", dir, path.join(dir, "data.json")], {
    env: { ...process.env, PATH: bin + ":" + process.env.PATH }, stdio: "pipe"
  }))
  assert.equal(fs.existsSync(path.join(dir, "data.json")), false)
})

test("backup is private before its first byte is copied", () => {
  const root = scratch()
  const dir = path.join(root, "omatracker")
  const file = path.join(dir, "data.json")
  const dest = file + ".corrupt-9"
  run(["prepare", dir, file])
  fs.writeFileSync(file, "private")
  const bin = path.join(root, "bin")
  fs.mkdirSync(bin)
  fs.writeFileSync(path.join(bin, "cat"), '#!/bin/bash\n[[ $(stat -c %a -- "$DEST") == 600 && ! -s $DEST ]] || exit 1\nexec /usr/bin/cat "$@"\n', { mode: 0o755 })
  execFileSync("bash", [script, "quarantine", dir, file, dest], {
    env: { ...process.env, DEST: dest, PATH: bin + ":" + process.env.PATH }
  })
  assert.equal(fs.readFileSync(dest, "utf8"), "private")
})
