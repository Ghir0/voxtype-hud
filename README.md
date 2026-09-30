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

- The level bars during recording are a **decorative animation**, not a real
  input meter: Voxtype's `status` stream does not expose audio levels.
- The HUD renders on a single overlay surface. Multi-monitor placement is not
  handled yet.
- Developed against the documented Voxtype `status --follow --format json`
  contract (`{"text": ..., "tooltip": ..., "class": "idle|recording|transcribing|stopped"}`).

## Remove

```sh
omarchy plugin remove io.github.ghir0.voxtype-hud
```

## License

MIT — see [LICENSE](LICENSE).
