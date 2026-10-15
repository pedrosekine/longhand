import QtQuick
import Quickshell
import Quickshell.Io

// Today's note: where it is, what it says, and the one place that writes it.
//
// Config comes from ~/.config/omarchy-student/config.json (see
// config.example.json in the repo). The vault path is machine-local and never
// lives in code. The note path is <vault>/<daily.dir>/<date in daily.format>.md,
// the same rule Obsidian's daily-notes plugin uses, so both agree on the file.
//
// Writes: create-if-missing from the template, then whatever the page holds.
// Atomic (temp + rename) so a half-written note never exists on disk, and
// async so a save costs the keystroke nothing. Nothing else in the system may
// write under the daily folder — that rule is what lets the agent say "I never
// touched your prose" and mean it.
Item {
  id: root

  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME")
    || Quickshell.env("HOME") + "/.config") + "/omarchy-student/config.json"

  property var config: ({})
  // The page's own type. `font` is the face the note is written in, `codeFont`
  // the one fenced code and frontmatter keep; empty means the page decides.
  readonly property string pageFont: (config && config.font) || ""
  readonly property string pageCodeFont: (config && config.codeFont) || ""
  readonly property bool configured: !!(config && config.vault && config.daily && config.daily.dir)
  property string configError: ""

  // The note currently loaded. `text` mirrors disk after load and after
  // every save; the page compares against it to know if anything is pending.
  //
  // The note's first line, when it is the agent link the template put there,
  // is held apart as `header` and never enters the editor: the page shows a
  // mark for it and writes it back unchanged on every save. `body` is what
  // the student sees and types. A note that does not start with the link has
  // an empty header and the body is the whole file.
  property string notePath: ""
  property string noteDate: ""        // the note's file name: a date in daily.format
  // Whether the note in the page is today's — checked against the clock,
  // so a page left open past midnight knows its note became yesterday's.
  property string today: ""
  readonly property bool isToday: noteDate !== "" && noteDate === today
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.today = root.configured ? root.todayStamp() : "" }
  property bool exists: false         // false: a day with no file yet, written on the first word
  property string text: ""
  property string header: ""
  property string frontmatter: ""     // the note's own `---` block, page-owned like the link line
  property string body: ""
  // A day the student marked private: the runner refuses it whole, so the
  // page must not even offer the agent. One line of frontmatter is the
  // mark, because that is what `student-agent` reads (note_is_private).
  readonly property bool notePrivate: /(^|\n)agent:[ \t]*false[ \t]*(\n|$)/.test(frontmatter)
  property bool ready: false
  property bool pending: false
  property bool saving: false
  property string error: ""

  signal loaded()
  signal externalChange()
  signal savedNow()

  // Where the runner lives and where it writes. The page only reads these.
  readonly property string runner: (config && config.runner) || (Quickshell.env("HOME") + "/.local/bin/student-agent")
  readonly property string agentDir: configured ? config.vault + "/" + (config.agentDir || "agents/student") : ""
  readonly property string statePath: agentDir !== "" && noteDate !== "" ? agentDir + "/daily/" + noteDate + ".json" : ""

  property string lastWritten: ""

  // Obsidian's daily-notes format is a moment.js string; Qt wants its own
  // tokens. Only the tokens a date format plausibly uses are mapped.
  function momentToQt(fmt) {
    return fmt.replace(/YYYY/g, "yyyy").replace(/YY/g, "yy").replace(/DD/g, "dd")
      .replace(/ddd/g, "ddd").replace(/HH/g, "HH").replace(/mm/g, "mm")
  }

  function dailyFormat() {
    return (config.daily && config.daily.format) || "YYYY-MM-DD"
  }

  function todayStamp() {
    return Qt.formatDate(new Date(), momentToQt(dailyFormat()))
  }

  function pathFor(stamp) {
    return config.vault + "/" + config.daily.dir + "/" + stamp + ".md"
  }

  function templatePath() {
    return config.daily && config.daily.template ? config.vault + "/" + config.daily.template + ".md" : ""
  }

  // Obsidian template variables: {{date}}, {{date:FMT}}, {{title}}. Enough
  // for a one-line template; anything else passes through untouched.
  // Split disk text into the page-owned header line and the student's body.
  function splitHeader(t) {
    // Frontmatter first (Obsidian properties, and the agent: false mark),
    // then the agent link line. Neither ever enters the editor; both are
    // written back unchanged unless the page itself changes them.
    var fm = t.match(/^---\n[\s\S]*?\n---\n?/)
    root.frontmatter = fm ? fm[0] : ""
    var rest = fm ? t.substring(fm[0].length) : t
    var m = rest.match(/^(\[\[[^\]\n]*\|agent\]\])\n?/)
    if (!m) { root.header = ""; root.body = rest; return }
    root.header = m[1]
    root.body = rest.substring(m[0].length)
  }

  // Mark the open note private, or take the mark off; the caller saves.
  // Only the `agent:` line is ours: any other property the student (or
  // Obsidian) put there survives, and an otherwise empty block goes rather
  // than being left behind as two bare rules.
  function setPrivate(on) {
    var fm = root.frontmatter
    var body = fm.replace(/^---\n/, "").replace(/\n---\n?$/, "")
    var lines = fm === "" ? [] : body.split("\n").filter(function (l) { return !/^agent:[ \t]*(true|false)[ \t]*$/.test(l) })
    if (on) lines.push("agent: false")
    var kept = lines.filter(function (l) { return l.trim() !== "" })
    root.frontmatter = kept.length === 0 ? "" : "---\n" + kept.join("\n") + "\n---\n"
  }

  // The blank line after the link is what keeps the link its own block for
  // the runner; put it back if the student deleted it.
  function joinHeader(bodyText) {
    var rest = root.header === "" ? bodyText
      : root.header + "\n" + (bodyText.charAt(0) === "\n" ? bodyText : "\n" + bodyText)
    return root.frontmatter + rest
  }

  function renderTemplate(raw, stamp) {
    var now = new Date()
    return raw
      .replace(/\{\{date:([^}]+)\}\}/g, function (_, f) { return Qt.formatDate(now, momentToQt(f)) })
      .replace(/\{\{date\}\}/g, stamp)
      .replace(/\{\{title\}\}/g, stamp)
      .replace(/\{\{time\}\}/g, Qt.formatTime(now, "HH:mm"))
  }

  // Point at a day's file (`stamp` is its name without .md). Same file:
  // re-read it only when nothing is pending or in flight, so an edit made
  // elsewhere while the page was closed shows up, and a save still landing
  // can never be overwritten by its own past. Another file: load fresh. The
  // page must flush, and wait for a save in flight, before switching.
  function openDate(stamp) {
    if (!configured) return
    var p = pathFor(stamp)
    root.today = todayStamp()
    if (p === notePath && ready) {
      if (!saving && !pending) noteFile.reload()
      return
    }
    root.ready = false
    root.error = ""
    root.noteDate = stamp
    root.notePath = p
    root.lastWritten = ""
    if (noteFile.path === p) noteFile.reload()
    else noteFile.path = p
  }

  function openToday() {
    if (configured) root.openDate(todayStamp())
  }

  // Called by the page with the editor's text (the body). No-ops when nothing
  // changed since the last write, so a save per keystroke never touches disk
  // twice.
  function save(bodyText) {
    if (!ready || error !== "") return
    // A day opened from the calendar has no file until something is
    // written in it; looking at it must not create one.
    if (!root.exists && bodyText.trim() === "") { root.pending = false; return }
    var content = root.joinHeader(bodyText)
    if (content === lastWritten) { root.pending = false; return }
    root.lastWritten = content
    root.text = content
    root.body = bodyText
    root.saving = true
    noteFile.setText(content)
  }

  function markPending(bodyText) {
    root.pending = root.joinHeader(bodyText) !== lastWritten
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.config = JSON.parse(text())
        root.configError = root.configured ? "" : "config.json needs vault and daily.dir"
      } catch (e) {
        root.config = ({})
        root.configError = "config.json is not valid JSON: " + e
      }
    }
    onLoadFailed: function (err) {
      root.config = ({})
      root.configError = "No config at " + root.configPath
    }
    onFileChanged: reload()
  }

  FileView {
    id: templateFile
    path: root.templatePath()
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: noteFile
    atomicWrites: true
    printErrors: false
    // Obsidian (or anything) may write the note while the page has it
    // open: re-read it then, so the next keystroke does not write over what
    // was written there. Our own writes read back as `lastWritten` and are
    // ignored below.
    watchChanges: true
    onFileChanged: if (!root.saving) reload()
    onLoaded: {
      var t = text()
      // A load that lands while our own write is in flight, or that reads
      // back exactly what we wrote, carries no news.
      if (root.ready && (root.saving || t === root.lastWritten)) return
      var external = root.ready
      root.exists = true
      root.lastWritten = t
      root.text = t
      root.splitHeader(t)
      root.ready = true
      root.pending = false
      if (external) root.externalChange()
      else root.loaded()
    }
    onLoadFailed: function (err) {
      if (err === FileViewError.FileNotFound) {
        // No note for this day. Today: seed it from the template now, the
        // one create path, as Obsidian would on its side. Any other day:
        // hold the template's header ready but write nothing until the
        // student does.
        var raw = ""
        try { raw = templateFile.text() } catch (e) { raw = "" }
        var seed = raw ? root.renderTemplate(raw, root.noteDate) : ""
        root.text = seed
        root.splitHeader(seed)
        root.ready = true
        root.pending = false
        if (root.noteDate === root.todayStamp()) {
          root.lastWritten = seed
          root.exists = seed !== ""
          if (seed !== "") noteFile.setText(seed)
        } else {
          root.lastWritten = ""
          root.exists = false
        }
        root.loaded()
        return
      }
      root.error = "Cannot read " + root.notePath + ": " + FileViewError.toString(err)
      root.ready = false
    }
    onSaved: { root.saving = false; root.pending = false; root.exists = true; root.savedNow() }
    onSaveFailed: function (err) {
      root.saving = false
      root.error = "Cannot write " + root.notePath + ": " + FileViewError.toString(err)
    }
  }
}
