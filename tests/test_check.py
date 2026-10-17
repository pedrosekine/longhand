"""One copy of a task (docs/tasks.md): longhand-check against a throwaway
vault and store, with the real `pomo`. Every way a deadline used to go
astray is a case here.

Run: python3 tests/test_check.py
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
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-check-"))
    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    (tmp / "config.json").write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"}}))
    env = dict(os.environ, XDG_STATE_HOME=str(tmp / "state"), LONGHAND_CONFIG=str(tmp / "config.json"),
               LONGHAND_POMO=str(POMO), LONGHAND_NO_CHECK="1")

    def pomo(*args):
        r = subprocess.run([str(POMO), "deadline", *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr
        return r.stdout

    # The check's clock is pinned, so a deadline's fortnight runs out when
    # the test says and not when the calendar does.
    NOW = int(dt.datetime(2026, 10, 17, 12, 0).timestamp())

    def run(*args, now=None):
        r = subprocess.run([str(CHECK), "--json", "--now", str(now or NOW), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)

    def item(i):
        return next(d for d in json.loads(pomo("list", "--all", "--json"))["deadlines"] if d["id"] == i)

    def ledger():
        return json.loads((tmp / "state" / "longhand" / "ledger.json").read_text())["deadlines"]

    def add(title, when):
        return int(pomo("add", title, *when.split()).split("#")[1].split()[0])

    note = daily / "2026-10-12.md"
    other = daily / "2026-10-13.md"
    a = add("Roles planned", "2026-10-30")
    b = add("Epistemology and research design", "2026-11-20")
    c = add("AI literacy", "2027-01-15 17:00")
    d = add("Ethics section", "2027-01-15")
    note.write_text(
        "# Interdisciplinary Seminar #intsem\n"
        f"- [ ] Roles planned 📅 2026-10-30 ^d{a}\n"
        "\n"
        "# Research Proficiency #respro\n"
        "### Building blocks\n"
        f"- [ ] Epistemology and research design 📅 2026-11-20 ^d{b}\n"
        f"- [ ] AI literacy 📅 2027-01-15 17:00 ^d{c}\n"
        f"- [ ] Ethics section 📅 2027-01-15 ^d{d}\n"
        "- [ ] a plain box\n")
    other.write_text("nothing bound here\n")

    out = run()
    check(item(b)["project"] == "respro" and item(c)["project"] == "respro",
          "a heading claims the project for the store too (the five 'no project' deadlines)")
    check(item(a)["project"] == "intsem", "…and the line's own heading for the first")
    check(item(b)["link"] == f"[[2026-10-12#^d{b}]]", "the store learns where each line is")
    check(out["cancelled"] == [] and out["lines"] == [], "nothing to do on a store and notes that agree")

    # A tick from the popup (the store moved): the line in its note follows.
    pomo("done", str(a))
    run()
    check(f"- [x] Roles planned 📅 2026-10-30 ^d{a}" in note.read_text(), "a tick in the store ticks the line")
    # A tick in Obsidian (the line moved): the store follows.
    note.write_text(note.read_text().replace(f"- [ ] AI literacy", "- [x] AI literacy"))
    run()
    check(item(c)["status"] == "done", "a tick on the line ticks the store")
    note.write_text(note.read_text().replace(f"- [x] AI literacy", "- [ ] AI literacy"))
    run()
    check(item(c)["status"] == "open", "…and unticking it reopens it")

    # A date changed on either side.
    note.write_text(note.read_text().replace("📅 2026-11-20 ^d", "📅 2026-11-27 ^d"))
    run()
    check(dt.datetime.fromtimestamp(item(b)["due"]).date() == dt.date(2026, 11, 27), "a date changed on the line moves the store")
    pomo("set", str(b), "2026-12-01", "09:00")
    run()
    check(f"Epistemology and research design 📅 2026-12-01 09:00 ^d{b}" in note.read_text(), "a date changed in the store rewrites the line's date only")

    # A block with several deadlines deleted: every one is cancelled, not the last only.
    kept = note.read_text()
    lines = kept.split("\n")
    note.write_text("\n".join(l for l in lines if f"^d{b}" not in l and f"^d{c}" not in l and f"^d{d}" not in l))
    out = run()
    check(sorted(x["id"] for x in out["cancelled"]) == [b, c, d], f"a deleted block cancels all its deadlines ({out['cancelled']})")
    check(all(item(i)["status"] == "cancelled" for i in (b, c, d)), "…as cancelled, kept in the store")
    check(ledger()[str(b)]["cancelled"]["status"] == "open", "…and the ledger remembers what each was")
    # Pasted into another note (a cut and a paste, or a move): back as it was, now there.
    moved = "\n".join(l for l in lines if f"^d{b}" in l or f"^d{c}" in l)
    other.write_text("nothing bound here\n" + moved.replace("- [ ] AI literacy", "- [x] AI literacy") + "\n")
    out = run()
    check(sorted(x["id"] for x in out["restored"]) == [b, c], "the lines pasted back bring their deadlines back")
    check(item(b)["status"] == "open" and item(c)["status"] == "done", "…in the state the line says")
    check(item(b)["link"] == f"[[2026-10-13#^d{b}]]", "…and the store knows the note they are in now")
    check(item(d)["status"] == "cancelled", "the one not pasted stays cancelled")
    check(item(b)["project"] == "", "a line moved out from under its heading loses the heading's project")

    # Dropped in the dashboard: the line stays, as [-], and the store follows.
    other.write_text(other.read_text().replace(f"- [ ] Epistemology", "- [-] Epistemology"))
    out = run()
    check(item(b)["status"] == "cancelled" and [x["id"] for x in out["cancelled"]] == [b], "a cancelled line cancels its deadline")
    other.write_text(other.read_text().replace(f"- [-] Epistemology", "- [ ] Epistemology"))
    run()
    check(item(b)["status"] == "open", "…and un-cancelling it brings it back")

    # Cancelled from the popup or a terminal (the store moved): the line says so.
    pomo("cancel", str(b))
    run()
    check(f"- [-] Epistemology and research design 📅 2026-12-01 09:00 ❌ " in other.read_text() and item(b)["status"] == "cancelled",
          "cancelled from the store: the line becomes [-] and says when, never deleted")
    pomo("reopen", str(b))
    run()
    check(f"- [ ] Epistemology and research design 📅 2026-12-01 09:00 ^d{b}" in other.read_text(), "…and reopened, it is a plain open line again")

    # The page's open note is read, never written.
    pomo("done", str(b))
    before = other.read_text()
    run("--open", "2026-10-13")
    check(other.read_text() == before, "the note the page has open is never written")
    check(ledger()[str(b)]["seen"]["state"] == "open", "…and what it still has to catch up on stays unagreed")
    run()
    check(f"- [x] Epistemology" in other.read_text(), "…so the next check, or the page, still brings it in line")

    # Born without a line: waiting, and the agent's.
    w = add("Registered topic, supervisor and peer group", "2026-10-30")
    out = run()
    check(w in out["waiting"] and item(w)["status"] == "open", "a deadline that never had a line waits")
    check(ledger()[str(w)]["origin"] == "agent" and ledger()[str(w)]["firstTitle"].startswith("Registered"),
          "…counted as the agent's, its first words kept")
    note.write_text(note.read_text() + f"\n- [ ] A registered topic and supervisor #respro 📅 2026-10-30 ^d{w}\n")
    out = run()
    check(item(w)["title"] == "A registered topic and supervisor" and ledger()[str(w)].get("rewritten") is True,
          "written over by the person: their words, and the origin kept")

    # A tag no deadline stands behind (removed outright): the line keeps its words and date.
    pomo("rm", str(a))
    out = run()
    check(a in out["stale"] and "- [x] Roles planned 📅 2026-10-30\n" in note.read_text(), "a stale tag is taken off, the date stays")

    # Done and never in a note: history, left alone.
    h = add("Masters exam", "2026-09-10")
    pomo("done", str(h))
    out = run()
    check(item(h)["status"] == "done" and h not in out["waiting"], "a done deadline that never had a line is history")

    # A fortnight past its date with nothing done: it steps aside — hidden,
    # kept, its line untouched — and comes back if the line says so.
    late = add("Initial paper", "2026-10-01")
    other.write_text(other.read_text() + f"- [ ] Initial paper 📅 2026-10-01 ^d{late}\n")
    out = run(now=int(dt.datetime(2026, 10, 15, 12, 0).timestamp()))
    check(item(late)["status"] == "open" and out["hidden"] == [], "thirteen days late it is still on the list")
    out = run()
    check(item(late)["status"] == "hidden" and [x["id"] for x in out["hidden"]] == [late],
          f"a fortnight late with nothing done, it steps aside ({item(late)['status']}, {out['hidden']})")
    check(ledger()[str(late)]["hidden"]["by"] == "check", "…remembered as stepped aside, not put away by hand")
    check(f"- [ ] Initial paper 📅 2026-10-01 ^d{late}" in other.read_text(), "…its line untouched")
    other.write_text(other.read_text().replace("📅 2026-10-01 ^d", "📅 2026-10-20 ^d"))
    out = run()
    check(item(late)["status"] == "open" and late in [x["id"] for x in out["restored"]],
          "its date moved on in the note: back on the list")
    other.write_text(other.read_text().replace("📅 2026-10-20 ^d", "📅 2026-10-01 ^d"))
    run()
    other.write_text(other.read_text().replace("- [ ] Initial paper", "- [x] Initial paper"))
    run()
    check(item(late)["status"] == "done" and "hidden" not in ledger()[str(late)],
          f"ticked in the note after stepping aside: done, as the line says ({item(late)['status']})")
    byhand = add("Put away by hand", "2026-10-01")
    other.write_text(other.read_text() + f"- [ ] Put away by hand 📅 2026-10-01 ^d{byhand}\n")
    run(now=int(dt.datetime(2026, 10, 2, 12, 0).timestamp()))
    pomo("hide", str(byhand))
    other.write_text(other.read_text().replace("📅 2026-10-01 ^d" + str(byhand), "📅 2026-10-25 ^d" + str(byhand)))
    run()
    check(item(byhand)["status"] == "hidden", "one hidden by hand stays hidden whatever its date does")
    never = add("An agent's old proposal", "2026-09-20")
    out = run()
    check(item(never)["status"] == "hidden" and never not in out["waiting"],
          "one that never had a line steps aside too, rather than waiting forever")

    # No store file: nothing is concluded from it either (every tag would look stale).
    store = tmp / "state" / "longhand" / "deadlines.tsv"
    store.rename(store.with_suffix(".away"))
    before = note.read_text()
    r = subprocess.run([str(CHECK), "--json"], capture_output=True, text=True, env=env)
    store.with_suffix(".away").rename(store)
    check(r.returncode != 0 and note.read_text() == before, "a missing store strips no tag from any note")

    # A dry run says what it would do and does nothing.
    pomo("done", str(w))
    before = note.read_text()
    r = subprocess.run([str(CHECK), "--dry-run"], capture_output=True, text=True, env=env)
    check("would: write" in r.stdout and note.read_text() == before, "a dry run changes nothing")
    run()

    # No daily folder: nothing is concluded from it.
    (tmp / "config.json").write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Gone"}}))
    r = subprocess.run([str(CHECK), "--json"], capture_output=True, text=True, env=env)
    check(r.returncode != 0 and item(w)["status"] == "done", "a missing daily folder cancels nothing")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
