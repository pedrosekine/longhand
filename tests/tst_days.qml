import QtQuick
import QtTest
import "../plugin-page/Days.js" as Days

// The sidebar calendar's reading of daily-note file names and months.
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

  function test_index_prefers_configured_name() {
    var idx = Days.index(["2026-10-07", "2026.10.07", "2023-03-08", "notes"], "YYYY.MM.DD")
    compare(idx["2026-10-7"], "2026.10.07")
    compare(idx["2023-3-8"], "2023-03-08")
    compare(Days.stemFor(new Date(2023, 2, 8), "YYYY.MM.DD", idx), "2023-03-08")
    compare(Days.stemFor(new Date(2026, 0, 5), "YYYY.MM.DD", idx), "2026.01.05")
  }

  function test_grid_starts_on_locale_weekday() {
    // October 2026 starts on a Thursday.
    var mon = Days.grid(2026, 9, 1)
    compare(mon[0], null); compare(mon[2], null)
    compare(mon[3].getDate(), 1)
    var sun = Days.grid(2026, 9, 0)
    compare(sun[4].getDate(), 1)
    compare(mon.length, 42)
    compare(mon[3 + 30].getDate(), 31); compare(mon[3 + 31], null)
  }

  function test_month_steps_clamp_the_day() {
    var d = Days.addMonths(new Date(2026, 0, 31), 1)
    compare(d.getMonth(), 1); compare(d.getDate(), 28)
    var e = Days.addMonths(new Date(2026, 0, 15), -1)
    compare(e.getFullYear(), 2025); compare(e.getMonth(), 11)
    compare(Days.addDays(new Date(2026, 9, 31), 1).getMonth(), 10)
  }

}
