"""A block's chat can change what is already there (2026-11-15), the runner's
side: the margin's agent is shown the boxes that read like the block, and
the deadlines with no line; a day for a box or dropping one goes into the
one list as the day conversation's cards do (checked by plan.py, `from:
margin`), the margin keeping a copy saying which item; a drop of a deadline
with no line names its number, one with a line becomes its box's drop; a
move names the deadline it moves; what local code refuses is said back.

Found when "do this task by wed" on a new "AI Literacy course" box added a
third deadline (#64) beside #63 and #32 — the move was guessed from the
words, and two alike made a new one — and the agent then had no card to
take any of it away.

Run: python3 tests/test_margin_cards.py
"""
import datetime as dt
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
import blocks  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# The model: answers what reply.json says, a "KEY:<title>" resolved to the
# box key the payload offered for that title (as the agent copies it).
STUB = r"""#!/usr/bin/env python3
import json, os, re, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
stdin = sys.stdin.read()
n = len([f for f in os.listdir(d) if f.startswith("call-")])
json.dump({"argv": args, "stdin": stdin}, open(os.path.join(d, f"call-{n}.json"), "w"))
seen = "".join(json.load(open(os.path.join(d, f)))["stdin"] + json.load(open(os.path.join(d, f)))["argv"][-1]
               for f in sorted(os.listdir(d)) if f.startswith("call-"))
offered = [json.loads(m) for m in re.findall(r"# What you may propose about this box.*?```json\n(.*?)\n```", seen, re.S)]
keys = {b["title"]: b["key"] for o in offered for b in o["open_boxes"]}
reply = json.load(open(os.path.join(d, "reply.json")))
def fill(x):
    if isinstance(x, dict):
        return {k: fill(v) for k, v in x.items()}
    if isinstance(x, list):
        return [fill(v) for v in x]
    if isinstance(x, str) and x.startswith("KEY:"):
        return keys.get(x[4:], "no such box")
    return x
reply = fill(reply)
print(json.dumps({"type": "text", "sessionID": "ses_m", "part": {"type": "text", "text": "```json\n" + json.dumps(reply) + "\n```"}}))
"""

