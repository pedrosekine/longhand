import QtQuick
import QtTest
import "../plugin-page"
import "../plugin-page/PdfMarks.js" as Marks

// The paper's room (Paper.qml) and what was read on a day (ReadToday.qml),
// against a stand-in page: the rows and their order, which questions
// wait, attaching marks, the strip's and the list's keys, the READ list's.
// The live page test (tests/page/run.py) drives them in the real page.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_paper.qml
Item {
  id: top

  // What the two read from the page, and what they ask of it.
  Item {
    id: fakePage
    property bool pdfShown: true
    property string pdfRel: "lit/Smith 2020.pdf"
    property bool noteRoom: true
    property string paneHeld: ""
    property var noteTalk: null
    property var dayMention: null
    property int dayMentionFocus: 0
    property var calFocus: new Date(2026, 10, 16)
    property int projFocus: -1
    property var sent: []
    property var opened: []
    property string hintSaid: ""
    property bool closed: false
    property var noteService: QtObject { property bool configured: true }
    property Item dayPaneItem: Item {
      property Item paperKeysRef: Item {}
      property Item dayFieldRef: Item {}
    }
    property Item pdfItem: Item {
      property string readPath: "/bin/true"
      property string picked: ""
      property var shownMark: ""
      property Item keysRef: pdfKeys
      property var read: ({ text: true, private: false, marks: [
        { id: "h1", kind: "h", page: 1, text: "Retrieval changes the memory", note: "" },
        { id: "h2", kind: "q", page: 2, text: "Sessions a day apart", note: "does sleep matter?" },
        { id: "h3", kind: "q", page: 3, text: "The closing argument", note: "" }] })
      function markById(id) { for (var i = 0; i < read.marks.length; i++) if (read.marks[i].id === id) return read.marks[i]; return null }
      function showMark(id) { shownMark = id }
    }
    function anywhereKey(e) { return false }
    function chatSelectionKey(e, hasOwn) { return false }
    function sendDay(t) { sent = sent.concat([t]); return true }
    function showHint(t) { hintSaid = t }
    function used() {}
    function openRoom() { noteRoom = true }
    function closeDay() { closed = true }
    function remember() {}
    function openPdf(rel) { opened = opened.concat([rel]) }
    function readDaysRun() { return true }
  }

  // The PDF's keys, in the window so they can take the focus.
  Item { id: pdfKeys }
  Item { id: listKeys }

  Paper { id: paper; page: fakePage }
  ReadToday { id: readToday; page: fakePage }

  function key(k, mods) { return { key: k, text: "", modifiers: mods || 0 } }

  TestCase {
    name: "Paper"
    when: windowShown

    function init() {
      fakePage.noteTalk = null
      fakePage.sent = []
      paper.marks = []
      paper.kept = []
      paper.filter = "all"
      paper.at = -1
      paper.listing = true
    }

    function test_rows_and_what_waits() {
      compare(paper.room, true)
      compare(paper.rows.map(function (m) { return m.id }), ["h1", "h2", "h3"], "page order")
      compare(paper.waiting.map(function (m) { return m.id }), ["h2", "h3"], "every question waits at first")
      // h3 asked about and answered: it waits no more, and the questions
      // strip puts the waiting one first.
      fakePage.noteTalk = { turns: [{ role: "student", text: "?", marks: ["h3"] }, { role: "agent", text: "because" }] }
      compare(paper.waiting.map(function (m) { return m.id }), ["h2"])
      compare(paper.markState(paper.page.pdfItem.markById("h3")), "answered")
      compare(paper.markState(paper.page.pdfItem.markById("h1")), "")
      paper.filter = "q"
      compare(paper.rows.map(function (m) { return m.id }), ["h2", "h3"], "the waiting one first")
      compare(paper.count("q"), 2)
      // An answer that failed answers nothing.
      fakePage.noteTalk = { turns: [{ role: "student", text: "?", marks: ["h3"] }, { role: "agent", text: "", error: "x" }] }
      compare(paper.waiting.length, 2)
    }

    function test_the_list_keys() {
      // The first row is the paper as a whole: Enter goes to the chat
      // with nothing attached.
      compare(paper.at, -1)
      verify(paper.keyPressed(top.key(Qt.Key_Return)))
      compare(paper.listing, false)
      compare(paper.marks, [])
      paper.listing = true
      // Down to a mark: the PDF goes to it; Enter attaches it.
      paper.keyPressed(top.key(Qt.Key_Down))
      compare(paper.at, 0)
      compare(fakePage.pdfItem.shownMark, "h1")
      paper.keyPressed(top.key(Qt.Key_Return))
      compare(paper.marks, ["h1"])
      // Space keeps several; Enter attaches the ones kept.
      paper.listing = true
      paper.marks = []
      paper.keyPressed(top.key(Qt.Key_Down))
      paper.keyPressed(top.key(Qt.Key_Space))
      paper.keyPressed(top.key(Qt.Key_Down))
      paper.keyPressed(top.key(Qt.Key_Space))
      compare(paper.kept, ["h2", "h3"])
      paper.keyPressed(top.key(Qt.Key_Return))
      compare(paper.marks, ["h2", "h3"])
      compare(paper.kept, [])
      // The strip.
      paper.listing = true
      paper.keyPressed(top.key(Qt.Key_3))
      compare(paper.filter, "q")
      compare(paper.at, -1)
      paper.keyPressed(top.key(Qt.Key_1))
      compare(paper.filter, "all")
    }

    function test_attach_and_ask_waiting() {
      paper.attach("h2")
      paper.attach("h2")
      paper.attach("nope")
      compare(paper.marks, ["h2"], "once, and only a mark that exists")
      compare(paper.head("h2"), "p. 2 “Sessions a day apart”")
      paper.marks = []
      paper.keyPressed(top.key(Qt.Key_Return, Qt.ControlModifier))
      compare(fakePage.sent.length, 1)
      verify(fakePage.sent[0].indexOf("- h2: does sleep matter?") >= 0 && fakePage.sent[0].indexOf("- h3") >= 0,
             "every waiting question, by its name, with the reader's words")
      compare(paper.listing, false)
    }

    // A click on a row, or Right, takes the keys to the mark in the PDF,
    // where m/q/n/x act on it (2026-11-16).
    function test_a_row_to_the_pdf() {
      paper.edit(1)
      compare(paper.at, 1)
      compare(fakePage.pdfItem.shownMark, "h2", "picked in the PDF")
      tryVerify(function () { return fakePage.pdfItem.keysRef.activeFocus }, 1000, "the keys go with it")
      fakePage.pdfItem.shownMark = ""
      listKeys.forceActiveFocus()
      paper.at = 0
      verify(paper.keyPressed(top.key(Qt.Key_Right)))
      compare(fakePage.pdfItem.shownMark, "h1", "Right does the same")
      fakePage.pdfItem.shownMark = ""
      paper.at = -1
      listKeys.forceActiveFocus()
      verify(paper.keyPressed(top.key(Qt.Key_Right)))
      compare(fakePage.pdfItem.shownMark, "", "the whole paper: nothing to edit")
    }

    function test_a_new_pdf_starts_afresh() {
      paper.marks = ["h1"]; paper.at = 2; paper.filter = "q"; paper.listing = false
      fakePage.pdfRel = "lit/Other.pdf"
      compare(paper.marks, []); compare(paper.at, -1); compare(paper.filter, "all"); compare(paper.listing, true)
      fakePage.pdfRel = "lit/Smith 2020.pdf"
    }
  }

  // Which mark a click on a page picks (PdfMarks.js): a word highlighted
  // inside a question's sentence.
  TestCase {
    name: "PdfMarks"
    readonly property var marks: [
      { id: "q1", boxes: [{ page: 1, rects: [[10, 100, 300, 12], [10, 114, 300, 12]] }] },
      { id: "h1", boxes: [{ page: 1, rects: [[120, 114, 60, 12]] }] },
      { id: "h2", boxes: [{ page: 2, rects: [[120, 114, 60, 12]] }] }]

    function test_the_smallest_first_then_larger_then_none() {
      compare(Marks.under(marks, 1, 150, 120), ["h1", "q1"])
      compare(Marks.pick(marks, 1, 150, 120, ""), "h1", "the word, not the sentence round it")
      compare(Marks.pick(marks, 1, 150, 120, "h1"), "q1", "again: the sentence")
      compare(Marks.pick(marks, 1, 150, 120, "q1"), "", "again: let go")
      compare(Marks.pick(marks, 1, 20, 104, ""), "q1", "where only the question is")
      compare(Marks.pick(marks, 1, 20, 104, "q1"), "", "a lone mark again: let go")
      compare(Marks.pick(marks, 1, 150, 120, "h2"), "h1", "another picked elsewhere")
      compare(Marks.pick(marks, 1, 500, 500, "h1"), "h1", "no mark there: nothing changes")
      compare(Marks.under(marks, 1, 309, 99, 1.5), ["q1"], "a little outside still counts")
    }

    // Painted with no layer (2026-11-17): every point covered once, the
    // later mark where two cross, a lone line one rounded piece.
    function cover(pieces, x, y) {
      var n = 0, kind = ""
      pieces.forEach(function (p) { if (x > p.x && x < p.x + p.w && y > p.y && y < p.y + p.h) { n++; kind = p.kind } })
      return { n: n, kind: kind }
    }
    function test_paint_never_twice() {
      var rects = [{ kind: "q", r: [10, 100, 300, 12] }, { kind: "q", r: [10, 111, 300, 12] }, { kind: "h", r: [120, 111, 60, 12] }]
      var pieces = Marks.paint(rects, 0)
      for (var x = 11; x < 310; x += 7)
        for (var y = 101.25; y < 123; y += 0.5)
          compare(cover(pieces, x, y).n, 1, "covered once at " + x + "," + y)
      compare(cover(pieces, 150, 118).kind, "h", "the later mark shows where they cross")
      compare(cover(pieces, 150, 105).kind, "q")
      compare(cover(pieces, 150, 111.5).kind, "h", "…also where the lines overlap")
      verify(pieces.every(function (p) { return !p.round }), "pieces that meet are square")
      var lone = Marks.paint([{ kind: "h", r: [10, 10, 50, 12] }, { kind: "q", r: [200, 10, 50, 12] }], 1.5)
      compare(lone.length, 2)
      verify(lone[0].round && lone[1].round, "apart: each rounded")
      compare(lone[0].x, 8.5, "widened by the pad")
      compare(lone[0].w, 53)
      compare(Marks.paint([], 1).length, 0)
      compare(Marks.paint([{ kind: "h", r: [0, 0, 0, 10] }]).length, 0, "nothing of no size")
    }
  }

  TestCase {
    name: "ReadToday"
    when: windowShown

    function test_the_days_list() {
      readToday.days = { "2026-11-16": [{ pdf: "lit/a.pdf", title: "a", h: 2, q: 1 }, { pdf: "lit/b.pdf", title: "b", h: 1, q: 0 }] }
      compare(readToday.rows.map(function (r) { return r.title }), ["a", "b"], "the calendar's day")
      compare(readToday.summary(readToday.rows[0]), "2 highlights, 1 question")
      compare(readToday.summary(readToday.rows[1]), "1 highlight")
      readToday.at = 0
      readToday.keyPressed(top.key(Qt.Key_Down))
      compare(readToday.at, 1)
      readToday.keyPressed(top.key(Qt.Key_Return))
      compare(fakePage.opened, ["lit/b.pdf"], "Enter opens the paper")
      readToday.keyPressed(top.key(Qt.Key_Tab))
      compare(readToday.at, -1)
      compare(fakePage.projFocus, 0, "Tab goes on to the projects")
      readToday.at = 1
      fakePage.calFocus = new Date(2026, 10, 15)
      compare(readToday.at, -1, "another day: out of the list")
      compare(readToday.rows, [])
    }
  }
}
