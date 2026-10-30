// Say — what a dashboard row says (moved out of Page.qml on 2026-10-30,
// the split's second pass; `tests/tst_say.qml` holds it). Words only: no
// state of the page's, which comes in as arguments — the projects, for a
// course's name, and `now`, for how far off a date is (the moment it is
// asked, when not given).
.pragma library

// What a row says. The title is the words alone: the dates and the
// priority a line carries are drawn as marks, so the metadata is on disk
// and quiet on screen.
function taskTitle(t) { return t.title !== undefined && t.title !== "" ? t.title : t.text }

// Priority is a mark beside the box, not a word in the row: ▲ for the
// high one, ▽ for the low, nothing for the rest.
function taskMark(t) {
  if (!t || t.priority === undefined || t.priority === 0) return ""
  return t.priority >= 1 ? "▲" : "▽"
}

// A course's own name, from its tag. The sidebar reads the curriculum for
// them; a tag the list does not know stays a tag. (Not `projectName` —
// that is the open project's own name, a property of the sidebar.)
function courseName(tag, projects) {
  for (var i = 0; i < projects.length; i++)
    if (projects[i].tag === tag) return projects[i].name || tag
  return tag
}

// A course for a row that has no heading path to fall back on.
function courseLabel(tag, projects) {
  if (!tag) return ""
  var name = courseName(tag, projects)
  return name === tag ? "#" + tag : name
}

// Where it came from, under the words: the course in full, then the
// section it was written in, then how long ago. The line that makes
// "draft the intro" mean something again three days later. The dates are
// not in here — they are pills, as they are in the note.
function taskWhere(t, under, projects) {
  var path = (t.path || []).slice()
  var full = t.project ? courseName(t.project, projects) : ""
  // The first heading is the course itself by the convention in use, so
  // its full name belongs there when the list knows it.
  if (full !== "" && full !== t.project) {
    if (path.length > 0) path[0] = full
    else path = [full]
  } else if (path.length === 0 && t.project) {
    path = ["#" + t.project]
  }
  // Under a band that already names the course, the course is noise.
  if (under !== undefined && under !== "" && path.length > 0 && path[0] === under) path.shift()
  var bits = []
  if (path.length > 0) bits.push(path.join(" › "))
  bits.push(sayAge(t.age))
  if (t.details > 0) bits.push(t.details === 1 ? "1 line of detail" : t.details + " lines of detail")
  var life = sayLife(t)
  if (life !== "") bits.push(life)
  return bits.join("   ·   ")
}

// The silence clock, said only when it matters: through the last quarter
// of a box's life, and once it is away. Nothing goes without first being
// shown as about to (agent/lifespan.py).
function sayLife(t) {
  if (t.away === "shelved") return "put aside"
  if (t.away === "quiet") return "gone quiet"
  if (!t.warn) return ""
  return t.left === 1 ? "goes quiet tomorrow" : "goes quiet in " + t.left + " days"
}

// The month a row falls in, for the band above it.
function monthLabel(ms, now) {
  var d = new Date(ms)
  return Qt.formatDate(d, d.getFullYear() === (now || new Date()).getFullYear() ? "MMMM" : "MMMM yyyy")
}

function taskMs(t) {
  var iso = t.when || t.due
  if (!iso) return 0
  var p = iso.split(" ")[0].split("-")
  return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)).getTime()
}

function sayDate(iso, now) {
  if (!iso) return ""
  var parts = iso.split(" ")
  var ymd = parts[0].split("-")
  var d = new Date(parseInt(ymd[0], 10), parseInt(ymd[1], 10) - 1, parseInt(ymd[2], 10))
  var today = now ? new Date(now.getTime()) : new Date()
  today.setHours(0, 0, 0, 0)
  var days = Math.round((d.getTime() - today.getTime()) / 86400000)
  var say = days === 0 ? "today" : days === 1 ? "tomorrow" : days === -1 ? "yesterday"
    : days < 0 ? Math.abs(days) + " days late" : Qt.formatDate(d, "ddd d MMM")
  return say + (parts[1] && parts[1] !== "23:59" ? " " + parts[1] : "")
}

function sayAge(age) {
  return age === 0 ? "written today" : age === 1 ? "written yesterday" : "written " + age + " days ago"
}

// An open deadline a fortnight past its date steps aside (longhand-check);
// the days it has left, through the last four of them, else 0.
function asideIn(d, now) {
  if (d.status !== "open") return 0
  var left = Math.ceil(((d.due + 14 * 86400) * 1000 - (now ? now.getTime() : Date.now())) / 86400000)
  return left > 0 && left <= 4 ? left : 0
}

// A row's kind: a question, something the agent did and tells (told), or
// something it proposes.
function askKind(x) { return x.told ? "told" : x.kind === "question" ? "question" : "proposal" }

// What a proposal or a told row says, by its kind.
function sayAsk(x, under, now) {
  var what = x.kind === "do-date" ? "do " + sayDate(x.date, now) + (under ? "" : " · " + (x.title || ""))
    : x.kind === "file" ? "file “" + x.name.replace(/\.pdf$/, "") + "” in " + (x.title || x.project)
    : x.kind === "deadline" ? "deadline: " + x.title + " · 📅 " + sayDate(x.date, now)
    : x.kind === "project" ? "make it a project: " + x.title + " #" + x.project
    : x.kind === "priority" ? "priority " + (x.priority === 2 ? "▲ high" : x.priority === 1 ? "medium" : "▽ low")
      + (under ? "" : " · " + x.title)
    : x.kind === "steps" ? "steps: " + x.steps.join(" · ")
    : x.kind === "drop" ? "drop it?" + (under ? "" : " · " + x.title)
    : x.kind === "done" ? "looks done — tick it?" + (under ? "" : " · " + x.title)
    : x.title || ""
  return x.told ? "done: " + what : what
}