# The timer's deadline commands, answered from the test's store.
POMO = r"""#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
a = sys.argv[1:]
open(os.path.join(d, "pomo_args.json"), "w").write(json.dumps(a))
if a[:2] == ["deadline", "list"]:
    print(open(os.path.join(d, "pomo_store.json")).read()); sys.exit(0)
if a[:2] == ["deadline", "when"]:
    print(open(os.path.join(d, "pomo_when")).read()); sys.exit(0)
if a[:2] == ["deadline", "set"]:
    print(f"pomo: deadline #{a[2]} · moved"); sys.exit(0)
print("{}")
"""


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="margin-cards-test-"))
    try:
        return run(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def run(tmp: pathlib.Path) -> int:
    today = dt.date.today()
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    soon, later, jan = (today + dt.timedelta(days=d) for d in (5, 3, 60))
    older = today - dt.timedelta(days=30)
    (vault / "Daily" / f"{older.isoformat()}.md").write_text(
        f"# Research Proficiency #respro\n\n- [ ] AI literacy 📅 {jan.isoformat()} ^d32\n")
    note = vault / "Daily" / f"{today.isoformat()}.md"
    note.write_text(f"- [ ] AI Literacy course 📅 {soon.isoformat()} ^d63\n\n- [ ] email the supervisor\n")
    state = tmp / "state" / "longhand"
    state.mkdir(parents=True)

    def ts(day):
        return int(time.mktime(day.timetuple())) + 86340

    rows = [(32, ts(jan), "AI literacy", "respro", f"[[{older.isoformat()}#^d32]]"),
            (63, ts(soon), "AI Literacy course", "", f"[[{today.isoformat()}#^d63]]"),
            (64, ts(later), "AI Literacy course", "", "")]
    (state / "deadlines.tsv").write_text("".join(f"{i}\t{due}\t{t}\topen\t0\t\t{p}\t{link}\n" for i, due, t, p, link in rows))
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m", "horizon": "2000-01-01"}))
    bindir = tmp / "bin"
    bindir.mkdir()
    for name, text in (("opencode", STUB), ("pomo", POMO)):
        (bindir / name).write_text(text)
        (bindir / name).chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    store = [{"id": i, "title": t, "status": "open", "due": due} for i, due, t, _, _ in rows]
    (stub / "pomo_store.json").write_text(json.dumps({"deadlines": store}))
    wed = today + dt.timedelta(days=2)
    (stub / "pomo_when").write_text(f"{ts(wed)}\t{wed:%a %d %b}")
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args):
        return subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)

    def reply(text, proposals):
        (stub / "reply.json").write_text(json.dumps({"reply": text, "proposals": proposals, "suggestions": [],
                                                     "knowledge": [], "read": []}))

    def calls():
        return [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"), key=lambda f: int(f.stem[5:]))]

    def record():
        st = json.loads((vault / "agents/longhand/daily" / f"{today.isoformat()}.json").read_text())
        return st["blocks"][h]

    def ledger():
        return json.loads((state / "proposals.json").read_text())

    h = next(b["hash"] for b in blocks.split(note.read_text()) if "AI Literacy course" in b["text"])
    day = today + dt.timedelta(days=2)

    # 1. The first message shows the boxes that read like the block, and the
    # deadline with no line; nothing unrelated.
    reply("Which of these is the course?", [])
    r = agent("chat", "--hash", h, "--message", "do I have duplicates of this task now?")
    check(r.returncode == 0, f"a chat runs ({r.stderr.strip()[-300:]})")
    first = calls()[-1]["stdin"]
    check("# What you may propose about this box" in first, "the first message carries what the margin may propose about")
    import re
    offered = json.loads(re.search(r"# What you may propose about this box.*?```json\n(.*?)\n```", first, re.S).group(1))
    titles = sorted(b["title"] for b in offered["open_boxes"])
    check(titles == ["AI Literacy course", "AI literacy"], f"…the boxes that read like it, not the supervisor's ({titles})")
    check([d["deadline"] for d in offered["deadlines_with_no_line"]] == [64],
          f"…and the deadline with no line, by its number ({offered['deadlines_with_no_line']})")
    check(sorted(offered["you_may"]) == ["do-date", "drop"], "…and what it may propose there: a day, a drop")
    check({b["title"]: b["deadline"] for b in offered["open_boxes"]} == {"AI Literacy course": 63, "AI literacy": 32},
          "…each box with its deadline's number, to tell them apart")

    # 2. "remove the one from the 18th, and the 20th; a day for the January
    # one": two drops and a do-date, all in one answer, into the one list.
    reply("Dropping the copy with no line and the 20 November box; Wednesday to work on January's.", [
        {"kind": "drop", "deadline": 64, "why": "a copy the margin's card added"},
        {"kind": "drop", "key": "KEY:AI Literacy course", "why": "the same course as January's"},
        {"kind": "do-date", "key": "KEY:AI literacy", "date": day.isoformat(), "why": "asked for Wednesday"},
        {"kind": "drop", "deadline": 999, "why": "made up"},
    ])
    r = agent("chat", "--hash", h, "--message", "remove the one from the 18, the one from the 20. A day for the January one")
    check(r.returncode == 0, f"…the chat runs ({r.stderr.strip()[-300:]})")
    check("# What you may propose about this box" not in calls()[-1]["argv"][-1],
          "a later message does not carry the boxes again while they are unchanged")
    mine = [x for x in ledger()["items"] if x.get("from") == "margin"]
    kinds = sorted((x["kind"], str(x.get("deadline") or x["key"].split("\t")[-1])) for x in mine)
    check(kinds == [("do-date", "- AI literacy"), ("drop", "- AI Literacy course"), ("drop", "64")],
          f"the two drops and the day are in the one list, from the margin ({kinds})")
    drop64 = next(x for x in mine if x.get("deadline") == 64)
    check(drop64["key"] == "" and drop64["title"] == "AI Literacy course" and drop64["status"] == "open",
          "…the deadline with no line, dropped by its number")
    rec = record()
    turn = rec["chat"][-1]
    cards = [rec["proposals"][i] for i in turn["proposals"]]
    check(sorted(c["ledger"] for c in cards) == sorted(x["id"] for x in mine) and all("id" not in c for c in cards),
          "the margin keeps a copy of each, saying which item it is, under the answer that made it")
    check(turn.get("unoffered") == ["drop · deadline #999"], f"what was refused is kept on the turn ({turn.get('unoffered')})")
    tr = (vault / "agents/longhand/daily" / f"{today.isoformat()}.md").read_text()
    check("- [ ] drop: AI Literacy course (deadline #64, no line)" in tr and f"- [ ] do {day.isoformat()}: AI literacy" in tr
          and "- not offered as a card: drop · deadline #999" in tr, "the transcript says each card, and what was not offered")
    idx = turn["proposals"][0]
    r = agent("accept", "--hash", h, "--index", str(idx))
    check(r.returncode != 0 and "page's to apply" in r.stderr, f"accept leaves a listed card to the page ({r.stderr.strip()})")

    # 3. The next message says what was not offered.
    reply("", [])
    agent("chat", "--hash", h, "--message", "ok")
    msg = calls()[-1]["argv"][-1]
    check("did not offer as cards" in msg and "- drop · deadline #999" in msg, "…and the next message tells the agent")

    # 4. A drop naming a deadline that has a line is its box's drop: the same
    # item as the one by key, not a second.
    reply("Dropping it.", [{"kind": "drop", "deadline": 63, "why": "the same course"}])
    agent("chat", "--hash", h, "--message", "drop #63")
    mine = [x for x in ledger()["items"] if x.get("from") == "margin" and x["kind"] == "drop"]
    check(len([x for x in mine if x["status"] == "open"]) == 2 and not record()["chat"][-1].get("unoffered"),
          f"a drop by the number of a deadline with a line is its box's drop, not a second card ({[x['key'] for x in mine]})")

    # 5. A move names the deadline it moves; without a number, a new one
    # beside two alike says so; a number not open is not a card.
    reply("Moving #63 to Wednesday.", [{"kind": "deadline", "title": "AI Literacy course", "when": "wed", "moves": 63},
                                        {"kind": "deadline", "title": "AI Literacy course", "when": "wed", "moves": "#999"}])
    agent("chat", "--hash", h, "--message", "do this task by wed")
    rec = record()
    made = [rec["proposals"][i] for i in rec["chat"][-1]["proposals"]]
    check(len(made) == 1 and made[0].get("moves", {}).get("id") == 63, f"a move names the deadline it moves ({made})")
    check(rec["chat"][-1].get("unoffered") == ["move deadline #999 · it is not an open deadline"],
          f"…a number that is not an open deadline is no card, and is said ({rec['chat'][-1].get('unoffered')})")
    r = agent("accept", "--hash", h, "--index", str(rec["chat"][-1]["proposals"][0]))
    check(r.returncode == 0 and json.loads((stub / "pomo_args.json").read_text()) == ["deadline", "set", "63", "wed"],
          "accepting it moves #63, adding nothing")
    reply("A new one.", [{"kind": "deadline", "title": "AI Literacy course", "when": "wed"}])
    agent("chat", "--hash", h, "--message", "a new one, then")
    rec = record()
    new = rec["proposals"][rec["chat"][-1]["proposals"][0]]
    check(not new.get("moves") and sorted(d["id"] for d in new.get("alike") or []) == [32, 63, 64],
          f"without a number, two alike make a new one that says what it stands beside ({new.get('alike')})")

    # 6. The list: a drop of a deadline with no line, closed some other way
    # (Del on its row), is moot; one still open stays.
    out = json.loads(agent("proposals").stdout)
    check(any(x.get("deadline") == 64 and x["kind"] == "drop" for x in out["open"]), "the dashboard lists the drop of #64")
    (state / "deadlines.tsv").write_text((state / "deadlines.tsv").read_text().replace("\tAI Literacy course\topen\t0\t\t\t\n",
                                                                                    "\tAI Literacy course\tcancelled\t0\t\t\t\n"))
    out = json.loads(agent("proposals").stdout)
    check(not any(x.get("deadline") == 64 for x in out["open"])
          and next(x for x in ledger()["items"] if x.get("deadline") == 64)["status"] == "moot",
          "…until #64 is cancelled some other way: moot")

    # 7. The day conversation is shown the deadlines with no line too.
    ctx = agent("day", "--message", "anything to tidy?")
    first_day = next(c for c in calls() if "--agent" in c["argv"] and "longhand-day" in c["argv"])
    check(ctx.returncode == 0 and '"deadlines_with_no_line"' in first_day["stdin"],
          "the day conversation is shown the deadlines with no line as well")

    print("PASS" if failures == 0 else f"FAIL ({failures})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
