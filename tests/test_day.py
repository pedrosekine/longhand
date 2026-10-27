"""The day conversation, the runner's side (docs/agent.md, "The day
conversation", 2026-10-21): one session a day, the day's context on the
first message and only what is new after, today's other conversations seen
in full, a block pointed at, a private day, the margin seeing the day's
last turns, proposals checked and recorded as the planner's are, and the
day's brief written the morning after — against a stub model, a throwaway
vault and state.

Run: python3 tests/test_day.py
"""
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import tempfile

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


STUB = """#!/usr/bin/env python3
import json, os, re, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
n = len([f for f in os.listdir(d) if f.startswith("call-")])
stdin = sys.stdin.read()
json.dump({"argv": args, "stdin": stdin}, open(os.path.join(d, f"call-{n}.json"), "w"))
reply = {"reply": f"answer {n}", "knowledge": [], "read": []}
if stdin.startswith("# Brief"):
    reply["reply"] = "" if "just hello" in stdin else "- Decided to email Frauenberger first.\\n- The scooter can wait.\\n- The supervisor is Neffke now."
if "PROPOSE" in args[-1] + stdin:
    # The candidates as the first message gave them; a day in the fortnight.
    seen = "".join(json.load(open(os.path.join(d, f)))["stdin"] for f in sorted(os.listdir(d)) if f.startswith("call-"))
    data = json.loads(re.search(r"# What you may propose.*?```json\\n(.*?)\\n```", seen, re.S).group(1))
    c = data["candidates"][0]
    reply["proposals"] = [{"kind": "do-date", "key": c["key"], "date": data["fortnight"][1]["date"], "why": "the day after"},
                          {"kind": "do-date", "key": "no such box", "date": data["fortnight"][1]["date"], "why": "made up"},
                          {"kind": "deadline", "title": "Supervisor email", "date": data["fortnight"][3]["date"],
                           "source": "the note", "why": "said"}]
print(json.dumps({"type": "text", "sessionID": "ses_day", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="day-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    day = dt.date.today().isoformat()
    note = vault / "Daily" / f"{day}.md"
    due = (dt.date.today() + dt.timedelta(days=10)).isoformat()
    note.write_text(f"# Research Proficiency #respro\n\nShortlist: Frauenberger or Neffke.\n\n- [ ] email the supervisor 📅 {due}\n")
    q = "Should I buy an e-scooter?"
    qh = blocks.split(q)[0]["hash"]
    daily = vault / "agents/longhand/daily"
    daily.mkdir(parents=True)
    (daily / f"{day}.json").write_text(json.dumps({"blocks": {qh: {
        "state": "reply", "reply": "By when do you need it?", "head": q, "at": f"{day}T09:00:00",
        "chat": [{"role": "student", "text": "before winter", "at": f"{day}T09:05:00"}]}},
        "suggestions": [], "observations": [], "runs": []}))
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m"}))
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    def calls():
        return [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"))]

    def state():
        return json.loads((daily / f"{day}.json").read_text())

    agent("install")
    check((cfgdir / "opencode" / "agent" / "longhand-day.md").exists(), "install writes the day agent's definition")

    agent("day", "--message", "what should I do first today?")
    first = calls()[-1]
    check("--agent" in first["argv"] and first["argv"][first["argv"].index("--agent") + 1] == "longhand-day"
          and "--session" not in first["argv"], "the first message of the day starts the day agent's own session")
    pay = first["stdin"]
    check("Shortlist: Frauenberger or Neffke." in pay and "# Your knowledge files" in pay,
          "…carrying the day's context: the note and the notebook")
    check("# Today's other conversations" in pay and "By when do you need it?" in pay and "student: before winter" in pay,
          "…and today's other conversations, in full")
    check(pay.rstrip().endswith("what should I do first today?"), "…and what the student says")
    d = state()["day"]
    check(d["session"] == "ses_day" and [t["role"] for t in d["turns"]] == ["student", "agent"]
          and d["turns"][1]["text"] == "answer 0", "the conversation is kept in the day's state, with its session")

    # The margin, later: a new turn there, then the day again.
    st = state()
    later = (dt.datetime.now() + dt.timedelta(seconds=5)).isoformat(timespec="seconds")
    st["blocks"][qh]["chat"].append({"role": "student", "text": "or a bike?", "at": later})
    (daily / f"{day}.json").write_text(json.dumps(st))
    box = next(b for b in blocks.split(note.read_text()) if "email the supervisor" in b["text"])
    agent("day", "--message", "and this one?", "--block", box["hash"])
    second = calls()[-1]
    check("--session" in second["argv"] and "ses_day" in second["argv"] and second["stdin"] == "",
          "a later message continues the same session, sending no context again")
    msg = second["argv"][-1]
    check("# Since your last answer, in today's other conversations" in msg and "student: or a bike?" in msg
          and "before winter" not in msg, "…only what is new in the other conversations")
    check("# The block the student points at" in msg and "> - [ ] email the supervisor" in msg,
          "…and the block the student points at")
    check(state()["day"]["turns"][2].get("block") == box["hash"], "the student's turn keeps the block it pointed at")

    # Cross-visibility: the margin sees the day's last turns.
    ctx = agent("context", "--trigger", "question", "--hash", box["hash"]).stdout
    check("# The day conversation, its last turns" in ctx and "Longhand: answer 1" in ctx and "student: and this one?" in ctx,
          "a block's payload carries the day conversation's last turns")

    # Proposing: checked as the planner's are, recorded in the one ledger,
    # the turn keeps their ids; a second time, the same card, not a new one.
    check("# What you may propose" in first["stdin"] and '"candidates"' in first["stdin"],
          "the first message carries what the day may propose about")
    agent("day", "--message", "PROPOSE a day for the supervisor email")
    check("# What you may propose" not in calls()[-1]["argv"][-1], "…a later message, only when it changed")
    ledger = json.loads((tmp / "state" / "longhand" / "proposals.json").read_text())
    mine = [x for x in ledger["items"] if x.get("from") == "day"]
    check(len(mine) == 2 and {x["kind"] for x in mine} == {"do-date", "deadline"} and all(x["status"] == "open" for x in mine),
          f"a proposal that holds is recorded with the dashboard's, one that names no box is not ({[x['kind'] for x in mine]})")
    turn = state()["day"]["turns"][-1]
    check(sorted(x["id"] for x in turn.get("proposals") or []) == sorted(x["id"] for x in mine)
          and any(x.get("date") and x.get("why") for x in turn["proposals"]), "the answer keeps its proposals, for the cards")
    check(turn.get("unoffered") == ["do-date · no such box"],
          f"what was proposed but not offered is kept on the turn, for the page to say so ({turn.get('unoffered')})")
    agent("day", "--message", "PROPOSE it again")
    check("did not offer as cards" in calls()[-1]["argv"][-1] and "- do-date · no such box" in calls()[-1]["argv"][-1],
          "…and the next message tells the agent, so it points at no card that is not there")
    again = json.loads((tmp / "state" / "longhand" / "proposals.json").read_text())
    check(len(again["items"]) == len(ledger["items"]) and sorted(x["id"] for x in state()["day"]["turns"][-1]["proposals"]) == sorted(x["id"] for x in mine),
          "the same proposal again is the same card: no new item")
    st = json.loads((cfgdir / "longhand" / "settings.json").read_text()) if (cfgdir / "longhand" / "settings.json").exists() else {}
    st["autonomy"] = {"do-date": "never"}
    (cfgdir / "longhand" / "settings.json").write_text(json.dumps(st))
    for x in again["items"]:
        x["status"] = "declined"
    (tmp / "state" / "longhand" / "proposals.json").write_text(json.dumps(again))
    agent("day", "--message", "PROPOSE a day once more")
    third = json.loads((tmp / "state" / "longhand" / "proposals.json").read_text())
    check(len(third["items"]) == len(again["items"]) and '"you_may"' in calls()[-1]["argv"][-1]
          and "do-date" not in calls()[-1]["argv"][-1].split('"you_may"')[1][:120],
          "a kind the student set to never is not proposed; a declined one does not return; what changed travels again")

    # A private day still talks, and sees nothing of the note.
    note.write_text("---\nagent: false\n---\nA private worry.\n")
    st = state()
    st["day"] = {"session": "", "turns": []}
    (daily / f"{day}.json").write_text(json.dumps(st))
    agent("day", "--message", "anything due this week?")
    pay = calls()[-1]["stdin"]
    check("A private worry." not in pay and "today's note is marked private" in pay,
          "a private day: the conversation works, sees nothing of the note, and is told so")

    briefs(tmp, env, bindir)
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


def briefs(tmp: pathlib.Path, env: dict, bindir: pathlib.Path) -> None:
    """The morning after: the day's first run writes the brief of each day
    before it that had a conversation, once; every payload carries the last
    few; a private day gets none; the student's corrections hold."""
    vault = tmp / "vault2"
    (vault / "Daily").mkdir(parents=True)
    cfgdir = tmp / "config2"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m"}))
    stub = tmp / "stub2"
    stub.mkdir()
    env = dict(env, LONGHAND_CONFIG=str(cfg), XDG_CONFIG_HOME=str(cfgdir), XDG_STATE_HOME=str(tmp / "state2"), STUB_DIR=str(stub))
    today = dt.date.today()
    daily = vault / "agents/longhand/daily"
    daily.mkdir(parents=True)
    knowledge = vault / "agents/longhand/knowledge"
    knowledge.mkdir(parents=True)
    # A correction made before the brief is written still holds in it.
    (knowledge / "corrections.md").write_text(f"# The student's corrections\n\n- {today} · correct · days/x.md: "
                                              f"«The supervisor is Neffke now» → «The supervisor is not chosen yet»\n")

    def day_of(back, turns, private=False):
        d = (today - dt.timedelta(days=back)).isoformat()
        (vault / "Daily" / f"{d}.md").write_text(("---\nagent: false\n---\n" if private else "") + "A day.\n")
        (daily / f"{d}.json").write_text(json.dumps({"blocks": {}, "day": {"session": "s", "turns": [
            {"role": "student", "text": t, "at": f"{d}T10:00:00"} if i % 2 == 0 else
            {"role": "agent", "text": t, "at": f"{d}T10:00:05"} for i, t in enumerate(turns)]}}))
        return d

    one = day_of(1, ["who first?", "Frauenberger, then Neffke."])
    two = day_of(2, ["just hello", "Hello."])
    three = day_of(3, ["a private worry", "I hear you."], private=True)
    four = day_of(4, [])
    (vault / "Daily" / f"{today.isoformat()}.md").write_text("Today.\n")

    def agent(*args):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr + r.stdout
        return r

    def calls():
        return [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"))]

    agent("day", "--message", "where were we?")
    asked = [c for c in calls() if c["stdin"].startswith("# Brief")]
    check(len(asked) == 2 and all("--agent" in c["argv"] and "longhand-day" in c["argv"] for c in asked),
          f"the day's first run asks for the briefs the days before are missing: two, not the private day nor the silent one ({len(asked)})")
    check(any("student: who first?" in c["stdin"] and "Longhand: Frauenberger, then Neffke." in c["stdin"] for c in asked),
          "…from that day's conversation")
    brief = knowledge / "days" / f"{one}.md"
    text = brief.read_text() if brief.exists() else ""
    check(text.startswith("# ") and "the day in brief" in text and "- Decided to email Frauenberger first." in text,
          "the brief is written into the notebook, days/<date>.md")
    check("The supervisor is not chosen yet" in text and "Neffke now" not in text, "…with the student's corrections applied")
    check(not (knowledge / "days" / f"{two}.md").exists() and json.loads((daily / f"{two}.json").read_text())["day"]["brief"]["file"] == "",
          "a day with nothing worth carrying gets no brief, and is not asked again")
    check(not (knowledge / "days" / f"{three}.md").exists()
          and json.loads((daily / f"{three}.json").read_text())["day"]["brief"].get("skipped"), "a private day gets none")
    check("brief" not in json.loads((daily / f"{four}.json").read_text())["day"], "a day without a conversation is left alone")
    pay = calls()[-1]["stdin"]
    check("# The last days, in brief" in pay and "Decided to email Frauenberger first." in pay
          and f"## days/{one}.md" in pay and pay.count("## days/") == 1, "today's payload carries the briefs")
    check(pay.find("# The last days, in brief") > pay.find("# Your knowledge files")
          and f"## days/{one}.md" not in pay[:pay.find("# The last days, in brief")],
          "…as the last days, not among its knowledge files")
    n = len(calls())
    agent("day", "--message", "and now?")
    check(len(calls()) == n + 1, "once written, no brief is asked for again")
    nbk = json.loads(agent("notebook").stdout)
    check(nbk["files"] and nbk["files"][-1]["file"] == f"days/{one}.md", "Settings lists the brief, after the agent's own notes")


if __name__ == "__main__":
    sys.exit(main())
