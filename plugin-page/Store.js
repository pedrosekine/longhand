// Store — the deadline store as the plugins read it (2026-10-30: the page's
// Deadlines.qml and the popup's Service.qml each kept a copy of this, word
// for word but for what they then left out; `tests/tst_store.qml` holds it).
// It lives beside the page, and `tools/install-plugins` puts a copy beside
// the popup: an Omarchy plugin is a folder of its own, installed as a copy,
// and the plugin folder refuses symlinks.
//
// The store is `deadlines.tsv`, which `pomo deadline` owns: every write goes
// through the CLI, so the file has one writer. One deadline a line:
//
//   id <TAB> due (epoch) <TAB> title <TAB> status <TAB> done_at <TAB> grade <TAB> project <TAB> link
//
// Shorter, older lines (ending after the title, or after the grade) read as
// the CLI reads them.
.pragma library

// The deadlines in the file's order, every status kept: what to leave out
// is the reader's. Columns past the eighth are ignored rather than folded
// into the title: a plugin is installed as a copy, so a newer CLI adding a
// column must not make a stale install show it as words.
function parse(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f.length < 3) continue
    var id = parseInt(f[0], 10)
    var due = parseInt(f[1], 10)
    if (!isFinite(id) || !isFinite(due)) continue
    var status = f.length > 3 ? f[3] : "open"
    if (status !== "done" && status !== "hidden" && status !== "cancelled") status = "open"
    var doneAt = f.length > 4 ? parseInt(f[4], 10) : 0
    out.push({ id: id, due: due, title: f[2], status: status, doneAt: isFinite(doneAt) ? doneAt : 0,
               grade: f.length > 5 ? f[5] : "", project: f.length > 6 ? f[6] : "", link: f.length > 7 ? f[7] : "" })
  }
  return out
}
