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
