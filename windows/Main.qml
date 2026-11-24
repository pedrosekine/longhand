import QtQuick
import Qt.labs.platform as Platform
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

  // The bar widgets' own services: the timer's state and the deadline store,
  // read live, and `pomo expired` run when a session runs out.
  Pomo.Service { id: pomo }
  Deadline.Service { id: deadlines }

  // ------------------------------------------------------------ the page

  // The shell has had the page loaded long before anyone summons it; here a
  // summon waits until the page has read its config (or found there is none).
  property bool configRead: false
  property var waiting: null
  // Opened before the note has been read, the page asks the note to take the
  // keys while it has no rows yet, and a sheet's hidden key catcher keeps
  // them (so the page's own "keys nowhere" net never fires). The host owes
  // the note the keys once it has loaded: the page's own way to the middle.
  property bool keysOwed: false

  function open(payload) {
    if (!host.configRead) { host.waiting = payload; return }
    host.keysOwed = !page.noteService.ready
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
    function onLoaded() {
      if (!host.keysOwed) return
      host.keysOwed = false
      Qt.callLater(page.focusCenter)
    }
  }
  Timer { interval: 1500; running: true; onTriggered: host.ready() }

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
    function onPomoRequested(what) { if (what === "skip") pomo.skip(); else pomo.toggle() }
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

  readonly property string timerLine: pomo.phase === "idle" ? ""
    : pomo.expired ? pomo.phaseTitle
    : (pomo.phaseTitle + " " + pomo.fmt(pomo.remaining) + (pomo.live ? "" : pomo.ready ? " ready" : " paused"))
  readonly property string timerAction: pomo.phase === "idle" ? "Start focus"
    : pomo.live ? "Pause · " + host.timerLine
    : pomo.expired ? "Start the next"
    : (pomo.ready ? "Start · " : "Resume · ") + pomo.phaseTitle + " " + pomo.fmt(pomo.remaining)
  readonly property string deadlineLine: deadlines.nextItem
    ? deadlines.nextItem.title + " · " + deadlines.fmtRel(deadlines.nextItem.due) : ""

  // A session ran out: said by the tray, as notify-send says it on Omarchy.
  // (The sound is `pomo expired`'s, which the timer's service runs.)
  property bool settled: false
  Timer { interval: 3000; running: true; onTriggered: host.settled = true }
  Connections {
    target: pomo
    function onExpiredChanged() {
      if (!pomo.expired || !host.settled || !hostResident || pomo.runStatus === "done") return
      tray.showMessage("Pomodoro", pomo.phase === "focus" ? "Focus done — break time" : "Break over — back to focus")
    }
  }

  Platform.SystemTrayIcon {
    id: tray
    visible: hostResident
    icon.source: Qt.resolvedUrl("../launcher/longhand.svg")
    tooltip: ["Longhand", host.timerLine, host.deadlineLine].filter(function (s) { return s !== "" }).join(" · ").slice(0, 120)
    // A click is the page as a window: the place to write.
    onActivated: function (reason) {
      if (reason === Platform.SystemTrayIcon.Trigger || reason === Platform.SystemTrayIcon.DoubleClick) host.pinned()
    }

    menu: Platform.Menu {
      Platform.MenuItem { text: "Today's note" + host.key("alongside"); onTriggered: host.pinned() }
      Platform.MenuItem { text: "Over everything" + host.key("page"); onTriggered: host.toggle("{}") }
      Platform.MenuSeparator {}
      Platform.MenuItem { text: host.timerAction + host.key("pomoToggle"); onTriggered: pomo.toggle() }
      Platform.MenuItem { text: "Skip to the next" + host.key("pomoSkip"); visible: pomo.phase !== "idle"; onTriggered: pomo.skip() }
      Platform.MenuItem { text: "Reset the timer"; visible: pomo.phase !== "idle"; onTriggered: pomo.reset() }
      Platform.MenuSeparator {}
      Platform.MenuItem { text: deadlines.tooltipText; enabled: false }
      Platform.MenuSeparator {}
      Platform.MenuItem { text: "Quit Longhand"; onTriggered: host.leave() }
    }
  }
}
