import QtQuick
import QtTest
import "../plugin-page/Dates.js" as Dates

// Date phrases read in the page, the way `pomo deadline when` reads them.
// "Now" is fixed: Tuesday 13 October 2026, 08:57.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_dates.qml
TestCase {
  name: "Dates"
  readonly property var now: new Date(2026, 9, 13, 8, 57, 30)

  function iso(s) { var r = Dates.read(s, now); return r ? r.iso : null }

  function test_days_and_months_from_the_notes() {
    compare(iso("30 oct"), "2026-10-30 23:59")
    compare(iso("by 30 nov"), "2026-11-30 23:59")
    compare(iso("07 dec"), "2026-12-07 23:59")
    compare(iso("15 jan"), "2027-01-15 23:59")          // past this year: next year's
    compare(iso("19th of Feb"), "2027-02-19 23:59")
    compare(iso("the 8th of Feb"), "2027-02-08 23:59")
    compare(iso("Oct 30"), "2026-10-30 23:59")
    compare(iso("12 oct"), "2027-10-12 23:59")          // yesterday by name: next year
    compare(iso("13 oct"), "2026-10-13 23:59")          // today stays today
    compare(iso("1 march 2026"), "2026-03-01 23:59")    // a year written is kept
    compare(iso("2026-10-30"), "2026-10-30 23:59")
  }

  function test_weekdays_like_gnu_date() {
    compare(iso("tuesday"), "2026-10-13 23:59")         // today is a Tuesday
    compare(iso("next tuesday"), "2026-10-20 23:59")
    compare(iso("next monday"), "2026-10-19 23:59")     // the Monday after today
    compare(iso("fri"), "2026-10-16 23:59")
    compare(iso("this friday"), "2026-10-16 23:59")
  }

  function test_relative_days_and_times() {
    compare(iso("today"), "2026-10-13 23:59")
    compare(iso("today (2026-10-13)"), "2026-10-13 23:59")   // an aside is dropped
    compare(iso("tomorrow"), "2026-10-14 23:59")
    compare(iso("tomorrow 9:00"), "2026-10-14 09:00")
    compare(iso("fri 17:00"), "2026-10-16 17:00")
    compare(iso("friday at 5pm"), "2026-10-16 17:00")
    compare(iso("30 oct 17:00"), "2026-10-30 17:00")    // GNU date refuses this one
    compare(iso("17:00"), "2026-10-13 17:00")
  }

  function test_offsets_keep_the_clock() {
    compare(iso("3d"), "2026-10-16 08:57")
    compare(iso("in 3 days"), "2026-10-16 08:57")
    compare(iso("5h"), "2026-10-13 13:57")
    compare(iso("2w"), "2026-10-27 08:57")              // across the clock change, the same wall time
    compare(iso("next week"), "2026-10-20 08:57")
  }

  function test_not_dates() {
    compare(iso("phone"), null)
    compare(iso("done"), null)
    compare(iso("22nd"), null)
    compare(iso("31 feb"), null)
    compare(iso("Smith"), null)
    compare(iso("friday please"), null)
    compare(iso("17"), null)
    compare(iso(""), null)
  }
}
