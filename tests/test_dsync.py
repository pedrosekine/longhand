"""The deadline store, the same on two machines (agent/dsync.py): two
stores (two XDG_STATE_HOMEs), one vault, the real `pomo` and
`longhand-check`, each run as its own machine (LONGHAND_HOST). The vault is
shared at once, as if the sync tool were instant, except where a test holds
a note back.

Run: python3 tests/test_dsync.py
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
CHECK = ROOT / "cli" / "longhand-check"
sys.path.insert(0, str(ROOT / "agent"))
import dsync  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def units() -> None:
    # Two seeds that disagree: the same answer whichever is read first.
    a = {"at": 0, "host": "air", "id": 1, "set": {"status": "done", "done_at": 200, "grade": "", "title": "x"}}
    b = {"at": 0, "host": "xmg", "id": 1, "set": {"status": "done", "done_at": 100, "grade": "1.3", "title": "x"}}
    c = {"at": 0, "host": "air", "id": 2, "set": {"status": "open"}}
    d = {"at": 0, "host": "xmg", "id": 2, "set": {"status": "done"}}
    m1, m2 = dsync.merge([a, b, c, d]), dsync.merge([d, c, b, a])
    check(m1 == m2, "seeds settle the same whatever the order")
    check(m1[1]["done_at"] == 100 and m1[1]["grade"] == "1.3" and m1[2]["status"] == "done",
          "…the earliest time it was done, a grade over none, done over open")
    # A real change beats any seed; the newest change wins, field by field.
    e = {"at": 50.0, "host": "air", "id": 1, "set": {"grade": ""}}
    f = {"at": 60.0, "host": "xmg", "id": 1, "set": {"title": "y"}}
    m = dsync.merge([a, b, e, f])
    check(m[1]["grade"] == "" and m[1]["title"] == "y" and m[1]["done_at"] == 100,
          "a change beats a seed; two changes to two fields both stand")


def two_machines() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="dsync-test-"))
    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    cfg = tmp / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"}}))
    logs = vault / "agents" / "longhand" / "deadlines"

    def env(host):
        return dict(os.environ, XDG_STATE_HOME=str(tmp / host), LONGHAND_CONFIG=str(cfg), LONGHAND_POMO=str(POMO),
                    LONGHAND_NO_CHECK="1", LONGHAND_HOST=host)

    def pomo(host, *args):
        r = subprocess.run([str(POMO), "deadline", *args], capture_output=True, text=True, env=env(host),
                           stdin=subprocess.DEVNULL)
        assert r.returncode == 0, r.stderr
        return r.stdout

    def run(host, *args):
        r = subprocess.run([str(CHECK), "--json", *args], capture_output=True, text=True, env=env(host),
                           stdin=subprocess.DEVNULL)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)

    def store(host):
        return {d["id"]: d for d in json.loads(pomo(host, "list", "--all", "--json"))["deadlines"]}

    def same():
        return store("air") == store("xmg")

    def both():
        run("air"), run("xmg"), run("air")

    # Two stores that drifted apart before there was any log: each written
    # down as a seed, and settled the same way on both.
    note = daily / "2026-11-10.md"
    note.write_text("# Thesis #thesis\n\n- [x] Revise the proposal 📅 2026-11-13 ✅ 2026-11-12 ^d1\n")
    for host, done_at in (("air", 1794942399), ("xmg", 1794586104)):
        pomo(host, "put", "1", "--due", "1794610740", "--title", "Revise the proposal", "--status", "done",
             "--done-at", str(done_at), "--project", "thesis", "--link", "[[2026-11-10#^d1]]")
    pomo("xmg", "put", "2", "--due", "1795215540", "--title", "Reflective Research Diary 3", "--status", "open",
         "--project", "studio")
    both()
    check(same() and store("air")[1]["done_at"] == 1794586104, "seeds: both keep the earliest time it was done")
    check(2 in store("air"), "…and a deadline only one machine had, waiting for a note, reaches the other")
    check((logs / "air.jsonl").is_file() and (logs / "xmg.jsonl").is_file(), "each machine writes a log of its own")

    # What the line does not hold travels too: a grade, a hide, a deadline
    # with no line, a date moved in the store.
    pomo("air", "grade", "1", "1.3")
    pomo("xmg", "hide", "2")
    both()
    check(store("xmg")[1]["grade"] == "1.3" and store("air")[2]["status"] == "hidden" and same(),
          "a grade given on one and a hide on the other both reach both")
    out = pomo("air", "add", "Initial paper", "--project", "intsem", "2026-11-30")
    new = int(out.split("#")[1].split()[0])
    both()
    check(new in store("xmg") and store("xmg")[new]["title"] == "Initial paper", "a deadline made with no line reaches the other")
    other = int(pomo("xmg", "add", "Something on xmg", "2026-12-01").split("#")[1].split()[0])
    check(other > new, f"…and the other's next id passes it ({other} > {new})")
    both()

    # Concurrent: a date moved on one, a title on the other, between syncs.
    pomo("air", "set", str(new), "2026-12-02")
    pomo("xmg", "set", str(new), "--title", "Initial paper, group part")
    both()
    d = store("air")[new]
    check(same() and d["title"] == "Initial paper, group part"
          and dt.datetime.fromtimestamp(d["due"]).date() == dt.date(2026, 12, 2),
          "a date moved on one and the words changed on the other: both stand")

    # A deadline from the other machine whose note has not arrived yet is
    # not cancelled for want of its line.
    held = daily / "2026-11-17.md"
    late = int(pomo("xmg", "add", "Finish the Themenvorschlag", "--project", "thesis", "2026-11-17").split("#")[1].split()[0])
    held.write_text(f"- [ ] Finish the Themenvorschlag #thesis 📅 2026-11-17 ^d{late}\n")
    run("xmg")                                   # xmg binds it to its line
    away = tmp / "held.md"
    held.rename(away)                            # …and the note has not reached the Air yet
    out = run("air")
    check(store("air").get(late, {}).get("status") == "open" and not out["cancelled"],
          f"a deadline that came before its note is not cancelled while the note is on its way ({out['cancelled']})")
    away.rename(held)
    both()
    check(store("air")[late]["status"] == "open" and same(), "…and once the note is there, it is simply the line's")

    # Removed outright on one: removed on the other.
    pomo("air", "rm", str(other))
    both()
    check(other not in store("xmg") and same(), "one removed outright on one machine is removed on the other")

    # A dry run writes no log and changes no store.
    before = {f.name: f.read_text() for f in logs.glob("*.jsonl")}
    pomo("air", "grade", "1", "2.0")
    r = subprocess.run([str(CHECK), "--dry-run"], capture_output=True, text=True, env=env("air"), stdin=subprocess.DEVNULL)
    check(r.returncode == 0 and {f.name: f.read_text() for f in logs.glob("*.jsonl")} == before
          and store("xmg")[1]["grade"] == "1.3", "a dry run writes no log")
    both()
    check(store("xmg")[1]["grade"] == "2.0" and same(), "…the real one does")

    # A log line cut short by the sync tool is skipped, not fatal.
    with open(logs / "xmg.jsonl", "a") as f:
        f.write('{"at": 9e9, "host": "xmg", "id": 1, "set": {"grade": "')
    out = run("air")
    check(store("air")[1]["grade"] == "2.0", "a half-written log line is skipped")


def main() -> int:
    units()
    two_machines()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
