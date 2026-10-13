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

Per-widget settings live on the bar entry: show the program name, warn percentage, and idle cutoff. Usage and limits are stored locally in `~/.local/share/omatracker/data.json`.

## Remove

```sh
omarchy plugin remove nate.omatracker
```

Removal disables the plugin and deletes this checkout. It does not delete `~/.local/share/omatracker/`. Remove that directory too if you want the history gone.

## License

MIT. See [LICENSE](LICENSE).

## Dependencies

No extra packages, network access, install hooks, or privileges. The only command it runs is `omarchy-notification-send`, which ships with Omarchy, and only when a daily limit is reached. Everything else uses the shell already running: Quickshell, the theme tokens, and the focused window.

## Ownership

The code in this repository is original. There are no preview images or other third-party assets.

## Configuration

The plugin does not write `shell.json`, Hyprland config, or any other app's files. Enabling it through `omarchy plugin add` is what places the bar widget, and that step asks first unless you pass `--enable`. The only file it creates is its own data file, `~/.local/share/omatracker/data.json`.

## Security

A marketplace listing is not a security review. This plugin runs unsandboxed inside `omarchy-shell`, with the same permissions as your user. Read it before you enable it.
