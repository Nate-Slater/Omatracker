# Omatracker

A theme-aware tracker for which programs are focused, and for how long, with daily limits. It runs inside the Omarchy shell. It does not start a second Quickshell process, install packages, or ask for extra privileges.

## Install

```sh
omarchy plugin add https://github.com/Nate-Slater/Omatracker.git --enable
```

That clones this repository, validates `manifest.json`, and adds the bar widget. Nothing in the plugin runs during install.

## Usage

Click the bar pill to open or close today's usage. Press Escape to close it. Right-click the pill to pause or resume.

Select a program in the panel to set a daily limit. Near the limit the pill uses the theme accent. At the limit it turns urgent and sends a notification through `omarchy-notification-send`, which ships with Omarchy.

Time counts only while a program is focused and the session is not idle. Games launched through Gamescope are tracked by their window title.

## Configure

```sh
omarchy bar move nate.omatracker --section right
```

Per-widget settings live on the bar entry: show the program name, warn percentage, and idle cutoff. Usage and limits are stored locally in `~/.local/share/omatracker/data.json`. That directory is kept at mode 0700, and the history file and any corrupt backups at mode 0600. An older install is migrated to those modes before the file is read or written again.

## Remove

```sh
omarchy plugin remove nate.omatracker
```

Removal disables the plugin and deletes this checkout. It does not delete `~/.local/share/omatracker/`. Remove that directory too if you want the history gone.

## License

MIT. See [LICENSE](LICENSE).

## Dependencies

Runtime dependencies are Omarchy/Quickshell, Bash, GNU coreutils (`mkdir`, `chmod`, `stat`, `cat`), and the Arch `acl` package (`setfacl`, `getfacl`). The bundled `restrict-store.sh` runs at startup and before saves to establish and verify private storage. `omarchy-notification-send` sends limit notifications. These dependencies are present on the tested Omarchy installation; the plugin does not install packages or request privileges. It has no network access, install hooks, remote builds, or separate service/Quickshell process.

## Ownership

The code in this repository is original. There are no preview images or other third-party assets.

## Configuration

The plugin does not write `shell.json`, Hyprland config, or any other app's files. Enabling it through `omarchy plugin add` is what places the bar widget, and that step asks first unless you pass `--enable`. The only files it creates are its own history, `~/.local/share/omatracker/data.json`, and a `data.json.corrupt-<time>` backup if that file cannot be parsed. Both stay mode 0600 inside a mode 0700 directory.

## Security

A marketplace listing is not a security certification. As described in the [Omarchy development guide](https://plugins.omarchy.org/develop.html), this plugin runs unsandboxed inside `omarchy-shell`, with your user permissions.

Before reading history or saving it, the plugin migrates existing files, removes named ACL grants, and verifies `0700` directories / `0600` files. The directory gets an owner-only default ACL so future files remain private even with umask `000`. Missing history and backup files are created empty and verified at `0600` **before** receiving private bytes. Atomic FileView saves preserve that mode, including temporary files; there is no post-save permission window. Permission/ACL failures stop tracking and persistence rather than loading or replacing the history. Symlink and multiply linked history entries are rejected. Storage must support POSIX permissions and ACLs and reside under a trusted user-owned home directory.

This protects against other unprivileged accounts on a correctly enforcing local filesystem. It cannot exclude root or processes running as your user, or compensate for a filesystem/server that falsely reports enforcing permissions. No locally stored encryption key would create a same-user security boundary. The plugin's code and parent directories are trusted, as with other Omarchy plugins.

Daily usage is retained for up to 90 days; application metadata, limits, and corrupt backups may remain longer. Wrapper window titles can become persisted application names. Limit notifications also disclose application usage to the session notification service, whose storage and retention are managed by Omarchy, not this plugin. Removal leaves the tracker history for you to delete explicitly.

See [SECURITY.md](SECURITY.md) for the review scope and verification commands. Periodic saves run every four seconds while usage changes; shutdown finishes a validated write already in progress rather than starting an unchecked final write.
