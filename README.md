# Voxtype HUD

A floating heads-up display for [Voxtype](https://voxtype.io) dictation on
[Omarchy](https://omarchy.org) Quattro.

It watches Voxtype's status stream and shows a small theme-aware card near the
bottom of the screen:

| Voxtype state  | What you see                                            |
| -------------- | ------------------------------------------------------- |
| `recording`    | a pulsing dot and five animated level bars              |
| `transcribing` | **an animated processing indicator** (three rising dots) |
| `stopped`      | a brief "Fatto" flash, then the card fades out           |

It is read-only: it mirrors Voxtype's state and never drives it.

## Requirements

- Omarchy Quattro (the `omarchy-shell` Quickshell plugin host)
- Voxtype installed and running, with its status file enabled
  (`state_file = "auto"`, the default)

## Install

```sh
omarchy plugin add https://github.com/Ghir0/voxtype-hud.git --enable
```

Then adjust your Hyprland bindings so Voxtype is driven through the compositor
(recommended by Voxtype itself):

```
bind  = SUPER, V, exec, voxtype record start
bindr = SUPER, V, exec, voxtype record stop
```

## Verify it is loaded

```sh
omarchy plugin list --json | jq '.[] | select(.id == "io.github.ghir0.voxtype-hud")'
```

If the HUD does not appear, check the shell log:

```sh
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

## Configure

Edit `Overlay.qml` and change the properties at the top:

| Property                | Default    | Meaning                                             |
| ----------------------- | ---------- | --------------------------------------------------- |
| `voxtypeBin`            | `voxtype`  | Path to the binary (use an absolute path if needed) |
| `doneDuration`          | `700`      | How long the "Fatto" confirmation stays (ms)        |
| `minProcessingDuration` | `500`      | Minimum time the processing animation stays up (ms) |

The card's position is `anchors.bottomMargin: Style.space(67)` inside
`Overlay.qml`.

## Notes and limitations

- Third-party plugins run against a **limited interface**: the shell's
  `OverlayWindow` type is *not* available to them (`OverlayWindow is not a
  type`). This plugin uses Quickshell's own `PanelWindow` instead — the same
  pattern as the first-party notifications service.
- The plugin declares `kinds: ["panel"]` + `keepLoaded: true`, which is what
  makes the shell mount it **at shell start**. An `overlay` kind is only
  loaded on first summon, so a status watcher living inside one would never
  run. After adding the plugin, restart the shell (`omarchy-restart-shell`).
- The level bars during recording are a **decorative animation**, not a real
  input meter: Voxtype's `status` stream does not expose audio levels. (The
  stock GTK4 OSD does draw a real waveform.)
- The HUD renders on a single panel surface. Multi-monitor placement is not
  handled yet.
- Built against the Omarchy wrapper `omarchy-voxtype-status` and the
  documented `voxtype status --follow --format json` contract
  (`{"alt": ..., "class": "idle|recording|transcribing|stopped", ...}`).

## Remove

```sh
omarchy plugin remove io.github.ghir0.voxtype-hud
```

## License

MIT — see [LICENSE](LICENSE).
