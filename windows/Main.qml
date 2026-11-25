import QtQuick
import Qt.labs.platform as Platform
import Quickshell
import Quickshell.Io
import LonghandHost
import qs.Commons as Commons
import "../plugin-page"
import "../plugin" as Pomo
import "../plugin-deadline" as Deadline

// What omarchy-shell is to Longhand, on Windows: something that holds the
// page, opens it when asked — by a global key, the tray, a second `longhand`
// — and hears it ask to be hidden; and, where the shell has a bar with the
// timer and the next deadline in it, an icon by the clock that says both.
// Page.qml and the two Service.qml are loaded as they are.
Item {
  id: host

  QtObject {
    id: shell
    function hide(id) { page.close(); return true }
  }

  Page {
    id: page
    objectName: "longhandPage"
    shell: shell
    manifest: ({ id: "longhand.page" })
  }

  // The bar's two widgets, loaded as they are (plugin/Panel.qml,
  // plugin-deadline/Panel.qml). Each holds its own service — the timer's
  // state, the deadline store, read live, `pomo expired` run when a session
  // runs out — and its popup, which the shim's KeyboardPanel opens as a
  // small window by the clock. Where the shell has a bar to hold their
  // labels, the tray says what the labels say, from the same services.
  Pomo.Panel { id: pomoPanel; bar: barStandIn; onSwitchRequested: host.popup("deadlines") }
  Deadline.Panel { id: deadlinePanel; bar: barStandIn; onSwitchRequested: host.popup("timer") }
  // The bar a widget asks for its colours and its face. There is none: this
  // answers with Windows' own (the shim's palette, the system's text face).
  QtObject {
    id: barStandIn
    readonly property var faces: Qt.fontFamilies()
    readonly property color foreground: Commons.Color.foreground
    readonly property color barForeground: Commons.Color.foreground
    readonly property color urgent: Commons.Color.urgent
    readonly property string fontFamily: faces.indexOf("Segoe UI Variable Text") >= 0 ? "Segoe UI Variable Text" : "Segoe UI"
    readonly property string position: "bottom"
    readonly property bool vertical: false
    readonly property var activePopout: null
  }
  // A widget's service is the one thing in it with a label for the bar.
  function serviceOf(panel) {
    for (var i = 0; i < panel.children.length; i++)
      if (panel.children[i].labelText !== undefined && panel.children[i].text === undefined) return panel.children[i]
    return null
  }
  readonly property var pomo: host.serviceOf(pomoPanel)
  readonly property var deadlines: host.serviceOf(deadlinePanel)

  // One popup at a time, as the bar has one open: the one asked for opens
  // (or, open already, closes), the other goes.
  function popup(which) {
    var asked = which === "timer" ? pomoPanel : deadlinePanel
    var other = which === "timer" ? deadlinePanel : pomoPanel
    if (other.opened) other.close()
    asked.toggle()
  }

  // ------------------------------------------------------------ the page

  // The shell has had the page loaded long before anyone summons it; here a
  // summon waits until the page has read its config (or found there is none).
  property bool configRead: false
  property var waiting: null

  function open(payload) {
    if (!host.configRead) { host.waiting = payload; return }
    page.open(payload)
  }
  // As shell.qml: summon opens, toggle opens or hides the overlay.
  function summon(payload) { host.open(payload || "{}") }
  function toggle(payload) {
    if (page.opened) shell.hide("longhand.page")
    else host.open(payload || "{}")
  }
  function pinned() { host.summon(JSON.stringify({ shape: "alongside" })) }

  function ready() {
    if (host.configRead) return
    host.configRead = true
    if (host.waiting !== null) { var p = host.waiting; host.waiting = null; host.open(p) }
  }
  Connections {
    target: page.noteService
    function onConfigChanged() { host.ready() }
  }
  Timer { interval: 1500; running: true; onTriggered: host.ready() }

  // Windows ending the session (longhand_host.py, save_at_session_end): what
  // is typed goes to the disk now, and the host waits while it is saving.
  // Nothing is put away: the person may yet cancel the sign-out.
  readonly property bool noteSaving: page.noteSaving
  function saveNow() { page.flush() }

  // Leaving: the page puts away what it holds, the last save lands, then out.
  function leave() {
    page.windowOpen = false
    page.close()
    leaving.tries = 0
    leaving.restart()
  }
  Timer {
    id: leaving
    property int tries: 0
    interval: 150
    onTriggered: {
      if (page.noteSaving && ++tries < 20) restart()
      else Qt.quit()
    }
  }

  Connections {
    target: hostBridge
    function onSummonRequested(payload) { host.summon(payload) }
    function onToggleRequested(payload) { host.toggle(payload) }
    function onPomoRequested(what) { if (what === "skip") host.pomo.skip(); else host.pomo.toggle() }
    function onPopupRequested(which) { host.popup(which) }
    function onQuitRequested() { host.leave() }
    function onKeysChanged() { host.keysRead++ }
  }

  // Without a tray (the check, a run for one look): put away, the host ends.
  Connections {
    target: page
    function onShowingChanged() { if (!page.showing && !hostResident && !hostKeepAlive) Qt.quit() }
  }

  // ------------------------------------------------------------ the tray

  property int keysRead: 0
  function key(action) {
    host.keysRead
    var k = hostBridge.keyName(action)
    return k === "" ? "" : "\t" + k
  }

  // A key Windows would not give Longhand (another program holds it): said
  // in the menu and in the keys sheet (winkeys.py), since what the host
  // prints reaches no one when Longhand was started from the Start menu.
  readonly property string keyTrouble: {
    host.keysRead
    var why = hostBridge.keyProblems().split("\n").filter(function (s) { return s !== "" })
    return why.length === 0 ? ""
      : why[0] + (why.length > 1 ? " (and " + (why.length - 1) + " more)" : "") + " — Ctrl+/ in the page moves it"
  }

  readonly property string timerLine:pomo.phase === "idle" ? ""
    : pomo.expired ? pomo.phaseTitle
    : (pomo.phaseTitle + " " + pomo.fmt(pomo.remaining) + (pomo.live ? "" : pomo.ready ? " ready" : " paused"))
  readonly property string timerAction: pomo.phase === "idle" ? "Start focus"
    : pomo.live ? "Pause · " + host.timerLine
    : pomo.expired ? "Start the next"
    : (pomo.ready ? "Start · " : "Resume · ") + pomo.phaseTitle + " " + pomo.fmt(pomo.remaining)
  readonly property string deadlineLine: deadlines.nextItem
    ? deadlines.nextItem.title + " · " + deadlines.fmtRel(deadlines.nextItem.due) : ""

  // What the bar's page glyph says (plugin-page/BarWidget.qml): a reply
  // waiting that has not been looked at, and what the agent proposes or
  // asks. The tray says both in words, in its tip and its menu — never on
  // the seal, which identifies Longhand and is no status light
  // (docs/brand/README.md), and never as a notification or a sound.
  AgentState { id: agent; config: page.noteService.config }
  property int asks: 0
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/proposals.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { host.asks = JSON.parse(text()).items.filter(function (x) { return x.status === "open" }).length }
      catch (e) { host.asks = 0 }
    }
    onLoadFailed: host.asks = 0
    onFileChanged: reload()
  }
  readonly property string agentLine: [
    agent.unread > 0 ? agent.unread + (agent.unread === 1 ? " reply" : " replies") + " waiting" : "",
    host.asks > 0 ? host.asks + " from the agent, in the dashboard" : ""
  ].filter(function (s) { return s !== "" }).join(" · ")

  // A session ran out: `pomo expired`, which the timer's service runs, says
  // it as notify-send says it on Omarchy, and here that comes to the tray
  // (windows/notify.py). The sound is pomo's too.
  Connections {
    target: hostBridge
    function onNotifyRequested(title, body) { if (hostResident) tray.showMessage(title, body) }
  }

  // The seal in Windows' colours, as the launcher's is in the theme's on
  // Omarchy (tools/theme_icon.py): the tile in the ground of the mode the
  // apps are in, the seal in the accent, followed live.
  readonly property string themedIcon: hostResident
    ? Host.themedIcon(String(Commons.Color.background), String(Commons.Color.foreground), String(Commons.Color.accent)) : ""

  Platform.SystemTrayIcon {
    id: tray
    visible: hostResident
    icon.source: host.themedIcon !== "" ? host.themedIcon : Qt.resolvedUrl("../launcher/longhand.svg")
    // Windows cuts a tip at 127 characters: the agent's line first, it is
    // the one that asks for something.
    tooltip: ["Longhand", host.agentLine, host.timerLine, host.deadlineLine].filter(function (s) { return s !== "" }).join(" · ").slice(0, 127)
    // A click is the page as a window: the place to write. The middle
    // button is the timer's popup, as it is the timer's on the bar.
    onActivated: function (reason) {
      if (reason === Platform.SystemTrayIcon.Trigger || reason === Platform.SystemTrayIcon.DoubleClick) host.pinned()
      else if (reason === Platform.SystemTrayIcon.MiddleClick) host.popup("timer")
    }

    menu: Platform.Menu {
      Platform.MenuItem { text: "Today's note" + host.key("alongside"); onTriggered: host.pinned() }
      Platform.MenuItem { text: host.agentLine; visible: host.agentLine !== ""; onTriggered: host.pinned() }
      Platform.MenuItem { text: "Over everything" + host.key("page"); onTriggered: host.toggle("{}") }
      Platform.MenuItem { text: host.keyTrouble; visible: host.keyTrouble !== ""; onTriggered: host.pinned() }
      Platform.MenuSeparator {}
      Platform.MenuItem { text: host.timerAction + host.key("pomoToggle"); onTriggered: pomo.toggle() }
      Platform.MenuItem { text: "Skip to the next" + host.key("pomoSkip"); visible: pomo.phase !== "idle"; onTriggered: pomo.skip() }
      Platform.MenuItem { text: "Reset the timer"; visible: pomo.phase !== "idle"; onTriggered: pomo.reset() }
      // The bar's two popups: the timer's (a length typed, the day's count)
      // and the deadlines' (ticked, graded, opened in the note).
      Platform.MenuItem { text: "Timer…" + host.key("pomoPopup"); onTriggered: host.popup("timer") }
      Platform.MenuSeparator {}
      Platform.MenuItem { text: (deadlines.nextItem ? deadlines.tooltipText : "Deadlines") + "…" + host.key("deadlines"); onTriggered: host.popup("deadlines") }
      Platform.MenuSeparator {}
      Platform.MenuItem { text: "Quit Longhand"; onTriggered: host.leave() }
    }
  }

  // The bar's other two widgets, each an icon of its own beside the seal,
  // as they stand beside the page's glyph on Omarchy: what each label says,
  // one click to its popup (2026-11-24, the user: the timer and the
  // deadlines were "inside the Longhand icon", too many clicks away).
  // Windows puts a new icon under the ^ arrow until the person pins it
  // (Settings → Personalization → Taskbar → Other system tray icons).
  function glyph(which, text, role) {
    return Host.trayGlyph(which, text, role, String(Commons.Color.background), String(Commons.Color.foreground),
                          String(Commons.Color.accent), String(Commons.Color.muted), String(Commons.Color.urgent))
  }

  // The timer: the minutes left (or gone, counting up), in the accent while
  // a focus runs, the text's colour in a break, faint paused or not started.
  readonly property string timerGlyph: pomo.phase === "idle" ? "○" : pomo.expired ? "✓"
    : String(pomo.countup ? Math.floor(pomo.remaining / 60)
             : pomo.remaining >= 5940 ? Math.round(pomo.remaining / 3600) + "h" : Math.ceil(pomo.remaining / 60))
  readonly property string timerRole: !pomo.live ? "muted" : pomo.phase === "focus" ? "accent" : "text"
  Platform.SystemTrayIcon {
    id: timerTray
    visible: hostResident
    icon.source: host.glyph("timer", host.timerGlyph, host.timerRole) || Qt.resolvedUrl("../launcher/longhand.svg")
    tooltip: ("Longhand timer · " + (host.timerLine || "not started")).slice(0, 127)
    onActivated: function (reason) {
      if (reason === Platform.SystemTrayIcon.Trigger || reason === Platform.SystemTrayIcon.DoubleClick) host.popup("timer")
      else if (reason === Platform.SystemTrayIcon.MiddleClick) pomo.toggle()
    }
    menu: Platform.Menu {
      Platform.MenuItem { text: host.timerAction + host.key("pomoToggle"); onTriggered: pomo.toggle() }
      Platform.MenuItem { text: "Skip to the next" + host.key("pomoSkip"); visible: pomo.phase !== "idle"; onTriggered: pomo.skip() }
      Platform.MenuItem { text: "Reset the timer"; visible: pomo.phase !== "idle"; onTriggered: pomo.reset() }
      Platform.MenuItem { text: "Timer…" + host.key("pomoPopup"); onTriggered: host.popup("timer") }
    }
  }

  // The deadlines: how far off the next one is (4d, 9h, 25m), "!" in the
  // urgent colour once it is late, a tick when all are handed in.
  readonly property string deadlineGlyph: deadlines.nextItem
    ? (deadlines.isLate(deadlines.nextItem.due) ? "!" : deadlines.unit(deadlines.nextItem.due - deadlines.nowSec))
    : deadlines.items.length > 0 ? "✓" : "–"
  readonly property string deadlineRole: !deadlines.nextItem ? "muted"
    : deadlines.isLate(deadlines.nextItem.due) || deadlines.isUrgent(deadlines.nextItem.due) ? "urgent" : "text"
  Platform.SystemTrayIcon {
    id: deadlineTray
    visible: hostResident
    icon.source: host.glyph("deadlines", host.deadlineGlyph, host.deadlineRole) || Qt.resolvedUrl("../launcher/longhand.svg")
    tooltip: ("Longhand deadlines · " + deadlines.tooltipText).slice(0, 127)
    onActivated: function (reason) {
      if (reason === Platform.SystemTrayIcon.Trigger || reason === Platform.SystemTrayIcon.DoubleClick) host.popup("deadlines")
    }
    menu: Platform.Menu {
      Platform.MenuItem { text: (deadlines.nextItem ? deadlines.tooltipText : "Deadlines") + "…" + host.key("deadlines"); onTriggered: host.popup("deadlines") }
    }
  }
}
