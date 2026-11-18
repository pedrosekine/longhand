"""How Longhand feels, once a week (agent/checkin.py; `longhand-agent checkin`).

Run: python3 tests/test_checkin.py

- the eight UEQ-S pairs; a week's answers scored as the questionnaire does:
  each step 1..7 as -3..+3, practical the first four, pleasant the last four
- a week is due until either machine answered or skipped it; each machine
  writes a log of its own; a line cut short mid-sync is passed over
- the agent's share of its proposals acted on that week sits beside it (not
  documents from Downloads, not what it did on its own)
- the command: due, then --answers keeps the week, --skip skips it, a wrong
  answer is refused and nothing is written
"""
import datetime as dt
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import checkin  # noqa: E402

FAILS = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        FAILS.append(what)


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="checkin-test-"))
    try:
        folder = tmp / "checkins"
        mon = dt.date(2026, 11, 16)                       # a Monday, ISO week 47
        check(len(checkin.ITEMS) == 8 and checkin.ITEMS[0] == ("obstructive", "supportive")
              and checkin.ITEMS[7] == ("usual", "leading edge"), "the eight UEQ-S pairs, negative word first")
        s = checkin.scores([7, 7, 7, 7, 1, 1, 1, 1])
        check(s == {"pragmatic": 3.0, "hedonic": -3.0, "overall": 0.0}, f"scored as UEQ-S: -3..+3, practical then pleasant ({s})")

        st = checkin.status(folder, mon, [])
        check(st["due"] and st["week"] == "2026-W47" and st["weeks"] == [], "a week never answered is due")
        checkin.save(folder, "air", mon, "2026-11-16T09:00:00", None, True)
        check(not checkin.status(folder, mon + dt.timedelta(days=4), [])["due"], "skipped on one machine: not due on any, all week")
        check(checkin.status(folder, mon + dt.timedelta(days=7), [])["due"], "…due again the next Monday")
        checkin.save(folder, "xmg", mon + dt.timedelta(days=7), "2026-11-23T10:00:00", [6, 6, 5, 6, 4, 5, 6, 5], False)
        check(sorted(p.name for p in folder.iterdir()) == ["air.jsonl", "xmg.jsonl"], "each machine writes a log of its own")
        with open(folder / "air.jsonl", "a") as f:
            f.write('{"week": "2026-W48", "answ')
        ledger = [{"kind": "do-date", "status": "accepted", "at": "2026-11-24T08:00:00"},
                  {"kind": "question", "status": "expired", "at": "2026-11-25T08:00:00"},
                  {"kind": "steps", "status": "superseded", "at": "2026-11-26T08:00:00"},
                  {"kind": "question", "status": "answered", "at": "2026-11-26T09:00:00"},
                  {"kind": "file", "status": "accepted", "at": "2026-11-24T08:00:00"},
                  {"kind": "do-date", "status": "told", "auto": True, "at": "2026-11-24T08:00:00"},
                  {"kind": "do-date", "status": "accepted", "at": "2026-11-17T08:00:00"}]
        st = checkin.status(folder, mon + dt.timedelta(days=8), ledger)
        w47, w48 = st["weeks"]
        check(w47["skipped"] and "pragmatic" not in w47, "a skipped week says so, with no scores")
        check(w48["pragmatic"] == 1.75 and w48["hedonic"] == 1.0 and not st["due"],
              f"a kept week's scores, the cut line passed over ({w48})")
        check(w48["acted"] == {"made": 4, "acted": 2, "share": 0.5},
              f"the agent's share acted on that week, not documents nor what it did itself ({w48['acted']})")
        check(w47["acted"]["made"] == 1, "…and for a skipped week too")
        try:
            checkin.save(folder, "xmg", mon, "x", [1, 2, 3], False)
            check(False, "a wrong answer is refused")
        except ValueError:
            check(True, "a wrong answer is refused")

        # The command, on a vault of its own.
        vault = tmp / "vault"
        vault.mkdir()
        cfg = tmp / "config.json"
        cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                                   "agentDir": "agents/longhand"}))
        env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"),
                   XDG_CONFIG_HOME=str(tmp / "cfg"), LONGHAND_HOST="here")
        run = lambda *a: subprocess.run([sys.executable, str(ROOT / "agent" / "longhand-agent"), "checkin", *a],  # noqa: E731
                                        capture_output=True, text=True, env=env)
        r = run()
        check(r.returncode == 0 and json.loads(r.stdout)["due"], f"the command: this week is due ({r.stderr.strip()})")
        r = run("--answers", "4,4,9,4,4,4,4,4")
        logs = vault / "agents" / "longhand" / "checkins"
        check(r.returncode != 0 and not logs.exists(), "…a step out of 1..7 is refused, nothing written")
        r = run("--answers", "5,5,5,5,3,3,3,3")
        check(r.returncode == 0 and (logs / "here.jsonl").is_file(), "…--answers keeps the week in this machine's log")
        d = json.loads(run().stdout)
        check(not d["due"] and d["weeks"][-1]["pragmatic"] == 1.0 and d["weeks"][-1]["hedonic"] == -1.0,
              f"…not due now, the week scored ({d['weeks'][-1]})")
    finally:
        shutil.rmtree(tmp)
    print("FAIL" if FAILS else "PASS")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
