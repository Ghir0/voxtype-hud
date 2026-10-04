// Voxtype Bubble — a draggable, clickable dictation control for Omarchy Quattro.
//
// This is the interactive sibling of a pure status HUD: the bubble drives
// voxtype as well as mirroring it.
//
//   idle         -> compact avatar bubble, docked to an edge or corner
//   recording    -> live input-level waveform + a stop button
//   transcribing -> animated processing dots
//   done         -> a brief confirmation flash, then back to idle
//
// Interaction
//   - click the bubble to start recording; click again (or the stop button)
//     to stop and transcribe
//   - drag it anywhere; on release it snaps to the nearest screen edge or
//     corner
//   - when idle it slides mostly off the docked edge(s), leaving a small peek;
//     approaching the peek slides it back out
//
// The dock is restored from ~/.local/state/voxtype-hud/position on the next
// shell start.
//
// Styling follows the first-party `omarchy.osd` plugin: same popup theme
// tokens, same BorderSurface/border-inset maths, so any theme that styles the
// OSD styles this bubble too.

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
  // Pointer movement below this many pixels is treated as a click, not a drag.
  readonly property int dragThreshold: 4
  // Pause after the pointer leaves, before the idle bubble hides (ms).
  property int hideDelay: 1600
  // How close (px) to an edge the bubble must be to dock to it. The nearest
  // edge always wins; if the bubble lands far from every edge it still docks
  // to the closest one, so it never floats mid-screen.
  property int snapDistance: 180

  // ── Avatar sprite sheet ──────────────────────────────────────────────
  // A grid of frames, one animation per row. The bundled sheet is 7x3 frames
  // of 32x32. `idleRow` picks which row animates while idle.
  readonly property url spriteSheet: Qt.resolvedUrl("alien-slime.png")
  readonly property int spriteFrameWidth: 32
  readonly property int spriteFrameHeight: 32
  readonly property int spriteFrameCount: 7
  readonly property int spriteFrameDuration: 130
  readonly property int idleRow: 0
  readonly property int spriteSize: Style.space(32)

  // Current frame of the idle animation.
  property int avatarFrame: 0

  // Path to the level helper shipped next to this file. Resolved relative to
  // the plugin directory, so it keeps working wherever Omarchy installs it.
  readonly property string levelHelper: String(Qt.resolvedUrl("hud-levels.py")).replace("file://", "")
  readonly property string translationHelper: String(Qt.resolvedUrl("hud-translation.py")).replace("file://", "")

  // ── State: idle | recording | transcribing | done ────────────────────
  property string mode: "idle"
  property var levels: []
  property bool translationEnabled: false
  property bool translationLoading: true
  property bool translationBusy: false
  property string translationError: ""

  function applyTranslationResult(output) {
    try {
      var result = JSON.parse(String(output || "{}"))
      root.translationEnabled = result.enabled === true
      root.translationError = ""
    } catch (e) {
      root.translationError = "Invalid Voxtype translation setting"
    }
    root.translationLoading = false
  }

  // ── Docking ──────────────────────────────────────────────────────────
  // Each axis can be docked (`dockX`/`dockY`) to the left/right and top/bottom
  // edge, so the bubble can sit in a corner (both docked) or against a single
  // edge (one docked). A docked axis is placed `marginX`/`marginY` from its
  // edge; a negative margin slides it off-screen, leaving `peek` pixels
  // visible. An undocked axis keeps its free coordinate in the margin.
  property bool dockX: true
  property bool dockY: true
  property bool anchorRight: true
  property bool anchorBottom: true
  property real marginX: Style.space(12)
  property real marginY: Style.space(12)
  readonly property int cornerInset: Style.space(12)
  readonly property int peek: Style.space(16)

  // Top-left position, derived from the dock + margins by `applyMargins()`.
  property real posX: -1000
  property real posY: -1000

  property bool placed: false
  property bool positionRestored: false
  property bool dragging: false
  property bool hovered: false
  // True while the bubble has slid off its dock and only the accent dot shows.
  property bool hidden: false

  readonly property bool canHide: mode === "idle"

  // Screen position of that dot. A docked axis puts its centre exactly on the
  // screen edge, so half of the dot hangs outside; a free axis keeps it centred
  // on the visible peek.
  readonly property real dotCenterX: root.dockX
    ? (root.anchorRight ? panel.width : 0)
    : (root.posX + root.bubbleWidth / 2)
  readonly property real dotCenterY: root.dockY
    ? (root.anchorBottom ? panel.height : 0)
    : (root.posY + root.bubbleHeight / 2)

  // ── Actions: the bubble drives voxtype ───────────────────────────────
  Process { id: startProc; command: ["voxtype", "record", "start"] }
  Process { id: stopProc; command: ["voxtype", "record", "stop"] }
  Process { id: cancelProc; command: ["voxtype", "record", "cancel"] }

  Process {
    id: readTranslationProc
    command: ["python3", root.translationHelper, "get"]
    running: true
    stdout: StdioCollector { id: readTranslationStdout; waitForEnd: true }
    stderr: StdioCollector { id: readTranslationStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0)
        root.applyTranslationResult(readTranslationStdout.text)
      else {
        root.translationLoading = false
        root.translationError = String(readTranslationStderr.text || "Cannot read Voxtype translation setting").trim()
      }
    }
  }

  Process {
    id: writeTranslationProc
    stdout: StdioCollector { id: writeTranslationStdout; waitForEnd: true }
    stderr: StdioCollector { id: writeTranslationStderr; waitForEnd: true }
    onExited: function (exitCode) {
      root.translationBusy = false
      if (exitCode === 0)
        root.applyTranslationResult(writeTranslationStdout.text)
      else
        root.translationError = String(writeTranslationStderr.text || "Could not update Voxtype translation").trim()
    }
  }

  function toggleTranslation() {
    if (root.translationLoading || root.translationBusy
        || (root.mode !== "idle" && root.mode !== "done"))
      return
    if (root.translationError !== "") {
      root.translationError = ""
      root.translationLoading = true
      readTranslationProc.running = true
      return
    }
    root.translationBusy = true
    writeTranslationProc.command = ["python3", root.translationHelper, "set", root.translationEnabled ? "false" : "true"]
    writeTranslationProc.running = true
  }

  function startRecording() {
    startProc.startDetached()
  }

  function stopRecording() {
    stopProc.startDetached()
  }

  function cancelRecording() {
    cancelProc.startDetached()
  }

  function onBubbleClick() {
    if (root.translationBusy || root.translationLoading)
      return
    if (root.mode === "recording")
      root.stopRecording()
    else if (root.mode === "idle" || root.mode === "done")
      root.startRecording()
    // While transcribing, a click is ignored on purpose.
  }

  // ── Position helpers ─────────────────────────────────────────────────
  function applyMargins() {
    if (panel.width <= 0 || panel.height <= 0)
      return
    root.posX = root.dockX
      ? (root.anchorRight ? panel.width - root.marginX - root.bubbleWidth : root.marginX)
      : root.marginX
    root.posY = root.dockY
      ? (root.anchorBottom ? panel.height - root.marginY - root.bubbleHeight : root.marginY)
      : root.marginY
  }

  // Keep the dock + margins in sync while dragging, so a later re-layout
  // (mode change) grows from the correct edge.
  function updateAnchorFromPosition() {
    if (panel.width <= 0 || panel.height <= 0)
      return
    root.anchorRight = (root.posX + root.bubbleWidth / 2) > panel.width / 2
    root.anchorBottom = (root.posY + root.bubbleHeight / 2) > panel.height / 2
    root.marginX = root.dockX
      ? (root.anchorRight ? panel.width - root.posX - root.bubbleWidth : root.posX)
      : root.posX
    root.marginY = root.dockY
      ? (root.anchorBottom ? panel.height - root.posY - root.bubbleHeight : root.posY)
      : root.posY
  }

  function reveal() {
    if (root.dragging)
      return
    hideTimer.stop()
    root.hidden = false
    if (root.dockX)
      root.marginX = root.cornerInset
    if (root.dockY)
      root.marginY = root.cornerInset
    root.applyMargins()
  }

  function hide() {
    if (root.dragging || !root.canHide)
      return
    root.hidden = true
    if (root.dockX)
      root.marginX = -(root.bubbleWidth - root.peek)
    if (root.dockY)
      root.marginY = -(root.bubbleHeight - root.peek)
    root.applyMargins()
  }

  // Dock to the nearest edge on each axis, then reveal. At least one axis is
  // always docked, so the bubble never floats mid-screen.
  function snapToNearest() {
    if (panel.width <= 0 || panel.height <= 0)
      return
    var cx = root.posX + root.bubbleWidth / 2
    var cy = root.posY + root.bubbleHeight / 2
    var dLeft = cx
    var dRight = panel.width - cx
    var dTop = cy
    var dBottom = panel.height - cy
    root.anchorRight = dRight < dLeft
    root.anchorBottom = dBottom < dTop
    root.dockX = Math.min(dLeft, dRight) < root.snapDistance
    root.dockY = Math.min(dTop, dBottom) < root.snapDistance
    if (!root.dockX && !root.dockY) {
      if (Math.min(dLeft, dRight) <= Math.min(dTop, dBottom))
        root.dockX = true
      else
        root.dockY = true
    }
    root.reveal()
  }

  function place() {
    if (root.placed || panel.width <= 0 || panel.height <= 0)
      return
    root.placed = true
    if (root.positionRestored) {
      root.snapToNearest()
    } else {
      root.dockX = true
      root.dockY = true
      root.anchorRight = true
      root.anchorBottom = true
      root.reveal()
    }
    if (root.canHide && !root.hovered)
      hideTimer.restart()
  }

  // ── Position persistence ─────────────────────────────────────────────
  Process {
    id: readPosition
    command: ["bash", "-c", "cat \"$HOME/.local/state/voxtype-hud/position\" 2>/dev/null"]
    running: true
    stdout: SplitParser {
      onRead: function (line) {
        var parts = String(line).trim().split(/\s+/)
        if (parts.length < 2)
          return
        var x = parseFloat(parts[0])
        var y = parseFloat(parts[1])
        if (isNaN(x) || isNaN(y))
          return
        root.posX = x
        root.posY = y
        root.positionRestored = true
        // The panel may already be placed (its size arrived before the read):
        // re-snap instead of bailing out of `place()`.
        if (root.placed)
          root.snapToNearest()
        else
          root.place()
      }
    }
  }

  Process {
    id: savePosition
    command: ["bash", "-c", "true"]
  }

  function persistPosition() {
    // Store the docked (revealed) target, not the live animated value.
    var mx = root.dockX ? root.cornerInset : root.marginX
    var my = root.dockY ? root.cornerInset : root.marginY
    var x = root.dockX && root.anchorRight ? Math.max(0, panel.width - mx - root.bubbleWidth) : mx
    var y = root.dockY && root.anchorBottom ? Math.max(0, panel.height - my - root.bubbleHeight) : my
    savePosition.command = [
      "bash", "-c",
      "mkdir -p \"$HOME/.local/state/voxtype-hud\" && printf '%s %s' \"$0\" \"$1\" > \"$HOME/.local/state/voxtype-hud/position\"",
      String(Math.round(x)), String(Math.round(y))
    ]
    savePosition.startDetached()
  }

  Timer {
    id: persistTimer
    interval: 320
    onTriggered: root.persistPosition()
  }

  // ── Avatar animation ─────────────────────────────────────────────────
  Timer {
    id: avatarTimer
    running: true
    interval: root.spriteFrameDuration
    repeat: true
    onTriggered: root.avatarFrame = (root.avatarFrame + 1) % root.spriteFrameCount
  }

  // ── voxtype status stream ────────────────────────────────────────────
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
    if (next === "recording")
      root.resetLevels()
    if (next === "done")
      doneTimer.restart()
    if (next === "recording" || next === "transcribing") {
      hideTimer.stop()
      root.reveal()
    } else if (next === "idle") {
      if (!root.hovered)
        hideTimer.restart()
    }
  }

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

  Timer {
    id: hideTimer
    interval: root.hideDelay
    onTriggered: {
      if (root.canHide && !root.hovered && !root.dragging)
        root.hide()
    }
  }

  // ── Theme + metrics (mirrors omarchy.osd) ────────────────────────────
  readonly property int padX: Style.space(14)
  readonly property int gap: Style.space(12)

  // Animation timings. `Style` has no duration helper — the first-party
  // plugins use plain millisecond literals, so these stay tunable here.
  readonly property int fadeDuration: 160
  readonly property int slideDuration: 280
  readonly property int meterSmoothing: 90

  readonly property int dotSize: Style.space(8)
  readonly property int dotSpacing: Style.space(6)

  readonly property int barCount: 9
  readonly property int barThickness: Style.space(3)
  readonly property int barSpacing: Style.space(3)
  readonly property int barsHeight: Style.space(18)
  readonly property int waveWidth: root.barCount * root.barThickness + (root.barCount - 1) * root.barSpacing

  readonly property int bubbleHeight: Style.space(48)
  readonly property int stopSize: Style.space(28)
  readonly property int buttonGap: Style.space(8)
  // Diameter of the accent dot left on screen when the bubble is hidden.
  readonly property int peekDotSize: Style.space(10)
  readonly property int translationOrbSize: Style.space(24)
  readonly property int translationOrbGap: Style.space(5)

  // Fixed indicator width, so the pill does not shift between states.
  readonly property int indicatorWidth: Math.max(root.waveWidth, 3 * root.dotSize + 2 * root.dotSpacing)

  // Idle is a circle; active states grow into a pill. `Row` skips invisible
  // children, so transcribing (no stop button) is narrower than recording.
  readonly property int activeWidth: root.padX + root.indicatorWidth
    + (root.mode === "recording"
      ? 2 * root.gap + root.stopSize + root.buttonGap + root.stopSize
      : root.gap)
    + root.spriteSize + root.padX
  readonly property int mainBubbleWidth: (root.mode === "idle" || root.mode === "done")
    ? root.bubbleHeight : root.activeWidth
  readonly property bool translationOrbVisible: root.mode === "idle" || root.mode === "done"
  readonly property int bubbleWidth: root.mainBubbleWidth
    + (root.translationOrbVisible ? root.translationOrbGap + root.translationOrbSize : 0)

  // The bubble grows from its docked edge when the state changes.
  onBubbleWidthChanged: {
    if (root.placed)
      root.applyMargins()
  }

  // Smooth slide for docking, hiding and re-growing. Disabled while dragging
  // so the bubble tracks the pointer 1:1.
  Behavior on posX {
    enabled: root.placed && !root.dragging
    NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutCubic }
  }
  Behavior on posY {
    enabled: root.placed && !root.dragging
    NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutCubic }
  }

  readonly property color cardColor: Util.alpha(Color.background, 0.97)
  readonly property color textColor: Color.popups.text
  readonly property color meterColor: Color.accent
  // A muted, background-toned border instead of the theme's accent popup one.
  readonly property var borderSpec: Border.flat(Util.alpha(Color.popups.text, 0.16), Math.max(1, Style.space(2)))

  // A full-screen, click-through layer surface with the input region limited
  // to the bubble. Keeping the surface static and moving the item inside it
  // (instead of moving the surface) makes dragging trivial and jitter-free.
  PanelWindow {
    id: panel
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "voxtype-bubble"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    mask: Region { item: bubble }

    onWidthChanged: root.place()
    onHeightChanged: root.place()

    // Full-window drag/click/hover surface. The mask means it only ever
    // receives pointer events over the bubble; later siblings (the bubble and
    // its controls) sit on top and win where they handle input.
    MouseArea {
      id: dragArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      property bool suppressClick: false
      property real pressX: 0
      property real pressY: 0
      property real startX: 0
      property real startY: 0

      onPressed: function (mouse) {
        pressX = mouse.x
        pressY = mouse.y
        startX = root.posX
        startY = root.posY
        suppressClick = false
        root.dragging = false
      }

      onPositionChanged: function (mouse) {
        if (!(mouse.buttons & Qt.LeftButton))
          return
        var dx = mouse.x - pressX
        var dy = mouse.y - pressY
        if (!root.dragging && Math.abs(dx) + Math.abs(dy) < root.dragThreshold)
          return
        root.dragging = true
        root.posX = Math.max(0, Math.min(panel.width - root.bubbleWidth, startX + dx))
        root.posY = Math.max(0, Math.min(panel.height - root.bubbleHeight, startY + dy))
        root.updateAnchorFromPosition()
      }

      onReleased: {
        if (!root.dragging)
          return
        root.dragging = false
        suppressClick = true
        root.snapToNearest()
        persistTimer.restart()
        if (root.canHide)
          hideTimer.restart()
      }

      onCanceled: {
        root.dragging = false
        suppressClick = false
      }

      onClicked: function (mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }
        root.onBubbleClick()
      }

      onContainsMouseChanged: {
        root.hovered = containsMouse
        if (root.dragging)
          return
        if (containsMouse) {
          hideTimer.stop()
          root.reveal()
        } else if (root.canHide) {
          hideTimer.restart()
        }
      }
    }

    // When hidden, the only thing left on screen is a small accent dot at the
    // docked edge. It sits inside the bubble's on-screen peek, so the same
    // input region keeps it hoverable.
    Rectangle {
      id: peekDot
      width: root.peekDotSize
      height: root.peekDotSize
      radius: width / 2
      color: root.meterColor
      visible: opacity > 0
      opacity: root.hidden ? 1 : 0
      x: root.dotCenterX - width / 2
      y: root.dotCenterY - height / 2
      Behavior on opacity {
        NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic }
      }
    }

    // ── The bubble ─────────────────────────────────────────────────────
    Item {
      id: bubble
      x: root.posX
      y: root.posY
      width: root.bubbleWidth
      height: root.bubbleHeight
      opacity: root.hidden ? 0 : (root.mode === "idle" ? 0.85 : 1)
      Behavior on width {
        NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic }
      }

      BorderSurface {
        width: root.mainBubbleWidth
        height: root.bubbleHeight
        radius: height / 2
        color: root.cardColor
        borderSpec: root.borderSpec
      }

      // Idle / done: the pixel-art avatar, clipped to the current frame.
      Image {
        id: avatarSprite
        visible: root.mode === "idle" || root.mode === "done"
        x: (root.mainBubbleWidth - width) / 2
        y: (parent.height - height) / 2
        width: root.spriteSize
        height: root.spriteSize
        source: root.spriteSheet
        smooth: false
        mirror: root.anchorRight
        sourceClipRect: Qt.rect(
          root.avatarFrame * root.spriteFrameWidth,
          (root.translationEnabled ? 2 : root.idleRow) * root.spriteFrameHeight,
          root.spriteFrameWidth,
          root.spriteFrameHeight
        )
      }

      // Active: indicator (waveform or dots) + action buttons.
      Row {
        visible: root.mode === "recording" || root.mode === "transcribing"
        anchors.left: parent.left
        anchors.leftMargin: root.padX
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap

        Item {
          width: root.indicatorWidth
          height: root.bubbleHeight

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
        }

        // Action buttons, while recording. Full bubble height (like the
        // indicator) so `Row`'s top alignment doesn't push them off-centre.
        Row {
          visible: root.mode === "recording"
          spacing: root.buttonGap

          // Cancel: discard the recording without transcribing.
          Item {
            width: root.stopSize
            height: root.bubbleHeight

            Rectangle {
              anchors.centerIn: parent
              width: root.stopSize
              height: root.stopSize
              radius: width / 2
              color: "transparent"
              border.color: Util.alpha(root.textColor, 0.45)
              border.width: Math.max(1, Style.space(1))
            }

            Item {
              anchors.centerIn: parent
              width: root.stopSize * 0.34
              height: width
              Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.max(1, Style.space(2))
                radius: height / 2
                color: root.textColor
                rotation: 45
              }
              Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.max(1, Style.space(2))
                radius: height / 2
                color: root.textColor
                rotation: -45
              }
            }

            MouseArea {
              anchors.centerIn: parent
              width: root.stopSize
              height: root.stopSize
              cursorShape: Qt.PointingHandCursor
              onClicked: function (mouse) {
                mouse.accepted = true
                root.cancelRecording()
              }
            }
          }

          // Stop: transcribe.
          Item {
            width: root.stopSize
            height: root.bubbleHeight

            Rectangle {
              anchors.centerIn: parent
              width: root.stopSize
              height: root.stopSize
              radius: width / 2
              color: root.meterColor
            }

            Rectangle {
              anchors.centerIn: parent
              width: root.stopSize * 0.34
              height: width
              radius: Style.space(2)
              color: root.textColor
            }

            MouseArea {
              anchors.centerIn: parent
              width: root.stopSize
              height: root.stopSize
              cursorShape: Qt.PointingHandCursor
              onClicked: function (mouse) {
                mouse.accepted = true
                root.stopRecording()
              }
            }
          }
        }

        // Sprite beside the action controls while recording/transcribing.
        Image {
          width: root.spriteSize
          height: root.spriteSize
          source: root.spriteSheet
          smooth: false
          mirror: root.anchorRight
          sourceClipRect: Qt.rect(
            root.avatarFrame * root.spriteFrameWidth,
            (root.translationEnabled ? 2 : root.idleRow) * root.spriteFrameHeight,
            root.spriteFrameWidth,
            root.spriteFrameHeight
          )
        }
      }

      // Translation-mode satellite, attached to the main bubble.
      Item {
        id: translationOrb
        visible: root.translationOrbVisible && !root.hidden
        x: root.mainBubbleWidth + root.translationOrbGap
        y: (root.bubbleHeight - height) / 2
        width: root.translationOrbSize
        height: root.translationOrbSize
        opacity: bubble.opacity

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: root.translationEnabled ? root.meterColor : root.cardColor
          border.color: root.translationEnabled ? root.meterColor : Util.alpha(root.textColor, 0.65)
          border.width: Math.max(1, Style.space(1))
        }

        Text {
          anchors.centerIn: parent
          text: root.translationBusy ? "…" : root.translationError !== "" ? "!" : "EN"
          color: root.translationEnabled ? root.cardColor : root.textColor
          font.family: "sans-serif"
          font.pixelSize: Style.space(9)
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          enabled: !root.translationLoading && !root.translationBusy
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.BusyCursor
          onClicked: function (mouse) {
            mouse.accepted = true
            root.toggleTranslation()
          }
        }
      }
    }
  }
}