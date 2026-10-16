"""The deadline CLI's contract with the page, against a throwaway state dir.

Run: python3 tests/test_pomo.py
"""
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
POMO = ROOT / "cli" / "pomo"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    state = tempfile.mkdtemp(prefix="pomo-test-")
    env = dict(os.environ, XDG_STATE_HOME=state)

    def pomo(*args):
        return subprocess.run([str(POMO), "deadline", *args], capture_output=True, text=True, env=env)

    r = pomo("add", "Chapter 2 draft", "--project", "thesis", "friday", "17:00")
    check(r.returncode == 0 and "deadline #1" in r.stdout and "thesis" in r.stdout, f"add with --project ({r.stdout.strip()})")
    r = pomo("add", "Old habit", "--subject", "stats", "tomorrow")
    check(r.returncode == 0 and "deadline #2" in r.stdout, "--subject still accepted")
    def by_id(i):
        return next(x for x in json.loads(pomo("list", "--all", "--json").stdout)["deadlines"] if x["id"] == i)
    check(by_id(1)["project"] == "thesis" and "subject" not in by_id(1), "JSON says project")
    check([x["id"] for x in json.loads(pomo("list", "--json", "--project", "stats").stdout)["deadlines"]] == [2], "list filters by project")
    r = pomo("set", "1", "--project", "")
    check(by_id(1)["project"] == "", "empty --project clears it")

    r = pomo("when", "fri", "17:00")
    ts, text = r.stdout.strip().split("\t")
    check(r.returncode == 0 and ts.isdigit() and text.endswith("17:00"), f"when reads a phrase ({r.stdout.strip()})")
    r = pomo("when", "next", "monday")
    check(r.returncode == 0 and r.stdout.strip().endswith("23:59"), "a bare day lands at its end")
    r = pomo("when", "phone")
    check(r.returncode != 0, "a non-date is refused")
    # A day and month already past this year are next year's; with a year, as written.
    today = dt.date.today()
    past = today - dt.timedelta(days=1)
    for phrase, want in ((past.strftime("%d %b"), past.replace(year=past.year + 1) if past.year == today.year else past),
                         (today.strftime("%d %b"), today),
                         (past.strftime("%d %b %Y"), past)):
        r = pomo("when", *phrase.split())
        got = dt.datetime.fromtimestamp(int(r.stdout.split("\t")[0])).date() if r.returncode == 0 else None
        check(got == want, f"when {phrase!r} is {want} ({got})")
    # Dates as written: ordinals, "of", and a month ending in h/d/w is not "3h"/"3d".
    for phrase in ("19th of Feb", "the 8th of Feb", "1st march", "1 march"):
        r = pomo("when", *phrase.split())
        check(r.returncode == 0 and r.stdout.strip().endswith("23:59"), f"when {phrase!r} reads as a day ({r.stdout.strip() or r.stderr.strip()})")
    r = pomo("when", "22nd")
    check(r.returncode != 0, "a bare ordinal is refused, not read as 22:00")
    r = pomo("when", "3d")
    check(r.returncode == 0 and not r.stdout.strip().endswith("23:59"), "3d is still three days from now")
    # Writers racing: eight adds at once must give eight rows, eight ids.
    procs = [subprocess.Popen([str(POMO), "deadline", "add", f"race {i}", "friday"], env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for i in range(8)]
    for p in procs:
        p.wait()
    ids = [x["id"] for x in json.loads(pomo("list", "--json").stdout)["deadlines"] if x["title"].startswith("race")]
    check(len(ids) == 8 and len(set(ids)) == 8, f"concurrent adds keep every row and id ({sorted(ids)})")

    # Cancelled: its line is gone (docs/tasks.md). History, off every list,
    # and brought back as it was.
    r = pomo("cancel", "1")
    check(r.returncode == 0 and by_id(1)["status"] == "cancelled", "cancel keeps the deadline, as cancelled")
    check(all(x["id"] != 1 for x in json.loads(pomo("list", "--json").stdout)["deadlines"]), "…off the list without --all")
    check("1 ×" in pomo("list", "--all").stdout.replace("  ", " "), "…marked × with --all")
    r = pomo("done", "1", "--at", "1790000000")
    check(r.returncode == 0 and by_id(1)["status"] == "done" and by_id(1)["done_at"] == 1790000000,
          "done --at brings it back with the time it was really done")
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
