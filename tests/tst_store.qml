import QtQuick
import QtTest
import "../plugin-page/Store.js" as Store

// The deadline store as the plugins read it (Store.js, 2026-10-30: one
// copy for the page and the popup). The CLI's side is tests/test_pomo.py.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_store.qml
TestCase {
  name: "Store"

  function test_a_whole_line() {
    var d = Store.parse("6\t1792162800\tessay draft\topen\t0\t\tintsem\t[[2026.10.09#^d6]]")
    compare(d.length, 1)
    compare(d[0], { id: 6, due: 1792162800, title: "essay draft", status: "open", doneAt: 0,
                    grade: "", project: "intsem", link: "[[2026.10.09#^d6]]" })
  }

  function test_older_shorter_lines() {
    var d = Store.parse("1\t1792162800\tjust a title\n2\t1792162800\tgraded\tdone\t1792100000\t1.3")
    compare(d[0].status, "open"); compare(d[0].doneAt, 0); compare(d[0].grade, ""); compare(d[0].project, ""); compare(d[0].link, "")
    compare(d[1].status, "done"); compare(d[1].doneAt, 1792100000); compare(d[1].grade, "1.3"); compare(d[1].link, "")
  }

  function test_every_status_kept_in_the_file_s_order() {
    var d = Store.parse("3\t30\tc\tcancelled\n1\t10\ta\thidden\n2\t20\tb\tdone\t5\n4\t40\td\tsomething new")
    compare(d.map(function (x) { return x.id + ":" + x.status }), ["3:cancelled", "1:hidden", "2:done", "4:open"])   // a status it does not know reads as open
  }

  function test_what_is_not_a_deadline_is_skipped() {
    var d = Store.parse("\nnot a line\nx\t10\tno id\n5\tsoon\tno due\n7\t70\tkept\n")
    compare(d.map(function (x) { return x.id }), [7])
    compare(Store.parse(""), [])
    compare(Store.parse(undefined), [])
    compare(Store.parse("8\t80\tdone, no day\tdone\tnever").map(function (x) { return x.doneAt }), [0])
  }

  // A newer CLI's ninth column is not read into the title, or anywhere.
  function test_a_newer_column_is_ignored() {
    var d = Store.parse("9\t90\ttitle\topen\t0\t\t\t\tsomething later")
    compare(d[0].title, "title")
    compare(Object.keys(d[0]).length, 8)
  }
}
