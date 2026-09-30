# Voxtype HUD

A floating heads-up display for [Voxtype](https://voxtype.io) dictation on
[Omarchy](https://omarchy.org) Quattro.

It watches Voxtype's status stream and shows a small theme-aware card near the
bottom of the screen:

| Voxtype state  | What you see                                             |
| -------------- | -------------------------------------------------------- |
| `recording`    | a **live input-level waveform** driven by your microphone |
| `transcribing` | **an animated processing indicator** (three rising dots)  |
| `stopped`      | a brief "Fatto" flash, then the card fades out            |

It is read-only: it mirrors Voxtype's state and never drives it.

## Requirements

- Omarchy Quattro (the `omarchy-shell` Quickshell plugin host)
- Voxtype installed and running, with its status file enabled
  (`state_file = "auto"`, the default)
- `parec` (PipeWire/PulseAudio) and `python3` for the level meter — both ship
  with Omarchy. Without them the waveform stays flat; everything else works.

## Install

```sh
omarchy plugin add https://github.com/Ghir0/voxtype-hud.git --enable
omarchy-restart-shell
```

The shell restart is required: a `keepLoaded` panel is mounted at shell start.

Then adjust your Hyprland bindings so Voxtype is driven through the compositor
(recommended by Voxtype itself):

```
bind  = SUPER, V, exec, voxtype record start
bindr = SUPER, V, exec, voxtype record stop
```

If you already had the plugin installed, remove the old directory first so the
clone starts clean:

```sh
rm -rf ~/.config/omarchy/plugins/io.github.ghir0.voxtype-hud
omarchy plugin add https://github.com/Ghir0/voxtype-hud.git --enable
omarchy-restart-shell
```

## Verify it is loaded

```sh
omarchy plugin list --json | jq '.[] | select(.id == "io.github.ghir0.voxtype-hud")'
```

While recording, the layer surface should be present:

```sh
hyprctl layers | grep voxtype-hud
```

If the HUD does not appear, read the **live** shell log. Several Quickshell
apps may be running, so select by PID — `qs log -p <path>` can pick a stale
instance:

```sh
PID=$(ps -eo pid,args -u "$USER" | awk '/omarchy\/shell/ && !/awk/ {print $1; exit}')
qs log --pid "$PID" --tail 100
```

## Configure

All knobs are `readonly property` values at the top of `Panel.qml`:

| Property         | Default     | Meaning                                      |
| ---------------- | ----------- | -------------------------------------------- |
| `doneDuration`   | `700`       | How long the "Fatto" confirmation stays (ms) |
| `padX` / `padY`  | `16` / `11` | Card padding, horizontal / vertical          |
| `gap`            | `11`        | Space between indicator and label            |
| `barCount`       | `9`         | Waveform bars (≈40 ms of audio each)         |
| `fadeDuration`   | `160`       | Card fade in/out (ms)                        |
| `meterSmoothing` | `90`        | Waveform bar easing (ms)                     |

The card sits at `anchors.bottomMargin: Style.space(67)`.

### Tuning the level meter

`hud-levels.py` maps microphone RMS to 0..1 over a −60..0 dBFS window:

| Constant     | Default | Meaning                                       |
| ------------ | ------- | --------------------------------------------- |
| `DB_FLOOR`   | `-60.0` | dBFS mapped to 0                              |
| `GAMMA`      | `0.8`   | <1 lifts quiet speech (livelier bars), 1 flat  |
| `ATTACK`     | `0.60`  | How fast the level rises                      |
| `RELEASE`    | `0.14`  | How fast it falls back                        |

## Notes and limitations

- Third-party plugins run against a **limited interface**: the shell's
  `OverlayWindow` type is *not* available to them (`OverlayWindow is not a
  type`). This plugin uses Quickshell's own `PanelWindow` instead — the same
  pattern as the first-party notifications service.
- The plugin declares `kinds: ["panel"]` + `keepLoaded: true`, which is what
  makes the shell mount it **at shell start**. An `overlay` kind is only
  loaded on first summon, so a status watcher living inside one would never
  run.
- The waveform is a real meter, but it reads the **default** source: if Voxtype
  is configured to record from a different device, the meter shows the default
  one instead. Set `parec --device=<source>` in `Panel.qml` to pin it.
- It reads the microphone only while Voxtype is recording.
- Multi-monitor placement is not handled yet — the HUD renders on one surface.
- Built against the Omarchy wrapper `omarchy-voxtype-status` and the documented
  `voxtype status --follow --format json` contract
  (`{"alt": ..., "class": "idle|recording|transcribing|stopped", ...}`).
  Omarchy's own Dictation indicator reads `alt` first, and so does this plugin.

## Development

`test-levels.py` feeds synthetic PCM at three amplitudes through
`hud-levels.py` — a way to check the meter mapping without opening a
microphone:

```sh
python3 test-levels.py
# silence ~0.03 / quiet speech ~0.57 / loud ~0.81
```

## Remove

```sh
omarchy plugin remove io.github.ghir0.voxtype-hud
```

## License

MIT — see [LICENSE](LICENSE).
