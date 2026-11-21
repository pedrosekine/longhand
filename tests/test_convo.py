"""The one conversation (agent/convo.py; docs/agent.md, "One conversation",
slice 1, 2026-11-18).

Run: python3 tests/test_convo.py

The store:
- each machine writes a log of its own, read merged, in the order said; a
  turn written twice (by two machines, or again) is one; a line cut short
  mid-sync is passed over
- memory follows the subject: what was said elsewhere about a message's
  subjects, and elsewhere today — never the place's own turns, never a
  closed one, never what it was given before, the last few a subject

The runner, against a stub model and a throwaway vault:
- every place's own store is brought in (the margin, the day's chat, a
  note's, the planner's), once: again adds nothing, and nor does the other
  machine merging the same synced stores
- a task talked about in yesterday's margin is known in today's day chat
  when its block is pointed at (the forgetting this is for); a box under
  it is the same subject
- a note's chat is told what was said elsewhere today; what was said about
  a note marked private is kept and carried nowhere
- a message's turns reach the log, written by this machine only
- a later message is not given again what its session has
- slice 2: a message points at several things (a task of another day, a
  block of today's; a private one counted, never shown), the turn keeps
  them; a note or a paper the agent may see anyway (never a private one,
  `--files` lists them); `--view` (earlier days, their own chat said
  whole and their other places a line each; today's places; with how to
  open them) and `--elsewhere` (what was said about a task outside its own
  chat)
- slice 3: a block's chat is the one agent's; what planning proposed is a
  line of "everything"
- recall (2026-11-21): a day's turns or the turns with some words, each
  with its neighbour, never closed, never past the horizon; asked for by
  the agent, given in the same session, kept on its answer; the payload
  says today's date
"""
import datetime as dt
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
import blocks  # noqa: E402
import convo  # noqa: E402

FAILS = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        FAILS.append(what)


STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
n = len([f for f in os.listdir(d) if f.startswith("call-")])
stdin = sys.stdin.read()
json.dump({"argv": args, "stdin": stdin}, open(os.path.join(d, f"call-{n}.json"), "w"))
reply = {"reply": f"answer {n}", "knowledge": [], "read": [], "proposals": []}
rf = os.path.join(d, "recall.json")
if os.path.exists(rf):                 # asked once to look back, then answers
    reply = {"reply": "", "knowledge": [], "read": [], "proposals": [], "recall": json.load(open(rf))}
    os.remove(rf)
