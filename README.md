# Voxtype Bubble

A draggable, clickable dictation control for [Voxtype](https://voxtype.io) on
[Omarchy](https://omarchy.org) Quattro — a Whisper-Flow-style bubble.

It both mirrors and drives Voxtype. Click the bubble to start recording, use
the on-bubble button to stop, and drag it anywhere on screen — it snaps to the
nearest edge or corner and remembers where it docked. States map to Voxtype's
status stream:

| Voxtype state  | What you see                                             |
| -------------- | -------------------------------------------------------- |
| `idle`         | a compact sprite-avatar bubble; click it to start recording |
| `recording`    | a **live input-level waveform** + **stop** and **cancel** buttons |
| `transcribing` | **an animated processing indicator** (three rising dots)  |
| `stopped`      | a brief confirmation flash, then back to idle             |

Unlike a pure HUD it is bidirectional: the bubble runs
`voxtype record start/stop`. A small satellite button stays on the screen-edge
side of the bubble and toggles Voxtype's built-in translation mode. When enabled, Voxtype translates speech into English; the
source language remains whatever is configured in Voxtype. The sprite switches
to a separate animation row and stays visible beside the recording controls.
The Hyprland push-to-talk hotkey still works alongside it.

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

The activator is a Hyprland binding, not Voxtype's own evdev listener. Disable
that listener so a bare `RIGHTCTRL` (often used as a plain modifier) never
starts a recording, and drive Voxtype through the compositor instead —
recommended by Voxtype itself:

```toml
# ~/.config/voxtype/config.toml
[hotkey]
enabled = false
```

```lua
-- ~/.config/hypr/bindings.lua
-- Push-to-talk on CTRL + MENU. Hyprland's CTRL modifier covers either Ctrl
-- key; it cannot target only the right one.
o.bind("CTRL + MENU", "Start dictation (push-to-talk)", "voxtype record start")
o.bind("CTRL + MENU", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
```

Restart the daemon after editing the config: `systemctl --user restart voxtype`.
Prefer a tap-to-toggle over hold-to-talk? Swap both dispatchers for
`voxtype record toggle` on a single binding.

## Controls

- **Click the bubble** while idle to start recording.
- **Click the round stop button** (or the bubble again) while recording to
  stop and transcribe.
- **Click the cancel button** while recording to discard it without
  transcribing (`voxtype record cancel`).
- **Click the small `EN` satellite** while idle to toggle translation. It uses
  Voxtype's `whisper.translate` setting and restarts the Voxtype user service
  when changing modes; wait for the satellite to finish loading before starting
  a recording. The button initially reflects Voxtype's current setting
  (translation is off in Voxtype's default config). With translation on, the
  animated sprite uses a different sheet row and remains beside the controls.
  The sprite is mirrored on the right half of the screen so it faces inward.
- **Drag the bubble** anywhere on screen. On release it **snaps to the nearest
  screen edge or corner**. The dock is saved to
  `~/.local/state/voxtype-hud/position` and restored at the next shell start
  (default: bottom-right corner).
- When idle, the bubble **slides mostly off its docked edge(s)** after a short
  pause. Only a small **accent dot** stays on screen at the docked spot;
  **approaching that dot slides the bubble back out**; while recording or
  transcribing it always stays fully visible.
- The `CTRL + MENU` push-to-talk hotkey keeps working alongside the bubble.

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

The layer surface should always be present (it hosts the bubble):

```sh
hyprctl layers | grep voxtype-bubble
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

| Property              | Default | Meaning                                          |
| --------------------- | ------- | ------------------------------------------------ |
| `snapDistance`        | `180`   | How close to an edge before docking (px)         |
| `doneDuration`        | `700`   | How long the confirmation flash stays (ms)       |
| `hideDelay`           | `1600`  | Pause before the idle bubble hides (ms)          |
| `dragThreshold`       | `4`     | Pixels of movement before a click becomes a drag |
| `cornerInset`         | `12`    | Gap between the bubble and the docked edge       |
| `peek`                | `16`    | Pixels left visible when hidden                  |
| `spriteSize`          | `32`    | Drawn avatar size (source frame is 32x32)        |
| `spriteFrameDuration` | `130`   | Avatar frame duration (ms)                       |
| `idleRow`             | `0`     | Sprite-sheet row used when translation is off    |
| `translationOrbGap`   | `5`     | Space between the EN satellite and main bubble   |
| `padX`                | `14`    | Pill padding, horizontal                         |
| `gap`                 | `12`    | Space between indicator and stop button          |
| `barCount`            | `9`     | Waveform bars (≈40 ms of audio each)             |
| `bubbleHeight`        | `48`    | Bubble diameter / pill height                    |
| `stopSize`            | `28`    | Stop / cancel button diameter                    |
| `buttonGap`           | `8`     | Space between stop and cancel                    |
| `peekDotSize`         | `10`    | Accent dot diameter when hidden                  |
| `fadeDuration`        | `160`   | Bubble width/fade animation (ms)                 |
| `slideDuration`       | `280`   | Dock / hide slide animation (ms)                 |
| `meterSmoothing`      | `90`    | Waveform bar easing (ms)                         |

### Avatar sprite sheet

`alien-slime.png` is a **7x3 grid of 32x32 frames** — one animation per row.
The bundled sheet's first row is the idle bounce. To use a different sprite,
replace the file (same layout) or point `spriteSheet` at another image and
adjust `spriteFrameWidth` / `spriteFrameHeight` / `spriteFrameCount` /
`idleRow`. Frames are drawn with nearest-neighbour scaling (`smooth: false`),
so pixel art stays crisp.

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
- Multi-monitor placement is not handled yet — the bubble renders on one surface.
- The bubble runs `voxtype record start/stop`; it needs no extra privileges
  beyond what the compositor binding already uses.
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
