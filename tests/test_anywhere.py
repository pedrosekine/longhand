"""What one message can do, from anywhere (docs/agent.md, "One conversation",
slice 4, 2026-11-18): add a task, move a deadline, tick or reopen a box when
the student asks, open something — and only when asked, never from a plan.

Run: python3 tests/test_anywhere.py

Against plan.py directly:
- a task the student asks for: its words and course; not one already open;
  never from a planning pass
- a deadline moved: by its number, to a day within the year, not the day
  it has; it keeps the day it had (`was`), for undoing; each day moved to
  is its own proposal, and one declined does not block another
- a box ticked because the student asked is done at once (`auto`); one
  that only looks done is still a card; a ticked box reopened when asked,
  only among those ticked lately; undoing a tick does not block the next
"""
import datetime as dt
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import plan  # noqa: E402

FAILS = []
TODAY = dt.date.today()


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        FAILS.append(what)


def main() -> int:
    days = [{"date": (TODAY + dt.timedelta(days=i)).isoformat()} for i in range(14)]
    boxes = [{"key": "thesis\t- write the intro", "title": "write the intro", "project": "thesis", "deadline": 61,
              "priority": 0, "steps_under_it": 0, "quiet": False, "age_days": 1, "due": ""}]
    due = dt.datetime.combine(TODAY + dt.timedelta(days=2), dt.time(23, 59))
    deadlines = [{"id": 61, "title": "write the intro", "due": due, "project": "thesis", "linked": True}]
    ticked = [{"key": "thesis\t- book the room", "title": "book the room", "project": "thesis"}]
    fri = (TODAY + dt.timedelta(days=5)).isoformat()

    def v(props, ledger=None, asked=True):
        return plan.validate({"proposals": props, "questions": []}, [], days, ledger or {"next": 1, "items": []}, TODAY,
                             boxes, deadlines, {}, [], ["thesis"], asked=asked, ticked=ticked)[0]

    got = v([{"kind": "task", "title": "email the dean", "project": "#thesis", "why": "asked"},
             {"kind": "task", "title": "write the intro", "why": "already one"}])
    check([(x["kind"], x["title"], x["project"]) for x in got] == [("task", "email the dean", "thesis")],
          f"a task the student asks for, with its course; not one already open ({got})")
    check(v([{"kind": "task", "title": "email the dean"}], asked=False) == [], "…never from a planning pass")

    got = v([{"kind": "move", "deadline": 61, "date": fri, "why": "asked"},
             {"kind": "move", "deadline": 99, "date": fri},
             {"kind": "move", "deadline": 61, "date": (TODAY + dt.timedelta(days=2)).isoformat()},
             {"kind": "move", "deadline": 61, "date": "2040-01-01"}])
    check(len(got) == 1 and got[0]["deadline"] == 61 and got[0]["date"] == fri and got[0]["key"] == boxes[0]["key"]
          and got[0]["was"] == due.strftime("%Y-%m-%d %H:%M"),
          f"a move: by its number, to a day within the year, not the day it has; the day it had kept ({got})")
    old = v([{"kind": "deadline", "moves": "#61", "title": "write the intro", "date": fri}])
    check([x["kind"] for x in old] == ["move"], "…said the older way (a deadline that `moves`), it is a move")
    declined = {"next": 2, "items": [dict(got[0], id=1, status="declined", at="x")]}
    sat = (TODAY + dt.timedelta(days=6)).isoformat()
    check(len(v([{"kind": "move", "deadline": 61, "date": sat}], declined)) == 1,
          "…one declined does not block moving it to another day")
    check(v([{"kind": "move", "deadline": 61, "date": fri}], asked=False) == [], "…never from a planning pass")

    got = v([{"kind": "done", "key": boxes[0]["key"], "asked": True}])
    check(len(got) == 1 and got[0].get("auto"), "a box ticked because the student asked is done at once, and told")
    got = v([{"kind": "done", "key": boxes[0]["key"], "why": "the notes say it happened"}])
    check(len(got) == 1 and not got[0].get("auto"), "…one that only looks done is still a card")
    undone = {"next": 2, "items": [{"id": 1, "kind": "done", "key": boxes[0]["key"], "title": "write the intro",
                                    "status": "undone", "at": "x", "auto": True}]}
    check(len(v([{"kind": "done", "key": boxes[0]["key"], "asked": True}], undone)) == 1,
          "…undoing a tick does not block the next one asked for")
    got = v([{"kind": "undone", "key": "thesis\t- book the room", "why": "asked"},
             {"kind": "undone", "key": "thesis\t- not ticked"}])
    check([(x["kind"], x["title"], x.get("auto")) for x in got] == [("undone", "book the room", True)],
          f"a ticked box reopened when asked, at once; only one ticked lately ({got})")
    print("FAIL" if FAILS else "PASS")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
