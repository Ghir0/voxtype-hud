// Voxtype HUD — floating overlay for Omarchy Quattro.
//
// Watches `voxtype status --follow --format json` and reflects the dictation
// state in a small floating card near the bottom of the screen:
//
//   recording     -> pulsing dot + animated level bars
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
  // Path/name of the voxtype binary — only used if you disable the wrapper
  // below and call voxtype directly.
  property string voxtypeBin: "voxtype"

  // ── State: idle | recording | transcribing | done ────────────────────
  property string mode: "idle"
  property bool hudVisible: false

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
    if (next === "done")
      doneTimer.restart()
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
  readonly property int pad: Style.space(14)
  readonly property int gap: Style.space(12)
  readonly property int dotSize: Style.space(9)
  readonly property int barThickness: Style.space(4)
  readonly property int barsHeight: Style.space(20)
  readonly property color cardColor: Util.alpha(Color.background, 0.97)
  readonly property color textColor: Color.popups.text
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

  OverlayWindow {
    id: panel
    shown: root.hudVisible
    // Purely visual surface: never take keyboard focus, never eat clicks.
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voxtype-hud"
    mask: Region {}

    BorderSurface {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      radius: Style.cornerRadius
      color: root.cardColor
      borderSpec: root.borderSpec

      width: card.borderLeft + root.pad + row.implicitWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + row.implicitHeight + root.pad + card.borderBottom

      // Fade the whole card in and out.
      opacity: root.hudVisible ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
      }

      Row {
        id: row
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: card.borderTop + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        spacing: root.gap

        // ── Indicator ──────────────────────────────────────────────────
        Item {
          width: Math.max(root.dotSize, root.barsHeight)
          height: root.barsHeight
          anchors.verticalCenter: parent.verticalCenter

          // Recording: a pulsing dot.
          Rectangle {
            visible: root.mode === "recording"
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: Color.accent
            anchors.centerIn: parent
            SequentialAnimation on opacity {
              running: root.mode === "recording"
              loops: Animation.Infinite
              NumberAnimation { to: 0.25; duration: 520; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
            }
          }

          // Recording: five stylised level bars. Decorative, NOT a real input
          // meter — voxtype's status stream does not expose audio levels.
          Row {
            visible: root.mode === "recording"
            anchors.centerIn: parent
            spacing: root.barThickness
            Repeater {
              model: 5
              Rectangle {
                required property int index
                width: root.barThickness
                radius: width / 2
                color: root.textColor
                anchors.verticalCenter: parent.verticalCenter
                height: root.barsHeight * 0.25
                SequentialAnimation on height {
                  running: root.mode === "recording"
                  loops: Animation.Infinite
                  NumberAnimation {
                    to: root.barsHeight
                    duration: 300 + index * 70
                    easing.type: Easing.InOutSine
                  }
                  NumberAnimation {
                    to: root.barsHeight * 0.25
                    duration: 300 + (4 - index) * 70
                    easing.type: Easing.InOutSine
                  }
                }
              }
            }
          }

          // Transcribing: the processing animation — three dots rising in turn.
          Row {
            visible: root.mode === "transcribing"
            anchors.centerIn: parent
            spacing: root.barThickness * 2
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
            color: Color.accent
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
