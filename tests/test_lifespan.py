"""The silence clock (agent/lifespan.py): how long an open box is carried
before it goes quiet, what touches it, and that nothing goes without first
counting down.

Run: python3 tests/test_lifespan.py
"""
import datetime as dt
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import lifespan  # noqa: E402
import task as tasklib  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


DAY0 = dt.date(2026, 10, 17)


def box(line: str, written: dt.date, today: dt.date, project: str = "") -> dict:
    t = tasklib.parse(line)
    t["age"] = (today - written).days
    if project and not t["project"]:
        t["project"] = project
    return t


def by_title(rows):
    return {r["title"]: r for r in rows}


def main() -> int:
    path = pathlib.Path(tempfile.mkdtemp(prefix="lifespan-")) / "silence.json"

    def run(today, lines):
        return by_title(lifespan.apply([box(l, w, today, p) for l, w, p in lines], path, today))

    old_note = ("- [ ] an old thought", DAY0 - dt.timedelta(days=20), "dtm")
    young_note = ("- [ ] a thought from yesterday", DAY0 - dt.timedelta(days=1), "dtm")
    old_task = ("- [ ] an old task ⏫", DAY0 - dt.timedelta(days=40), "")
    young_task = ("- [ ] a young task 🔼", DAY0 - dt.timedelta(days=3), "")
    dated = ("- [ ] a dated one 📅 2026-12-01", DAY0 - dt.timedelta(days=60), "")
    later = ("- [ ] later on ⏳ 2026-11-20", DAY0 - dt.timedelta(days=50), "")

    # The clock's first day: nothing goes without counting down first.
    r = run(DAY0, [old_note, young_note, old_task, young_task, dated, later])
    check(r["an old thought"]["away"] == "" and r["an old thought"]["warn"]
          and r["an old thought"]["left"] == 2,
          f"a note box past its 7 days starts in its last quarter, not gone ({r['an old thought']['left']})")
    check(r["an old task"]["away"] == "" and r["an old task"]["left"] == 8,
          f"a task past its 30 days gets the last quarter of 30 ({r['an old task']['left']})")
    check(r["a thought from yesterday"]["left"] == 6 and not r["a thought from yesterday"]["warn"],
          "a box written yesterday has 6 days left, no countdown yet")
    check(r["a young task"]["left"] == 27, "a task written 3 days ago has 27 left")
    check(r["a dated one"]["life"] == 0 and r["a dated one"]["away"] == "",
          "a deadline never decays by silence — it is judged by its date")
    check(r["later on"]["left"] == 30 + (dt.date(2026, 11, 20) - DAY0).days,
          "a do-date ahead: the clock runs from that day")
    check(path.exists(), "the clock is kept in the layer")

    # Three days on: the countdown ran out.
    d3 = DAY0 + dt.timedelta(days=3)
    new_in_old = ("- [ ] written into an old note since", DAY0 - dt.timedelta(days=30), "")
    r = run(d3, [old_note, young_note, old_task, new_in_old])
    check(r["an old thought"]["away"] == "quiet", f"…and it goes quiet when it does ({r['an old thought']['left']})")
    check(r["a thought from yesterday"]["left"] == 3 and not r["a thought from yesterday"]["warn"],
          "a note box with 3 days left is not counting down yet (its last quarter is 2 days)")
    check(r["written into an old note since"]["left"] == 7 - 3,
          f"a box the clock has not met is new as of the last look, not of its old note ({r['written into an old note since']['left']})")

    # The same words in a later note are a touch.
    again = ("- [ ] an old thought", d3, "dtm")
    r = run(d3, [old_note, again])
    check(r["an old thought"]["away"] == "" and r["an old thought"]["left"] == 7,
          "the same words written again today bring it back with a full life")
    other_project = ("- [ ] an old thought", d3, "intsem")
    rows = lifespan.apply([box(*old_note[:2], d3, "dtm"), box(*other_project[:2], d3, "intsem")], path, d3)
    check(rows[0]["key"] != rows[1]["key"], "…but only in the same project")

    # Not now, by hand; and kept on purpose.
    key = run(d3, [young_note])["a thought from yesterday"]["key"]
    lifespan.touch(path, key, "shelve", d3)
    r = run(d3, [young_note])
    check(r["a thought from yesterday"]["away"] == "shelved", "s puts a box aside")
    lifespan.touch(path, key, "keep", d3 + dt.timedelta(days=1))
    r = run(d3 + dt.timedelta(days=1), [young_note])
    check(r["a thought from yesterday"]["away"] == "" and r["a thought from yesterday"]["left"] == 7,
          "keeping it brings it back, its clock started again")

    # The note's own words decide what is a task: a priority given later
    # lengthens the life.
    promoted = ("- [ ] a thought from yesterday ⏫", DAY0 - dt.timedelta(days=1), "dtm")
    r = run(d3 + dt.timedelta(days=1), [promoted])
    check(r["a thought from yesterday"]["life"] == 30 and r["a thought from yesterday"]["key"] == key,
          "a priority makes it a task, same box, 30 days")

    # A clock file that cannot be read is a first day, not an empty one.
    path.write_text("{not json")
    r = run(d3, [old_note])
    check(r["an old thought"]["away"] == "" and r["an old thought"]["warn"],
          "an unreadable clock never sends a box away unwarned")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
