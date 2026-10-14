# Security review — 2026-10-14

Baseline: `4734f2f9be2f18674f93e848e5e4d0aeef3fab5b`.
Report: [marketplace review comment](https://github.com/omacom/omarchy-plugin-marketplace/issues/11316#issuecomment-6157311553).

## Addressed

- History, corrupt backups, and atomic-save files are private from their first
  sensitive byte: directory `0700`, files `0600`.
- Existing history/backups are migrated before FileView is given a path.
- Named access ACLs are removed; inherited default ACLs are replaced with
  owner-only defaults. Both ACL contents and mode bits are checked.
- Missing history is seeded empty at `0600` before QSaveFile opens it. Its
  atomic replacement preserves the mode. There is no post-save chmod.
- Corrupt backups are created empty, verified, then populated. A failed backup
  does not authorize replacing the original; a collision preserves the prior copy.
- Permission-helper failures, abnormal exits, read errors, and save errors
  disable further tracking/persistence. Regular owned singly-linked files are
  required; symlinks and special files are rejected.
- Periodic saving no longer gets postponed indefinitely by each one-second
  sample. Teardown cannot bypass the pre-write check.

## Trust boundaries and scope

Reviewed all repository QML/JavaScript, manifest, helper, and documentation,
plus FileView/QSaveFile behavior and the installed Omarchy command interfaces.
This is a source review and regression verification, not marketplace approval
or a certification of Qt/Quickshell/Omarchy or all possible filesystems.

Omarchy deliberately runs plugins unsandboxed, under the login user. Same-user
processes and root remain trusted; excluding them requires an OS-enforced
security boundary and a different architecture. The filesystem must genuinely
enforce the permissions it reports. Parent paths and plugin code must be trusted.

The plugin declares service and bar-widget entry points and internally loads
its panel. It has no install hooks, privilege escalation, network client,
dynamic code evaluation, or plugin IPC handler. UI text is plain text. Commands
use argument vectors; history is not placed on a subprocess command line.

Notifications go to Omarchy's notification service, which can persist them
outside the tracker directory. This repository does not change another
plugin's files or system configuration. Securing the notification store on an
installed machine is a separate administrator/user configuration action.

## Verification

```sh
omarchy plugin validate .
node --test test.js test-restrict.js test-service.js
bash -n restrict-store.sh
c++ -fPIC test-atomic.cpp -o /tmp/omatracker-atomic $(pkg-config --cflags --libs Qt6Core)
/tmp/omatracker-atomic ./restrict-store.sh
qmllint -I "$OMARCHY_PATH/shell" Service.qml BarWidget.qml Panel.qml
```

The Node regressions exercise umask `022`/`000`, existing-data migration,
named/default ACL grants, missing-file reseeding, backup privacy before copying,
backup collisions, symlinks/hardlinks, and permission changes that appear to
succeed but leave unsafe modes. Service-handler tests cover the read/write
permission gates, abnormal exits, failed backups, and periodic scheduling.
The Qt regression inspects the actual open
QSaveFile temporary inode before and after writing and the committed inode,
under umask `022`, `000`, and `077`, with no post-write permission repair.

On installations where standalone qmllint cannot resolve Quickshell's virtual
`qs` imports, provide a temporary import root with `qs` pointing at the installed
shell directory. This is tooling setup outside the plugin; the distributable
plugin directory contains no symlinks. Runtime loading is checked in the
existing Omarchy shell, not a second plugin shell process.