print(json.dumps({"type": "text", "sessionID": "ses_x", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def store(tmp: pathlib.Path) -> None:
    folder = tmp / "log"
    a, b = convo.Log(folder, "alpha"), convo.Log(folder, "beta")
    task, paper = "task:thesis\t- write the intro", "paper:papers/smith.pdf"

    def t(where, thread, role, text, at, subjects, **kw):
        return convo.turn(where, thread, role, text, at, subjects, {task: "write the intro", paper: "smith"}, **kw)
    m1 = t("margin", "margin:2026-11-16:aa", "student", "is the intro too long?", "2026-11-16T10:00:00", [task, "block:2026-11-16:aa"])
    m2 = t("margin", "margin:2026-11-16:aa", "agent", "Cut the second paragraph.", "2026-11-16T10:00:00", [task, "block:2026-11-16:aa"])
    p1 = t("paper", paper, "student", "what is the sample?", "2026-11-17T09:00:00", [paper])
    n1 = t("note", "note:human/x.md", "student", "a private thing", "2026-11-18T08:00:00", ["note:human/x.md"], closed=True)
    d1 = t("day", "day:2026-11-18", "student", "what first?", "2026-11-18T09:00:00", ["day:2026-11-18"])
    check(len(a.append([m1, m2])) == 2 and len(b.append([p1, n1, d1, m1])) == 3,
          "a turn another machine's log holds is not written again")
    check(sorted(f.name for f in folder.iterdir()) == ["alpha.jsonl", "beta.jsonl"], "each machine writes a log of its own")
    with open(folder / "beta.jsonl", "a") as f:
        f.write('{"id": "cut", "thread": "day:2026-11-18", "role": "stu')
    turns = a.read()
    check([x["text"] for x in turns] == ["is the intro too long?", "Cut the second paragraph.", "what is the sample?",
                                         "a private thing", "what first?"],
          f"read merged, in the order said (a question before its answer), the cut line passed over ({[x['text'] for x in turns]})")
    check(len(b.append([d1])) == 0 and b.append([t("day", "day:2026-11-18", "agent", "The intro.", "2026-11-18T09:00:05", ["day:2026-11-18"])])
          and (folder / "beta.jsonl").read_text().splitlines()[-2].endswith('"stu') and len(b.read()) == 6,
          "…and a log cut short takes the next turn on a line of its own")
    turns = a.read()

    groups, rest = convo.memory(turns, [task], "day:2026-11-18", "2026-11-18")
    check([s for s, _ in groups] == [task] and [x["text"] for x in groups[0][1]] == ["is the intro too long?", "Cut the second paragraph."]
          and rest == [], "memory: what was said elsewhere about the subject; the place's own turns and a closed one, never")
    groups, rest = convo.memory(turns, [paper], paper, "2026-11-18")
    check(groups == [] and [x["text"] for x in rest] == ["what first?", "The intro."],
          "…and what was said elsewhere today")
    had = convo.carry([], convo.ids(*convo.memory(turns, [task], "day:2026-11-18", "2026-11-18")))
    check(convo.memory(turns, [task], "day:2026-11-18", "2026-11-18", had) == ([], []), "…never what it was given before")
    many = [t("margin", "margin:2026-11-10:bb", "student", f"line {i}", f"2026-11-10T10:{i:02d}:00", [task]) for i in range(30)]
    groups, _ = convo.memory(many, [task], "day:2026-11-18", "2026-11-18")
    check(len(groups[0][1]) == convo.PER_SUBJECT and groups[0][1][-1]["text"] == "line 29", "…the last few a subject")
    said = convo.lines(turns, *convo.memory(turns, [task], "day:2026-11-18", "2026-11-18"), "2026-11-18")
    check(any("## About the task “write the intro”" in l for l in said)
          and any("in the margin, about “write the intro”] Longhand: Cut the second paragraph." in l for l in said),
          "the payload's section names the subject and where each turn was said")
    check(convo.lines(turns, [], [], "2026-11-18") == [], "…and is nothing when there is nothing to carry")

    # Recall (2026-11-21): what was said before, fetched when the agent asks.
    day = convo.recall(turns, day="2026-11-16")
    check([x["text"] for x in day] == ["is the intro too long?", "Cut the second paragraph."],
          "recall: a day's turns, wherever said")
    found = convo.recall(turns, words="second paragraph")
    check([x["text"] for x in found] == ["is the intro too long?", "Cut the second paragraph."],
          f"…or the turns with these words, each with the one before it, so the answer comes with its question ({[x['text'] for x in found]})")
    check(convo.recall(turns, words="private thing") == [] and convo.recall(turns, day="2026-11-18")[0]["text"] == "what first?",
          "…never a closed turn")
    check(convo.recall(turns, day="2026-11-16", hidden=lambda d: d < "2026-11-17") == []
          and convo.recall(turns, words="sample", day="2026-11-16") == [],
          "…never what the horizon hides, and a day narrows the words")
    lots = [t("margin", "margin:2026-11-09:cc", "student", f"line {i}", f"2026-11-09T10:{i:02d}:00", [task]) for i in range(60)]
    check(len(convo.recall(lots, words="line")) == convo.RECALL_TURNS and convo.recall(lots, words="line")[-1]["text"] == "line 59"
          and convo.recall(turns) == [],
          "…the latest few at most, and nothing for nothing asked")
    said = convo.recall_lines(turns, found, "2026-11-18", words="second paragraph")
    check(said[0] == "## From your one conversation, about “second paragraph”"
          and any("in the margin, about “write the intro”] Longhand: Cut the second paragraph." in l for l in said)
          and convo.recall_lines(turns, [], "2026-11-18", day="2026-11-01")[2] == "(nothing found)",
          "…its section says what was asked, where and when each turn was said, or that nothing was")


def runner(tmp: pathlib.Path) -> None:
    vault = tmp / "vault"
    daily_notes = vault / "human" / "Daily"
    daily_notes.mkdir(parents=True)
    today, yday = dt.date.today(), dt.date.today() - dt.timedelta(days=1)
    box = "- [ ] write the intro"
    (daily_notes / f"{yday}.md").write_text(f"# Thesis #thesis\n\n{box}\n  - [ ] cut the second paragraph\n")
    (daily_notes / f"{today}.md").write_text(f"# Thesis #thesis\n\nA line of today.\n\n{box}\n")
    yh = next(b for b in blocks.split((daily_notes / f"{yday}.md").read_text()) if "write the intro" in b["text"])["hash"]
    th = next(b for b in blocks.split((daily_notes / f"{today}.md").read_text()) if "write the intro" in b["text"])["hash"]
    agent_dir = vault / "agents" / "longhand"
    (agent_dir / "daily").mkdir(parents=True)
    (agent_dir / "daily" / f"{yday}.json").write_text(json.dumps({"date": str(yday), "blocks": {yh: {
        "state": "reply", "reply": "An intro states the gap first.", "head": box, "at": f"{yday}T10:00:00",
        "chat": [{"role": "student", "text": "is mine too long?", "at": f"{yday}T10:05:00"},
                 {"role": "agent", "text": "Yes: cut the second paragraph.", "at": f"{yday}T10:05:00"},
                 {"role": "student", "text": "and after?", "at": f"{yday}T10:06:00"},
                 {"role": "agent", "text": "", "error": "timed out", "at": f"{yday}T10:06:00"}]}},
        "day": {"session": "", "turns": [{"role": "student", "text": "what did I miss?", "at": f"{yday}T18:00:00"},
                                         {"role": "agent", "text": "Nothing due.", "at": f"{yday}T18:00:04"}]},
        "observations": [{"text": "The essay is due Friday.", "at": f"{yday}T08:00:00"}],
        "suggestions": [], "runs": []}))
    studies = vault / "human" / "Studies"
    studies.mkdir(parents=True)
    (studies / "open.md").write_text("# Methods\n\nInterviews, twelve of them.\n")
    (studies / "closed.md").write_text("---\nagent: false\n---\n# Diary\n\nSomething of my own.\n")
    (agent_dir / "notes").mkdir()
    for rel, said in (("human/Studies/closed.md", "what did I write about my own thing?"),):
        (agent_dir / "notes" / (hashlib.md5(rel.encode()).hexdigest()[:16] + ".json")).write_text(json.dumps({
            "path": rel, "session": "", "seen": "", "turns": [
                {"role": "student", "text": said, "at": f"{today}T00:00:05"},
                {"role": "agent", "text": "SECRET-OF-THE-DIARY, you wrote.", "at": f"{today}T00:00:09"}]}))
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m"}))
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()

    def env_of(host):
        st = tmp / f"state-{host}"
        (st / "longhand").mkdir(parents=True, exist_ok=True)
        return dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(st), XDG_CONFIG_HOME=str(cfgdir),
                    STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}", LONGHAND_HOST=host)
    here, there = env_of("here"), env_of("there")
    key = "thesis\t- write the intro"
    for e in (here, there):                                # the planner's conversations sync as part of the ledger
        (pathlib.Path(e["XDG_STATE_HOME"]) / "longhand" / "proposals.json").write_text(json.dumps({
            "next": 2, "items": [], "threads": {key: {"title": "write the intro", "turns": [
                {"role": "student", "text": "not on Wednesday, I have lab", "at": f"{yday}T12:00:00", "about": 1},
                {"role": "agent", "text": "Thursday then.", "at": f"{yday}T12:00:00", "about": 1}]}}}))

    def agent(*args, env=here, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    def calls():
        return [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"))]

    def convo_(*args, env=here):
        return json.loads(agent("conversation", *args, env=env).stdout)

    agent("install")
    c = convo_("--merge")
    check(c["added"] == 12 and c["where"] == {"margin": 5, "open": 1, "day": 2, "note": 2, "planner": 2}
          and c["hosts"] == {"here": 12},
          f"every place's own store is brought in: the margin, on opening, the day's chat, a note's, the planner's ({c})")
    check(convo_("--merge")["added"] == 0, "…again adds nothing")
    c2 = convo_("--merge", env=there)
    check(c2["added"] == 0 and c2["turns"] == 12, f"…nor does the other machine, merging the same synced stores ({c2['added']})")
    about = convo_("--about", "task:" + key)
    check(about["turns"] == 7 and {t["where"] for t in about["list"]} == {"margin", "planner"}
          and all(t["names"]["task:" + key] == "write the intro" for t in about["list"]),
          f"a task's turns, wherever said: its margin (first reply, chat, a failed answer) and the planner ({about['turns']})")

    # The forgetting this is for: yesterday's margin, known in today's day chat.
    agent("day", "--message", "where was I with this?", "--block", th)
    pay = calls()[-1]["stdin"]
    check("# Elsewhere in your one conversation" in pay and "## About the task “write the intro”" in pay
          and "Longhand: Yes: cut the second paragraph." in pay and "with the planner] student: not on Wednesday, I have lab" in pay,
          "a task talked about in yesterday's margin, and with the planner, is known in today's day chat when its block is pointed at")
    check("SECRET-OF-THE-DIARY" not in pay and "what did I write about my own thing?" not in pay,
          "what was said about a note marked private is carried nowhere")
    check("timed out" not in pay and "Longhand: \n" not in pay, "…and a failed answer is not said as one")
    log = vault / "agents" / "longhand" / "conversation"
    mine = [json.loads(l) for l in (log / "here.jsonl").read_text().splitlines()]
    check([t["text"] for t in mine[-2:]] == ["where was I with this?", f"answer {len(calls()) - 1}"]
          and mine[-1]["subjects"] == [f"day:{today}", "task:" + key, f"block:{today}:{th}"]
          and not (log / "there.jsonl").exists(),
          f"a message's turns reach the log, the answer about what was asked, written by this machine only ({mine[-1]['subjects']})")
    agent("day", "--message", "and then?")
    again = calls()[-1]["argv"][-1]
    check("cut the second paragraph" not in again and "Elsewhere" not in again and "Since then" not in again,
          "a later message is not given again what its session has")

    # A note's chat, which saw nothing of the others: what was said today.
    agent("note", "--file", "human/Studies/open.md", "--message", "how many interviews?")
    pay = calls()[-1]["stdin"]
    check("## Elsewhere today" in pay and "in the day's chat] student: where was I with this?" in pay
          and "SECRET-OF-THE-DIARY" not in pay and pay.rstrip().endswith("how many interviews?"),
          "a note's chat is told what was said elsewhere today, before the student's words")
    # A box under the task is the same subject; the margin of today's block
    # knows the day's chat about it and yesterday's margin.
    ctx = agent("context", "--trigger", "question", "--hash", th).stdout
    check("## About the task “write the intro”" in ctx and "student: is mine too long?" in ctx
          and "in the day's chat] student: where was I with this?" in ctx,
          "today's block of the same task carries yesterday's margin and today's day chat about it")
    sub = next(b for b in blocks.split((daily_notes / f"{yday}.md").read_text()) if "cut the second" in b["text"])
    check(sub["hash"] == yh, "(the box under it is in the task's block)")
    c = convo_(env=there)
    check(c["hosts"].get("here", 0) >= 15 and "there" not in c["hosts"], f"the other machine reads it all, having written none ({c['hosts']})")

    # Slice 2: a message points at several things (the chips above the
    # box) — a task of another day by its line, a block of today's by its
    # hash; what may not be shown is counted, never shown.
    note_today = daily_notes / f"{today}.md"
    note_today.write_text(note_today.read_text() + "\n> [!private]\n> - [ ] SECRET-BOX of my own\n")
    line_today = next(b for b in blocks.split(note_today.read_text()) if "A line of today" in b["text"])["hash"]
    secret = next(b for b in blocks.split(note_today.read_text()) if "SECRET-BOX" in b["text"])["hash"]
    agent("day", "--message", "these two together?", "--refs", json.dumps([
        {"date": str(yday), "line": 2}, {"date": str(today), "hash": line_today}, {"date": str(today), "hash": secret}]))
    msg = calls()[-1]["argv"][-1]
    check("# The blocks the student points at" in msg and f"In the note of {yday} (a task):" in msg
          and "> - [ ] write the intro" in msg and "In today's note:" in msg and "> A line of today." in msg,
          "a message points at several things: a task of another day, a block of today's")
    check("SECRET-BOX" not in msg and "(1 more they pointed at cannot be shown to you" in msg,
          "…a private one is counted, never shown")
    st = json.loads((agent_dir / "daily" / f"{today}.json").read_text())["day"]["turns"][-2]
    check([(r["date"], r["kind"], r["head"]) for r in st["refs"]] == [(str(yday), "task", "write the intro"), (str(today), "block", "A line of today.")]
          and st["block"] == line_today, f"…the turn keeps what it pointed at, for its chips ({st.get('refs')})")
    last = [json.loads(l) for l in (log / "here.jsonl").read_text().splitlines()][-1]
    check(last["role"] == "agent" and "task:" + key in last["subjects"] and f"block:{yday}:{yh}" in last["subjects"]
          and f"block:{today}:{line_today}" in last["subjects"], f"…and is about all of it in the log ({last['subjects']})")

    # …a note or a paper, only one the agent may see anyway: a private note
    # is talked about in its own chat, never through @ (2026-11-18).
    (studies / "paper.pdf").write_bytes(b"%PDF-1.4\n%%EOF\n")
    files = json.loads(agent("conversation", "--files").stdout)["files"]
    rels = {f["rel"]: f["kind"] for f in files}
    check(rels.get("human/Studies/open.md") == "note" and rels.get("human/Studies/paper.pdf") == "paper"
          and "human/Studies/closed.md" not in rels and not any(r.startswith("human/Daily/") for r in rels),
          f"@ may offer the notes and papers the agent may see, never a private one, never a daily note ({sorted(rels)})")
    agent("day", "--message", "and these?", "--refs", json.dumps([
        {"file": "human/Studies/open.md"}, {"file": "human/Studies/paper.pdf"}, {"file": "human/Studies/closed.md"}]))
    msg = calls()[-1]["argv"][-1]
    check("# The note the student points at: Methods (`human/Studies/open.md`)" in msg and "Interviews, twelve of them." in msg
          and "# The paper the student points at: paper (`human/Studies/paper.pdf`)" in msg and '"file": "human/Studies/paper.pdf"' in msg,
          "a note pointed at comes whole; a paper by its name, to be read when asked")
    check("Something of my own" not in msg and "(1 more they pointed at cannot be shown to you" in msg,
          "…a private note pointed at is counted, never shown")
    st = json.loads((agent_dir / "daily" / f"{today}.json").read_text())["day"]["turns"][-2]
    last = [json.loads(l) for l in (log / "here.jsonl").read_text().splitlines()][-1]
    check([(r["kind"], r["head"]) for r in st["refs"]] == [("note", "Methods"), ("paper", "paper")]
          and "note:human/Studies/open.md" in last["subjects"] and "paper:human/Studies/paper.pdf" in last["subjects"],
          f"…the turn keeps them, and the log has it about the note and the paper ({last['subjects']})")

    # A block's chat points at more than its block (`chat --refs`): the
    # message carries it, the turn keeps it, the log files it under it.
    agent("chat", "--hash", th, "--message", "and the methods note?", "--date", str(today),
          "--refs", json.dumps([{"file": "human/Studies/open.md"}]))
    pay = calls()[-1]["stdin"] or calls()[-1]["argv"][-1]
    check("# The note the student points at: Methods (`human/Studies/open.md`)" in pay and "Interviews, twelve of them." in pay,
          "a block's chat may point at a note too, carried with the message")
    rec = json.loads((agent_dir / "daily" / f"{today}.json").read_text())["blocks"][th]
    asked = next(x for x in rec["chat"] if x.get("text") == "and the methods note?")
    last = [json.loads(l) for l in (log / "here.jsonl").read_text().splitlines()]
    said = next(x for x in last if x["text"] == "and the methods note?")
    check(asked.get("refs") == [{"file": "human/Studies/open.md", "kind": "note", "head": "Methods"}]
          and "note:human/Studies/open.md" in said["subjects"] and "task:" + key in said["subjects"],
          f"…the turn keeps it, and the log files the message under the task and the note ({said['subjects']})")

    # The pane's "everything": earlier days a line each with their places,
    # today's places other than the day's own chat.
    v = convo_("--view")
    yd = v["days"][-1]
    names = {(g["kind"], g["name"]): g for g in yd["groups"]}
    check(v["today"] == str(today) and yd["date"] == str(yday) and yd["turns"] == 10
          and ("day", "the day's chat") not in names and names[("task", "write the intro")]["open"]["kind"] == "task"
          and names[("task", "write the intro")]["open"]["key"] == key,
          f"everything: an earlier day's other places a line each, saying how to open what it is about ({sorted(names)})")
    check([(t["where"], t["role"], t["text"]) for t in yd["said"]]
          == [("open", "agent", "The essay is due Friday."), ("day", "student", "what did I miss?"), ("day", "agent", "Nothing due.")]
          and "refs" in yd["said"][1] and "refs" not in yd["said"][2],
          f"…and its own chat said whole, what was said on opening too, a message with what it pointed at, "
          f"for the page to draw above today's ({yd['said']})")
    tg = {(g["kind"], g["name"]): g for g in v["groups"]}
    check(("note", "Methods") in tg and tg[("note", "Methods")]["open"] == {"kind": "file", "rel": "human/Studies/open.md"}
          and tg[("note", "Methods")]["role"] == "agent" and not any(g["where"] == "day" for g in v["groups"]),
          f"…and today's other places, never the day's own chat ({sorted(tg)})")
    # Slice 3, one voice: what planning proposed, still open, is a line of
    # the conversation of its own, opening the dashboard's list.
    led_path = pathlib.Path(here["XDG_STATE_HOME"]) / "longhand" / "proposals.json"
    led = json.loads(led_path.read_text())
    led["items"] = [{"id": 1, "kind": "do-date", "key": key, "title": "write the intro", "date": str(today),
                     "why": "w", "status": "open", "at": f"{today}T07:00:00"},
                    {"id": 2, "kind": "drop", "key": key, "title": "x", "why": "w", "status": "open",
                     "at": f"{today}T07:00:00", "from": "day"}]
    led_path.write_text(json.dumps(led))
    v2 = convo_("--view")
    asks = [g for g in v2["groups"] if g["kind"] == "proposals"]
    check(len(asks) == 1 and asks[0]["turns"] == 1 and asks[0]["open"] == {"kind": "asks"}
          and "write the intro" in asks[0]["text"],
          f"one voice: what planning proposed, still open, is a line of the conversation (not what a chat proposed) ({asks})")

    # Recall: the student points back at yesterday; the agent asks for it
    # and gets it in the same session, the turn keeps what it looked at.
    (stub / "recall.json").write_text(json.dumps([{"day": str(yday)}, {"words": "nothing like this anywhere"}]))
    agent("day", "--message", "like we said yesterday, which one first?")
    follow = calls()[-1]
    text = follow["stdin"] or follow["argv"][-1]
    check("# What you asked for" in text and f"## From your one conversation, on {yday}" in text
          and "in the day's chat] student: what did I miss?" in text and "Yes: cut the second paragraph." in text
          and "(nothing found)" in text and "SECRET-OF-THE-DIARY" not in text,
          "recall: yesterday's turns, wherever said, given in the same session; nothing found is said")
    first = next(c for c in calls() if "where was I with this?" in (c["stdin"] or c["argv"][-1]))
    check(f"today: {today.isoformat()} ({today:%A})" in (first["stdin"] or first["argv"][-1]),
          "…the payload says today's date, so the agent knows which day yesterday was")
    day_state = json.loads((agent_dir / "daily" / f"{today}.json").read_text())["day"]
    rec = day_state["turns"][-1]
    check(rec.get("recalled") == [{"day": str(yday), "words": "", "turns": 9},
                                  {"day": "", "words": "nothing like this anywhere", "turns": 0}],
          f"…and the answer keeps what it looked back at, an answer that failed not counted ({rec.get('recalled')})")

    # "About this": what was said about a task outside its own chat.
    e = json.loads(agent("conversation", "--elsewhere", "--task", key, "--date", str(yday), "--hash", yh).stdout)
    said = [(t["where"], t["text"]) for t in e["turns"]]
    check(("day", "where was I with this?") in said and ("day", "these two together?") in said
          and not any(w == "planner" or x in ("is mine too long?", "Yes: cut the second paragraph.") for w, x in said)
          and e["turns"][0]["place"] == "in the day's chat",
          f"about this: what the day's chat said about a task, not its own margin or the planner ({said})")


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="convo-test-"))
    try:
        store(tmp)
        runner(tmp)
    finally:
        shutil.rmtree(tmp)
    print("FAIL" if FAILS else "PASS")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
