import QtQuick
import Quickshell
import Quickshell.Io

// Live Pomodoro state. Watches the CLI's state.json (no polling processes)
// and recomputes the countdown locally every second.
Item {
  id: root

  property var settings: ({})

  // Session lengths. Defaults mirror cli/pomo; the state file overrides them
  // with the cli's current focus_len/break_len (custom durations update these).
  property int focusLen: 1500
  property int breakLen: 300

  // Raw state from the file.
  property string phase: "idle" // idle | focus | break
  property string runStatus: "idle" // idle | running | paused | done
  property int endsAt: 0
  property int storedRemaining: 0
  property bool autoStart: false
  // Count-up mode: an open-ended focus session. endsAt holds the session's
  // START epoch (not a deadline) and "remaining" holds elapsed seconds while
  // paused; there is no total, so the session never expires.
  property bool countup: false
  // The deadline this session is for (`pomo start --for <id>`), 0 when none.
  property int target: 0

  // Live values.
  property int nowSec: Math.floor(Date.now() / 1000)
  property int remaining: 0
  property int total: 0 // this session's length (stored by cli/pomo)

  // Fallback for sessions started before total was stored. Count-up has no
  // total by design, so it must not fall back to the focus length either.
  readonly property int effTotal: countup ? 0 : total > 0 ? total : phase === "focus" ? focusLen : phase === "break" ? breakLen : 0

  readonly property bool expired: (runStatus === "done") || (runStatus === "running" && !countup && phase !== "idle" && endsAt > 0 && nowSec >= endsAt)
  readonly property bool live: runStatus === "running" && !expired
  // Ready state: next phase armed at full length, waiting for play.
  readonly property bool ready: !countup && !live && effTotal > 0 && remaining >= effTotal
  readonly property real progress: !countup && effTotal > 0 ? Math.max(0, Math.min(1, 1 - remaining / effTotal)) : 0

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/longhand/state.json"

  function fmt(s) {
    var m = Math.floor(s / 60)
    var r = s % 60
    return m + ":" + (r < 10 ? "0" + r : r)
  }

  // ✓ once a session has run out and waits for the next to be started:
  // "● 0:00" read as a timer still going (the bar pass, 2026-11-28).
  readonly property string labelText: phase === "idle" ? "○ --:--"
    : expired ? "✓ " + fmt(0)
    : countup ? ((runStatus === "paused" ? "○ " : "↑ ") + fmt(remaining))
    : (runStatus === "paused" ? "○ " : "● ") + fmt(remaining)

  readonly property string phaseTitle: expired ? "Done" : phase === "focus" ? "Focus"
    : phase === "break" ? "Break" : "Pomodoro"

  // What state it is in, in words: the popup's header and the bar's tip.
  // A ready phase (armed at its full length, waiting for play) and a pause
  // halfway through looked alike, and so did a paused count-up and a paused
  // countdown.
  readonly property string stateText: phase === "idle" ? "Timer"
    : expired ? (phase === "focus" ? "Focus done" : "Break over")
    : (phase === "focus" ? "Focus" : "Break")
      + (countup ? " · counting up" : "")
      + (live ? "" : ready ? " · ready" : runStatus === "paused" ? " · paused" : "")

  // Expiry edge detection: ring once when a running phase hits zero.
  // The CLI persists a "done" status on completion, so re-ticks (or a
  // pause/resume cycle on the finished timer) can't re-fire and double-count.
  // firstTick avoids a spurious bell when the shell (re)starts mid-expiry.
  //
  // A session that ran out while the shell was not running is still
  // "running" in the file, past its end: nothing has logged it. It used to
  // stay so (the first tick skipped it, and the next saw it already
  // expired), uncounted and at 0:00 until a key was pressed. It is ended
  // now too, without the bell when it ran out a while ago: a sound at login
  // for a session that ended hours before says nothing.
  property bool prevExpired: false
  property bool firstTick: true

  function tick() {
    nowSec = Math.floor(Date.now() / 1000)
    if (countup)
      remaining = runStatus === "running" ? Math.max(0, nowSec - endsAt) : storedRemaining
    else
      remaining = runStatus === "running" ? Math.max(0, endsAt - nowSec) : storedRemaining
    var e = runStatus === "running" && !countup && phase !== "idle" && endsAt > 0 && nowSec >= endsAt
    if (e && !prevExpired && !expiredProc.running) {
      var stale = firstTick && nowSec - endsAt > 120
      expiredProc.environment = stale ? ({ LONGHAND_SILENT: "1" }) : ({})
      expiredProc.command = ["pomo", "expired"]
      expiredProc.running = true
    }
    prevExpired = e
    firstTick = false
    // The day's count is the day's: past midnight (or a Monday, or the
    // first of a month) it is counted again, not only when a session ends.
    if (nowSec >= recountAt) recount(logView.text())
  }

  // Session counters from the CLI log (same scopes as `pomo stats`).
  property int dayCount: 0
  property int weekCount: 0
  property int monthCount: 0
  // Focused time per scope (secs), summed from the logged session lengths.
  property int daySec: 0
  property int weekSec: 0
  property int monthSec: 0

  readonly property string logPath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/longhand/pomo.log"

  function pad(n) {
    return (n < 10 ? "0" : "") + n
  }

  function isoDay(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
  }

  // When the counts go stale: the next local midnight.
  property int recountAt: 0

  function recount(raw) {
    var now = new Date()
    var midnight = new Date(now)
    midnight.setHours(24, 0, 0, 0)
    recountAt = Math.floor(midnight.getTime() / 1000)
    var day = isoDay(now)
    var monday = new Date(now)
    monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7))
    var mon = isoDay(monday)
    var m1 = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-01"
    var dc = 0, wc = 0, mc = 0, ds = 0, ws = 0, ms = 0
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf("focus completed")
      if (at < 0) continue
      // The logged length ("m:ss", "h:mm:ss") follows "focus completed · ".
      // Count-up lines carry a trailing "· count-up" tag, so cut at the next ·.
      var start = at + 15
      while (lines[i].charAt(start) === "·" || lines[i].charAt(start) === " ") start++
      var stop = lines[i].indexOf("·", start)
      var token = (stop < 0 ? lines[i].substring(start) : lines[i].substring(start, stop)).trim()
      var parts = token.split(":")
      var secs = 0
      for (var p = 0; p < parts.length; p++) secs = secs * 60 + (parseInt(parts[p], 10) || 0)
      var dt = lines[i].substring(0, 10)
      if (dt >= day) { dc++; ds += secs }
      if (dt >= mon) { wc++; ws += secs }
      if (dt >= m1) { mc++; ms += secs }
    }
    dayCount = dc
    weekCount = wc
    monthCount = mc
    daySec = ds
    weekSec = ws
    monthSec = ms
  }

  function zeroCounts() {
    dayCount = 0
    weekCount = 0
    monthCount = 0
    daySec = 0
    weekSec = 0
    monthSec = 0
  }

  function applyText(raw) {
    var d = null
    try {
      d = JSON.parse(raw)
    } catch (e) {
      return
    }
    phase = d.phase || "idle"
    runStatus = d.status || "idle"
    endsAt = d.ends_at || 0
    storedRemaining = d.remaining || 0
    total = d.total || 0
    if (d.focus_len > 0) focusLen = d.focus_len
    if (d.break_len > 0) breakLen = d.break_len
    autoStart = d.auto === true
    countup = d.countup === true
    target = d["for"] > 0 ? d["for"] : 0
    tick()
  }

  function stateGone() {
    phase = "idle"
    runStatus = "idle"
    endsAt = 0
    storedRemaining = 0
    total = 0
    focusLen = 1500
    breakLen = 300
    autoStart = false
    countup = false
    target = 0
    tick()
  }

  // Fire-and-forget CLI actions; the FileView picks up the result. One at a
  // time, as the deadlines' are: the state file is rewritten whole. The ones
  // asked meanwhile wait their turn (the bar pass: they were dropped, so a
  // pause then a resume, or a length then auto-start, did only the first).
  property var queue: []
  function run() {
    var cmd = ["pomo"]
    for (var i = 0; i < arguments.length; i++) cmd.push(arguments[i])
    root.queue = root.queue.concat([cmd])
    root.next()
  }
  function next() {
    if (actionProc.running || root.queue.length === 0) return
    actionProc.command = root.queue[0]
    root.queue = root.queue.slice(1)
    actionProc.running = true
  }

  function toggle() {
    run("toggle")
  }

  function skip() {
    run("skip")
  }

  function reset() {
    run("reset")
  }

  function startFocus(minutes) {
    run("start", "focus", String(minutes))
  }

  function startCountup() {
    run("start", "focus", "up")
  }

  function autostartToggle() {
    run("autostart", "toggle")
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyText(text())
    onLoadFailed: root.stateGone()
  }

  FileView {
    id: logView
    path: root.logPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.recount(text())
    onLoadFailed: root.zeroCounts()
  }

  Process {
    id: actionProc
    running: false
    onExited: root.next()
  }

  Process {
    id: expiredProc
    running: false
  }
}
