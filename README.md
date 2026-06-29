# ood-xfce-session-timer

A walltime countdown for [Open OnDemand](https://openondemand.org/) interactive
desktop sessions. It places a live "time remaining" indicator in the Xfce panel
and fires desktop notifications as the session's Slurm walltime runs out, so
users can save their work before the job is killed.

Built for and tested on Rocky Linux 9 / Slurm / OnDemand `bc_desktop` / Xfce,
but it should adapt to any RHEL-family OOD deployment that uses the Xfce
interactive desktop.

## What it does

- Adds a color-coded countdown (`H:MM:SS`) to the Xfce panel: green normally,
  amber under 30 minutes, bold red under 5 minutes.
- Shows the absolute session end time in the panel item's tooltip.
- Sends `notify-send` popups at configurable thresholds (default: 30, 10, 5,
  and 1 minute remaining).
- Reflects whatever walltime the user actually requested because it reads the job's real end time from the
  scheduler.

The countdown updates every 30 seconds by default (configurable). It is
self-contained per session and does nothing on a desktop that isn't an OOD
interactive job.

## How it works

There are three small pieces:

1. **`ood-timeleft-genmon.sh`** — the producer script. The Xfce
   [GenMon](https://docs.xfce.org/panel-plugins/xfce4-genmon-plugin/start)
   plugin runs it on an interval and renders its output. It resolves the job's
   `EndTime` from Slurm **once**, caches it, and from then on computes the
   remaining time locally with simple date math.

2. **`ood-add-timer.sh`** — the injector. It runs once per session from
   `/etc/xdg/autostart`, adds a GenMon instance to the panel pointed at the
   producer, and launches the background warning loop. It writes both the
   GenMon `rc` file (genmon < 4.2.0) and the equivalent xfconf properties
   (genmon ≥ 4.2.0), so it works regardless of the plugin version on your image.
   It is idempotent across session reconnects.

3. **`ood-session-timer.desktop`** — the autostart entry that launches the
   injector inside the Xfce session.

### Why autostart instead of a default panel layout

A system `xfce4-panel.xml` default only reaches users who have **no** panel
config yet; anyone who has already opened a desktop has a `~/.config` panel
layout that shadows it. Because HPC users have persistent home directories, the
autostart injector is the reliable way to reach every user on every session. It
runs inside an established session (so the bus and `xfconfd` are up), the panel
live-adds the plugin when its id appears, and the guard prevents double-adds on
reconnect.

### Scheduler load

The producer contacts `slurmctld` exactly once per session (first render), then
reads a cached epoch. A large number of concurrent desktops will not add meaningful
controller load.

## Requirements

- Rocky Linux 9 / RHEL 9 family (or compatible) **compute nodes** — these run
  the desktop, so everything installs there, not on the OOD portal node.
- Open OnDemand with an Xfce-based `bc_desktop` interactive app.
- Slurm.
- Packages (EPEL provides GenMon):

  ```bash
  sudo dnf install -y xfce4-genmon-plugin libnotify xfce4-notifyd
  ```

  `xfce4-notifyd` is the notification daemon the warnings rely on; pin it so
  popups don't silently fail on a minimal image.

## Installation

### Quick install

On the compute-node image, run the bundled installer as root:

```bash
sudo ./install.sh
```

It performs all of the steps below: installs the packages, places the scripts
in `/opt/ood-session-timer/bin/`, and installs the autostart entry. Useful
options:

- `--bindir DIR` — install the scripts somewhere other than the default; the
  injector's `PRODUCER` path and the `.desktop` `Exec=` line are rewritten to
  match.
- `--skip-packages` — install files only, if your image pipeline manages RPMs
  separately.
- `--uninstall` — remove the installed files.

You still need to confirm the job environment reaches the session (step 4) and
verify the panel id (step 5). The remaining steps document what the installer
does, for manual installs or troubleshooting.

### Longer install

All steps target the **compute-node image**.

1. **Install the scripts.**

   ```bash
   sudo install -Dm755 bin/ood-timeleft-genmon.sh /opt/ood-session-timer/bin/ood-timeleft-genmon.sh
   sudo install -Dm755 bin/ood-add-timer.sh       /opt/ood-session-timer/bin/ood-add-timer.sh
   ```

   If you install elsewhere, update the `PRODUCER` variable in
   `ood-add-timer.sh` and the `Exec=` line in the `.desktop` file to match.

2. **Install the autostart entry.**

   ```bash
   sudo install -Dm644 autostart/ood-session-timer.desktop /etc/xdg/autostart/ood-session-timer.desktop
   ```

3. **Install the packages** (see Requirements).

4. **Confirm the job environment reaches the desktop.** In the standard OSC
   `bc_desktop` flow the window manager inherits the job environment, so
   `$SLURM_JOB_ID` is visible. Verify once: launch a desktop, open a terminal
   in it, and run `echo $SLURM_JOB_ID`. If it's populated, you're done.

   If it's empty (some xstartup wrappers launch the WM via a clean login
   shell), add one line to your `bc_desktop` app's `template/script.sh.erb`
   before the desktop launches, so the scripts pick the id up via their file
   fallback:

   ```bash
   echo "$SLURM_JOB_ID" > "$HOME/.ood-session-job"
   ```

   See `examples/bc_desktop-script.sh.erb.snippet`.

5. **Verify the panel id.** Defaults usually put everything on `panel-1`.
   Confirm on a running session and adjust the `PANEL` variable if needed:

   ```bash
   xfconf-query -c xfce4-panel -p /panels
   ```

## Configuration

Edit the variables at the top of `ood-add-timer.sh`:

| Variable        | Default                                              | Purpose                                         |
|-----------------|------------------------------------------------------|-------------------------------------------------|
| `PLUGIN_ID`     | `1000`                                               | GenMon panel plugin id (high, avoids collisions)|
| `PANEL`         | `panel-1`                                            | Which panel to add the item to                  |
| `PRODUCER`      | `/opt/ood-session-timer/bin/ood-timeleft-genmon.sh`  | Path to the producer script                     |
| `UPDATE_MS`     | `30000`                                              | Refresh interval in milliseconds                |
| `FONT`          | `Monospace 10`                                       | Panel item font                                 |
| `WARN_AT`       | `(1800 600 300 60)`                                  | Notification thresholds, in seconds remaining   |
| `ENABLE_NOTIFY` | `1`                                                  | Set `0` to disable popups                       |

To change the refresh interval, set `UPDATE_MS` (and the matching `rc` value is
written automatically). A few seconds is the practical floor; a per-second
ticking panel clock is more distracting than useful. Note the panel can lag
reality by up to one interval, which is why the to-the-second notifications
exist for the final stretch.

### Optional: themed icon

The default display is color-coded text with no icon, which avoids any font
dependency (an emoji glyph renders as a missing-glyph box on a minimal image).
If you want an icon, GenMon's `<icon>` tag pulls from the active icon theme and
sizes itself to the panel. Find one that exists in your image's theme:

```bash
find /usr/share/icons -regextype posix-extended \
  -iregex '.*/(alarm|appointment-soon|.*clock.*)[^/]*\.(svg|png)$' 2>/dev/null | head
```

Then add an `<icon>NAME</icon>` line to the producer's output (the icon follows
the theme's foreground color; the urgency color stays on the text).

## Testing

Launch a short desktop session — request ~30 minutes so you can watch it cross
the thresholds. You should see the countdown in the panel turn amber under 30
minutes and red/bold under 5, with notifications firing at each threshold and a
tooltip showing the absolute end time.

## Troubleshooting

- **Missing-glyph box instead of an icon** — your image has no font with that
  glyph. Use the default text-only display, or the themed-icon option above.
- **Plugin doesn't appear until a manual panel restart** — change the `.desktop`
  `Exec=` line to append `--restart`; on a single-panel OOD desktop that's a
  sub-second flicker.
- **Item sits flush against the next panel button** — the producer adds trailing
  spaces inside its `<span>`; add more, or switch a space to `\u00A0` if the
  panel trims it. On genmon ≥ 4.2.0 you can instead use a `<css>` margin.
- **Countdown shows `--:--`** — the job's `EndTime` wasn't resolvable yet;
  it self-corrects on the next tick. If it persists, confirm `$SLURM_JOB_ID` /
  `~/.ood-session-job` is reaching the session (install step 4).

## Uninstall

Remove the autostart entry from the image; the scripts under `/opt` become
inert:

```bash
sudo rm /etc/xdg/autostart/ood-session-timer.desktop
```

Nothing here touches user home directories beyond a per-session GenMon `rc`
file and a cache file in `$TMPDIR`.

## Contributing

Issues and pull requests welcome — especially adaptations for other desktop
environments (MATE, GNOME) or schedulers.

## License

[MIT](LICENSE).
