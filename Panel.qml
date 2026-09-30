// Voxtype HUD — floating overlay for Omarchy Quattro.
//
// Watches `voxtype status --follow --format json` and reflects the dictation
// state in a small floating card near the bottom of the screen:
//
//   recording     -> live input-level waveform (real, not decorative)
//   transcribing  -> animated "processing" indicator (the point of this plugin)
//   stopped/idle  -> a brief "done" flash, then the HUD hides itself
//
// Strictly read-only: it mirrors voxtype's state and never drives it.
// Click-through (empty layer-shell input region), never takes keyboard focus.
//
// Styling follows the first-party `omarchy.osd` plugin: same popup theme
// tokens, same BorderSurface/border-inset maths, so any theme that styles the
// OSD styles this HUD too.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  // ── Configuration ────────────────────────────────────────────────────
  // How long the "done" confirmation stays on screen (ms).
  property int doneDuration: 700

  // Path to the level helper shipped next to this file. Resolved relative to
  // the plugin directory, so it keeps working wherever Omarchy installs it.
  readonly property string levelHelper: String(Qt.resolvedUrl("hud-levels.py")).replace("file://", "")

  // ── State: idle | recording | transcribing | done ────────────────────
  property string mode: "idle"
  property bool hudVisible: false

  // Rolling history of input levels (0..1), oldest first. Rendered as a
  // scrolling waveform, so the bars show real time-and-amplitude, like Yapper.
  property var levels: []

  function handleLine(line) {
    var text = String(line || "").trim()
    if (text === "")
      return
    var payload = null
    try {
      payload = JSON.parse(text)
    } catch (e) {
      payload = null
    }
    if (!payload)
      return
    // voxtype emits both `alt` (Waybar-style) and `class`. Omarchy's own
    // Dictation indicator reads `alt` first, so we mirror that.
    var state = String(payload["alt"] || payload["class"] || "").toLowerCase()
    if (state === "" && payload.tooltip)
      state = String(payload.tooltip).toLowerCase().replace("voxtype:", "").trim()
    applyState(state)
  }

  function applyState(state) {
    if (state === "recording")
      enter("recording")
    else if (state === "transcribing")
      enter("transcribing")
    else if (state === "stopped")
      enter("done")
    else if (root.mode !== "done")
      enter("idle") // "idle" or anything unknown
  }

  function enter(next) {
    root.mode = next
    root.hudVisible = (next !== "idle")
    if (next === "recording")
      root.resetLevels()
    if (next === "done")
      doneTimer.restart()
  }

  // ── Input level ──────────────────────────────────────────────────────
  function resetLevels() {
    var zeros = []
    for (var i = 0; i < root.barCount; i++)
      zeros.push(0)
    root.levels = zeros
  }

  function pushLevel(line) {
    var v = parseFloat(line)
    if (isNaN(v))
      return
    var next = root.levels.length === root.barCount ? root.levels.slice(1) : root.levels.slice()
    next.push(v)
    while (next.length < root.barCount)
      next.unshift(0)
    root.levels = next
  }

  // ── voxtype status stream ────────────────────────────────────────────
  // Reuse Omarchy's own wrapper. It handles a missing voxtype, and it wraps
  // `voxtype status --follow` in `setpriv --pdeathsig TERM` so the follower
  // dies with the shell instead of being orphaned when the shell restarts.
  Process {
    id: statusStream
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function (line) {
        root.handleLine(line)
      }
    }
    // If the stream dies (voxtype restarted, binary moved), bring it back.
    onRunningChanged: {
      if (!running)
        reviveTimer.restart()
    }
  }

  // Real microphone levels, only while recording — reading the mic when idle
  // would be both pointless and impolite. The low latency window keeps the
  // meter responsive instead of lagging a second behind the voice.
  Process {
    id: levelStream
    running: root.mode === "recording"
    command: ["bash", "-c", "parec --raw --format=s16le --rate=16000 --channels=1 --latency-msec=40 | python3 " + root.levelHelper]
    stdout: SplitParser {
      onRead: function (line) {
        root.pushLevel(line)
      }
    }
    onRunningChanged: {
      if (!running)
        root.resetLevels()
    }
  }

  Timer {
    id: reviveTimer
    interval: 2000
    onTriggered: {
      if (!statusStream.running)
        statusStream.running = true
    }
  }

  Timer {
    id: doneTimer
    interval: root.doneDuration
    onTriggered: root.enter("idle")
  }

  // ── Theme + metrics (mirrors omarchy.osd) ────────────────────────────
  // Asymmetric padding reads better in a pill: a touch more on the sides than
  // top/bottom. Everything derives from `padX`/`padY` so there is one place to
  // tune the card.
  readonly property int padX: Style.space(16)
  readonly property int padY: Style.space(11)
  readonly property int gap: Style.space(11)

  // Animation timings. Note: `Style` has no duration helper — the first-party
  // plugins use plain millisecond literals, so these stay tunable here.
  readonly property int fadeDuration: 160
  readonly property int meterSmoothing: 90

  readonly property int dotSize: Style.space(8)
  readonly property int dotSpacing: Style.space(6)

  readonly property int barCount: 9
  readonly property int barThickness: Style.space(3)
  readonly property int barSpacing: Style.space(3)
  readonly property int barsHeight: Style.space(18)
  readonly property int waveWidth: root.barCount * root.barThickness + (root.barCount - 1) * root.barSpacing
  // Fixed indicator width: the label must not shift when the state changes.
  readonly property int indicatorWidth: Math.max(root.waveWidth, 3 * root.dotSize + 2 * root.dotSpacing)

  readonly property color cardColor: Util.alpha(Color.background, 0.97)
  readonly property color textColor: Color.popups.text
  readonly property color meterColor: Color.accent
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property string labelText: {
    if (root.mode === "recording")
      return "Ascolto…"
    if (root.mode === "transcribing")
      return "Trascrivo…"
    if (root.mode === "done")
      return "Fatto"
    return ""
  }

  // PanelWindow (Quickshell built-in) instead of the shell's OverlayWindow:
  // third-party plugins get a limited interface, and `OverlayWindow` is not
  // exposed to them ("OverlayWindow is not a type"). This mirrors the pattern
  // used by the first-party notifications service.
  PanelWindow {
    id: panel
    visible: root.hudVisible
    anchors { bottom: true; left: true; right: true }
    implicitHeight: card.height + Style.space(67)
    color: "transparent"
    WlrLayershell.namespace: "voxtype-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Keep the input region to the card only, so the rest of the strip is
    // click-through.
    mask: Region { item: card }

    BorderSurface {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      radius: Style.cornerRadius
      color: root.cardColor
      borderSpec: root.borderSpec

      width: card.borderLeft + root.padX + row.implicitWidth + root.padX + card.borderRight
      height: card.borderTop + root.padY + row.implicitHeight + root.padY + card.borderBottom

      // Fade the whole card in and out.
      opacity: root.hudVisible ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic }
      }

      Row {
        id: row
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: card.borderTop + root.padY
        anchors.leftMargin: card.borderLeft + root.padX
        spacing: root.gap

        // ── Indicator (fixed width, so the label never jitters) ────────
        Item {
          width: root.indicatorWidth
          height: Math.max(root.barsHeight, root.dotSize)

          // Recording: live input-level waveform. Each bar is one measurement
          // from ~40 ms ago, so the whole strip scrolls like a real meter.
          Row {
            visible: root.mode === "recording"
            anchors.centerIn: parent
            spacing: root.barSpacing
            Repeater {
              model: root.barCount
              Rectangle {
                required property int index
                width: root.barThickness
                radius: width / 2
                color: root.meterColor
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(root.barThickness, root.barsHeight * (root.levels[index] || 0))
                Behavior on height {
                  NumberAnimation { duration: root.meterSmoothing; easing.type: Easing.OutQuad }
                }
              }
            }
          }

          // Transcribing: the processing animation — three dots rising in turn.
          Row {
            visible: root.mode === "transcribing"
            anchors.centerIn: parent
            spacing: root.dotSpacing
            Repeater {
              model: 3
              Rectangle {
                required property int index
                width: root.dotSize
                height: root.dotSize
                radius: width / 2
                color: root.textColor
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on y {
                  running: root.mode === "transcribing"
                  loops: Animation.Infinite
                  PauseAnimation { duration: index * 140 }
                  NumberAnimation { to: -root.dotSize * 0.9; duration: 260; easing.type: Easing.OutCubic }
                  NumberAnimation { to: 0; duration: 260; easing.type: Easing.InCubic }
                  PauseAnimation { duration: (2 - index) * 140 }
                }
                SequentialAnimation on opacity {
                  running: root.mode === "transcribing"
                  loops: Animation.Infinite
                  PauseAnimation { duration: index * 140 }
                  NumberAnimation { to: 1.0; duration: 260 }
                  NumberAnimation { to: 0.35; duration: 260 }
                  PauseAnimation { duration: (2 - index) * 140 }
                }
              }
            }
          }

          // Done: a settled accent dot.
          Rectangle {
            visible: root.mode === "done"
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: root.meterColor
            anchors.centerIn: parent
          }
        }

        // ── Label ──────────────────────────────────────────────────────
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.labelText
          color: root.textColor
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
      }
    }
  }
}
