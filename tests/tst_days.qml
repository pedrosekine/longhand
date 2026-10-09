import QtQuick
import QtTest
import "../plugin-page/Days.js" as Days

// The sidebar's reading of daily-note file names.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
TestCase {
  name: "Days"

  function test_parse_configured_and_older_formats() {
    var a = Days.parse("2026.10.09", "YYYY.MM.DD")
    compare(a.configured, true)
    compare(a.date.getFullYear(), 2026); compare(a.date.getMonth(), 9); compare(a.date.getDate(), 9)
    var b = Days.parse("2023-03-08", "YYYY.MM.DD")
    compare(b.configured, false)
    compare(b.date.getMonth(), 2)
    compare(Days.parse("Feedback Peter about Sparkasse", "YYYY.MM.DD"), null)
    compare(Days.parse("2026.02.30", "YYYY.MM.DD"), null)   // not a day
  }

  function test_rows_newest_first_by_month() {
    var r = Days.rows(["2026.09.30", "2026.10.07", "2023-03-08", "notes", "2026.10.09"], "YYYY.MM.DD", "2026.10.09")
    var kinds = r.map(function (x) { return x.kind === "month" ? x.label : x.stem })
    compare(kinds, ["OCTOBER", "2026.10.09", "2026.10.07", "SEPTEMBER", "2026.09.30", "MARCH 2023", "2023-03-08"])
    compare(r[1].today, true)
    compare(r[1].label, "Fri 9")
  }

  function test_today_listed_before_its_file_exists() {
    var r = Days.rows(["2026.10.07"], "YYYY.MM.DD", "2026.10.09")
    compare(r[1].stem, "2026.10.09")
  }

  function test_same_day_in_two_formats_listed_once() {
    var r = Days.rows(["2026.10.07", "2026-10-07"], "YYYY.MM.DD", "")
    compare(r.length, 2)
    compare(r[1].stem, "2026.10.07")
  }
}
