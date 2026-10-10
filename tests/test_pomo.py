"""The deadline CLI's contract with the page, against a throwaway state dir.

Run: python3 tests/test_pomo.py
"""
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
        return next(x for x in json.loads(pomo("list", "--json").stdout)["deadlines"] if x["id"] == i)
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
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
