"""`longhand-agent dated`: every box given a day, under the day it is for.

Run: python3 tests/test_dated.py

A task written on Saturday "for Monday" belongs to Monday's page too
(2026-11-14). The page's band above a day's note reads this list.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fakes  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"

failures = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-dated-test-"))
try:
    vault = tmp / "vault"
    daily = vault / "human" / "Daily"
    daily.mkdir(parents=True)
    cfg = tmp / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD"},
                               "horizon": "2000-01-01", "agentDir": "agents/longhand"}))
    mine = fakes.machine(tmp)
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"),
               XDG_CONFIG_HOME=mine["XDG_CONFIG_HOME"], FAKE_HYPR_DIR=mine["FAKE_HYPR_DIR"], PATH=mine["PATH"])

    (daily / "2026-11-14.md").write_text(
        "# Thesis #thesis\n\n"
        "- [ ] Finish the Themenvorschlag 📅 2026-11-16 ^d61\n"
        "- [x] Book the room ⏳ 2026-11-16 ✅ 2026-11-14\n"
        "- [ ] Draft and send ⏳ 2026-11-16 📅 2026-11-18 17:00\n"
        "- [-] Dropped idea 📅 2026-11-16 ❌ 2026-11-14\n"
        "- [ ] no date at all\n"
        "\n```\n- [ ] in a fence 📅 2026-11-16\n```\n")
    # A future day's note counts too, and one dated for its own day.
    (daily / "2026-11-16.md").write_text("- [ ] Call the office 📅 2026-11-16 09:00\n")
    (daily / "not-a-day.md").write_text("- [ ] stray 📅 2026-11-16\n")

    r = subprocess.run([sys.executable, str(AGENT), "dated"], capture_output=True, text=True, env=env,
                       stdin=subprocess.DEVNULL)
    check(r.returncode == 0, f"dated exits 0 ({r.stderr.strip()})")
    days = json.loads(r.stdout or "{}").get("days", {})
    mon = days.get("2026-11-16", [])
    titles = [x["title"] for x in mon]

    check(set(titles) == {"Finish the Themenvorschlag", "Book the room", "Draft and send", "Call the office"},
          f"Monday has every box due or to be done on it, from any note ({titles})")
    check("Dropped idea" not in titles, "a cancelled box is not counted")
    check("stray" not in titles and "in a fence" not in titles, "a file that is no day, and a fence, are not read")
    check([x["done"] for x in mon] == [False, False, False, True], f"open ones first ({[x['done'] for x in mon]})")
    check(mon[0]["title"] == "Call the office", "the due ones before the do ones, by the hour")
    hows = {x["title"]: x["how"] for x in mon}
    check(hows["Finish the Themenvorschlag"] == "due" and hows["Draft and send"] == "do", f"due or do ({hows})")
    draft = [x for x in days.get("2026-11-18", []) if x["title"] == "Draft and send"]
    check(len(draft) == 1 and draft[0]["how"] == "due", "a box with a do-day and a due day is on both days")
    them = next(x for x in mon if x["title"] == "Finish the Themenvorschlag")
    check(them["date"] == "2026-11-14" and them["written"] == "2026-11-14" and them["line"] == 2
          and them["project"] == "thesis" and them["anchor"] == 61,
          f"a row says where its line is, so the page can go to it ({them})")
    check("2026-11-14" not in days, "a day nothing is for has no entry")
finally:
    shutil.rmtree(tmp)

print("FAIL" if failures else "PASS")
sys.exit(1 if failures else 0)
