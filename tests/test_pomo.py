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
import time

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
    # A config folder of its own: pomo reads the vault's deadline logs from it.
    env = dict(os.environ, XDG_STATE_HOME=state, XDG_CONFIG_HOME=tempfile.mkdtemp(prefix="pomo-test-cfg-"))
    env.pop("LONGHAND_CONFIG", None)

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
    # "at" before the time, as the agent's cards write it (2026-11-03).
    for phrase, want in (("6 Nov 2026 at 23:59", "2026-11-06 23:59"), ("4 Feb 2027 at 10:30", "2027-02-04 10:30"),
                         ("friday at 5pm", "17:00")):
        r = pomo("when", *phrase.split())
        got = dt.datetime.fromtimestamp(int(r.stdout.split("\t")[0])).strftime("%Y-%m-%d %H:%M") if r.returncode == 0 else ""
        check(got.endswith(want), f"when {phrase!r} is {want} ({got or r.stderr.strip()})")
    # Dotted, day first (2026-11-15): with a year as written, without one
    # this year's, or next year's once over; a day that does not exist is refused.
    ahead = today + dt.timedelta(days=3)
    for phrase, want in ((ahead.strftime("%d.%m"), ahead.strftime("%Y-%m-%d 23:59")),
                         (ahead.strftime("%d.%m."), ahead.strftime("%Y-%m-%d 23:59")),
                         (past.strftime("%d.%m") if past.year == today.year else "", past.replace(year=past.year + 1).strftime("%Y-%m-%d 23:59")),
                         ("12.11.2026 17:00", "2026-11-12 17:00"), ("12.11.26 at 9:30", "2026-11-12 09:30"),
                         ("3.2.2027", "2027-02-03 23:59")):
        if not phrase:
            continue
        r = pomo("when", *phrase.split())
        got = dt.datetime.fromtimestamp(int(r.stdout.split("\t")[0])).strftime("%Y-%m-%d %H:%M") if r.returncode == 0 else ""
        check(got == want, f"when {phrase!r} is {want} ({got or r.stderr.strip()})")
    check(pomo("when", "31.02.2027").returncode != 0, "a dotted day that does not exist is refused")
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

    # Windows refuses to replace a file another process has open: the popup
    # and longhand-check read the store while a tick is written. Held open
    # until pomo has its new copy ready and is waiting to put it in place,
    # then let go: the tick still lands.
    if os.name == "nt":
        r = pomo("add", "Held open", "friday")
        held_id = int(r.stdout.split("#")[1].split()[0])
        store = pathlib.Path(state) / "longhand" / "deadlines.tsv"

        def copies():  # pomo's new store, not yet in place (deadlines.tsv.lock is its lock)
            return [f for f in store.parent.glob("deadlines.tsv.*") if f.suffix != ".lock"]
        holder = open(store, "rb")
        p = subprocess.Popen([sys.executable, "-X", "utf8", str(ROOT / "cli" / "pomo.py"), "deadline", "done", str(held_id)],
                             env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        until = time.monotonic() + 20
        while p.poll() is None and not copies() and time.monotonic() < until:
            time.sleep(0.01)
        waited = p.poll() is None
        time.sleep(0.1)
        holder.close()
        said = p.communicate(timeout=20)
        check(waited and p.returncode == 0 and by_id(held_id)["status"] == "done",
              f"a tick written while the store is open elsewhere lands once it is let go ({p.returncode}, {said[1].strip()[-160:]})")
        check(not copies(), "…leaving no copy behind")
    # Another machine's numbers, in the vault's logs, are never handed out
    # here (2026-11-24: a new machine's first deadline took #1 and was folded
    # into a different #1). Both programs, the bash one and the port.
    for program in ([str(POMO)], [sys.executable, "-X", "utf8", str(ROOT / "cli" / "pomo.py")]):
        fresh = tempfile.mkdtemp(prefix="pomo-test-fresh-")
        cfg = pathlib.Path(tempfile.mkdtemp(prefix="pomo-test-cfg-"))
        vault = pathlib.Path(tempfile.mkdtemp(prefix="pomo-test-vault-"))
        logs = vault / "agents" / "longhand" / "deadlines"
        logs.mkdir(parents=True)
        (logs / "other.jsonl").write_text('{"at": 1.0, "host": "other", "id": 70, "set": {"title": "Theirs"}}\n'
                                          '{"at": 2.0, "host": "other", "id": 9, "set": {"title": "Older"}}\n')
        (cfg / "longhand").mkdir()
        (cfg / "longhand" / "config.json").write_text(json.dumps({"vault": str(vault)}))
        env2 = dict(env, XDG_STATE_HOME=fresh, XDG_CONFIG_HOME=str(cfg))
        r = subprocess.run(program + ["deadline", "add", "Mine", "friday"], capture_output=True, text=True, env=env2)
        check(r.returncode == 0 and "deadline #71" in r.stdout,
              f"{pathlib.Path(program[-1]).name}: a new store numbers past the other machines' logs ({r.stdout.strip()}{r.stderr.strip()})")
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
