"""The planning job and its ledger (docs/agent.md, slice 2): what is
offered to the model, what it may answer, what is kept of it, and what
came of each proposal — against a stub model, a throwaway vault and store.

Run: python3 tests/test_plan.py
"""
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
import timetable  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# A model that answers from a file, and counts its calls.
STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
if sys.argv[1:2] == ["session"]:
    print(json.dumps({"info": {"cost": 0.001, "tokens": {"input": 9, "output": 3, "reasoning": 0}}})); sys.exit(0)
n = int(open(os.path.join(d, "calls")).read()) if os.path.exists(os.path.join(d, "calls")) else 0
open(os.path.join(d, "calls"), "w").write(str(n + 1))
if os.path.exists(os.path.join(d, "sleep")):
    import time; time.sleep(float(open(os.path.join(d, "sleep")).read()))
open(os.path.join(d, "argv.json"), "w").write(json.dumps(sys.argv[1:]))
open(os.path.join(d, "payload.md"), "w").write(sys.stdin.read())
queue = os.path.join(d, "replies.json")
if os.path.exists(queue):
    rs = json.load(open(queue)); reply = json.dumps(rs.pop(0))
    json.dump(rs, open(queue, "w")) if rs else os.remove(queue)
else:
    reply = open(os.path.join(d, "reply.json")).read()
ev = lambda t, part: print(json.dumps({"type": t, "sessionID": "ses_plan", "part": part}))
ev("text", {"type": "text", "text": "```json\\n" + reply + "\\n```"})
ev("step_finish", {"type": "step-finish", "cost": 0.0003, "tokens": {"input": 200, "output": 40, "reasoning": 0, "total": 240}})
"""

TODAY = dt.date.today()


def day(n):
    return (TODAY + dt.timedelta(days=n)).isoformat()


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="plan-test-"))
    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    know = vault / "agents/longhand/knowledge"
    (know / "projects").mkdir(parents=True)
    (know / "projects/intsem.md").write_text("# Interdisciplinary Seminar\n\n- Tag: `#intsem`\n- Course code: M_IC_IntSem_W26\n")
    note = daily / f"{TODAY.isoformat()}.md"
    note.write_text(
        "# Interdisciplinary Seminar #intsem\n\n"
        "- [ ] read the paper ⏫\n"
        f"- [ ] essay draft 📅 {day(5)}\n"
        "- [ ] a passing thought\n"
        f"- [ ] has a date already ⏳ {day(2)}\n"
        "\n> [!private]\n> - [ ] a secret task ⏫\n")
    before = note.read_text()
    state = tmp / "state"
    cfgdir = tmp / "config"
    cfgdir.mkdir()
    cfg = cfgdir / "config.json"
    url = "https://uni.example/feed.ics?token=SECRET"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "calendars": [{"name": "IT:U", "url": url, "agent": "classes"}]}))
    # A calendar copy as a fetch would leave it: a class tomorrow, and an
    # event that is not a class (which "classes only" keeps from the agent).
    tomorrow = TODAY + dt.timedelta(days=1)
    cache = timetable.cache_path(state / "longhand", url)
    cache.parent.mkdir(parents=True)
    cache.write_text("BEGIN:VCALENDAR\r\n"
                     f"BEGIN:VEVENT\r\nUID:a\r\nDTSTART:{tomorrow:%Y%m%d}T104500\r\nDTEND:{tomorrow:%Y%m%d}T121500\r\n"
                     "SUMMARY:Seminar M_IC_IntSem_W26\r\nEND:VEVENT\r\n"
                     f"BEGIN:VEVENT\r\nUID:b\r\nDTSTART:{tomorrow:%Y%m%d}T180000\r\nDTEND:{tomorrow:%Y%m%d}T200000\r\n"
                     "SUMMARY:Dinner with a friend\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    cache.with_suffix(".json").write_text(json.dumps({"fetched": 1, "source": timetable._source(url)}))
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    def calls():
        f = stub / "calls"
        return int(f.read_text()) if f.exists() else 0

    def ledger():
        return json.loads((state / "longhand" / "proposals.json").read_text())["items"]

    # The first plan: what is offered.
    (stub / "reply.json").write_text(json.dumps({"proposals": [], "questions": [], "knowledge": []}))
    out = json.loads(agent("plan").stdout)
    check(out["ran"] and calls() == 1, f"the first plan of the day runs ({out})")
    argv = json.loads((stub / "argv.json").read_text())
    check(argv[argv.index("--agent") + 1] == "longhand-plan", "…as the planner, an agent of its own (no tools)")
    check("--model" not in argv, "…on the agent's own model when none is set")
    payload = (stub / "payload.md").read_text()
    logged = sorted((state / "longhand" / "payloads").glob("*-plan.md"))
    check(logged and logged[-1].read_text() == payload, "the payload is logged, whole, before inference")
    data = json.loads(re.search(r"```json\n(.*?)\n```", payload, re.S).group(1))
    titles = [c["title"] for c in data["candidates"]]
    check("read the paper" in titles and "essay draft" in titles,
          f"tasks and deadlines with no do-date are offered ({titles})")
    check("a passing thought" not in titles, "…not a note box: that is thinking, not work to schedule")
    check("has a date already" not in titles, "…not one that already has a do-date")
    check("secret" not in payload, "…and nothing private, anywhere in the payload")
    d1 = data["fortnight"][1]
    check(d1["on"] == ["10:45–12:15 Interdisciplinary Seminar"] and d1["free_hours"] == 7.5,
          f"the fortnight is computed: tomorrow's class named by its course, the free hours left ({d1})")
    check("Dinner" not in payload, "…and an event that is not a class, from a calendar shared for classes only, is not shown")
    check(len(data["fortnight"]) == 14 and data["fortnight"][0]["date"] == TODAY.isoformat(), "…fourteen days from today")
    check(any(w["project"] == "intsem" for w in data["workload"]), "workload per project is computed")
    key = {c["title"]: c["key"] for c in data["candidates"]}

    # The same day, nothing changed: no second plan.
    out = json.loads(agent("plan").stdout)
    check(not out["ran"] and calls() == 1, f"the same unchanged fortnight is not planned twice a day ({out['why']})")

    # What the model says, checked.
    (stub / "reply.json").write_text(json.dumps({
        "proposals": [
            {"kind": "do-date", "key": key["read the paper"], "date": day(3), "why": "Wednesday is free."},
            {"kind": "do-date", "key": key["essay draft"], "date": day(7), "why": "after its due date"},
            {"kind": "do-date", "key": "not a key", "date": day(2), "why": "invented"},
            {"kind": "do-date", "key": key["read the paper"], "date": day(4), "why": "a second for the same box"},
            {"kind": "do-date", "key": key["essay draft"], "date": day(30), "why": "outside the fortnight"},
        ],
        "questions": [
            {"key": key["essay draft"], "question": "Which essay is this — Design Theory's?", "recommended": "Design Theory, essay 2"},
            {"key": "", "question": "Do you work on weekends?", "recommended": "No"},
            {"key": "", "question": "A third question", "recommended": "too many"},
            {"key": "invented", "question": "About nothing", "recommended": "x"},
        ],
        "knowledge": [{"file": "patterns.md", "content": "- plans on Wednesdays"}, {"file": "answers.md", "content": "forged"}],
    }))
    out = json.loads(agent("plan", "--force").stdout)
    check(out["ran"] and out["proposals"] == 1 and out["questions"] == 2,
          f"--force plans now; only what holds is kept: one do-date, two questions ({out})")
    items = ledger()
    dd = [x for x in items if x["kind"] == "do-date"]
    check(len(dd) == 1 and dd[0]["date"] == day(3) and dd[0]["why"] == "Wednesday is free.",
          "never after a box's own due date, never an unknown box, one per box, inside the fortnight")
    check([x["question"] for x in items if x["kind"] == "question"] ==
          ["Which essay is this — Design Theory's?", "Do you work on weekends?"], "at most two questions, each about a box offered or none")
    check((know / "patterns.md").read_text().strip() == "- plans on Wednesdays", "its knowledge files are written as always")
    check(not (know / "answers.md").exists(), "…but never answers.md, which is the student's")
    check(note.read_text() == before, "planning writes nothing into a note")
    check(any("\tplan\t" in l for l in (state / "longhand" / "cost.tsv").read_text().splitlines()), "the run's cost is in the ledger")

    # The dashboard's view.
    got = json.loads(agent("proposals").stdout)
    p = next(x for x in got["open"] if x["kind"] == "do-date")
    check(got["count"] == 3 and p["where"]["date"] == TODAY.isoformat() and "read the paper" in p["where"]["text"],
          f"open proposals, each with where its box is ({p['where']})")

    # Answers.
    q1, q2 = [x for x in got["open"] if x["kind"] == "question"]
    agent("proposal", "accept", "--id", str(q1["id"]))
    agent("proposal", "answer", "--id", str(q2["id"]), "--answer", "Sometimes, Sundays")
    answers = (know / "answers.md").read_text()
    check("Which essay is this — Design Theory's? → Design Theory, essay 2" in answers,
          "accepting a question answers it with the recommended answer, kept in answers.md")
    check("Do you work on weekends? → Sometimes, Sundays" in answers, "…or with the student's own")
    payload_again = None
    agent("proposal", "decline", "--id", str(p["id"]))
    check(next(x for x in ledger() if x["id"] == p["id"])["status"] == "declined", "a do-date declined is recorded")
    r = agent("proposal", "decline", "--id", str(p["id"]))
    check('"changed": false' in r.stdout, "…once")

    # A declined day is not proposed again; a new plan supersedes what was open.
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "do-date", "key": key["read the paper"], "date": day(3), "why": "again"},
        {"kind": "do-date", "key": key["essay draft"], "date": day(2), "why": "Tuesday is free"}],
        "questions": [], "knowledge": []}))
    out = json.loads(agent("plan", "--force").stdout)
    check(out["proposals"] == 1, "the day the student declined for a box is not proposed again")
    payload_again = (stub / "payload.md").read_text()
    check("Sometimes, Sundays" in payload_again and "never ask them again" in payload_again,
          "the student's answers go to every plan after")
    check('"declined": 1' in payload_again, "…and the record of what came of its proposals")
    essay = next(x for x in ledger() if x["kind"] == "do-date" and x["status"] == "open")
    agent("proposal", "accept", "--id", str(essay["id"]))
    got = json.loads(agent("proposals").stdout)
    check({"key": key["essay draft"], "date": day(2)} in got["accepted"], "an accepted do-date is listed for its pill's tint")

    # Moot: the box got a date some other way.
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "do-date", "key": key["read the paper"], "date": day(4), "why": "Thursday"}], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    note.write_text(note.read_text().replace("- [ ] read the paper ⏫", f"- [ ] read the paper ⏳ {day(6)} ⏫"))
    got = json.loads(agent("proposals").stdout)
    check(got["count"] == 0 and any(x["status"] == "moot" for x in ledger()),
          "a do-date whose box got a date some other way is settled as moot")

    # Stats.
    st = agent("stats", "--since", TODAY.isoformat()).stdout
    check("Agent proposals: do-dates 1/2 accepted" in st and "questions 2 answered" in st,
          f"stats counts what came of them ({[l for l in st.splitlines() if 'proposals' in l]})")

    # Install: both agents, both without tools.
    agent("install")
    agents = cfgdir / "opencode" / "agent"
    plan_def = (agents / "longhand-plan.md").read_text() if (agents / "longhand-plan.md").exists() else ""
    check((agents / "longhand.md").exists() and '"*": deny' in plan_def and "read: false" in plan_def,
          "install writes the planner's definition beside the margin's, every tool denied")

    # Talking about a proposal (2026-10-20): the planner answers, given the
    # plan it made; each box has one conversation, which the boxes under it
    # share; a revision is checked like a plan; an agreement settles it.
    note.write_text(note.read_text() + "\n# Poster #intsem\n\n- [ ] make the poster ⏫\n  - [ ] find images 🔽\n")
    (stub / "reply.json").write_text(json.dumps({"proposals": [], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    data = json.loads(re.search(r"```json\n(.*?)\n```", (stub / "payload.md").read_text(), re.S).group(1))
    poster = next(c["key"] for c in data["candidates"] if c["title"] == "make the poster")
    images = next(b["key"] for b in data["open_boxes"] if b["title"] == "find images")
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "do-date", "key": poster, "date": day(3), "why": "the day after the seminar"},
        {"kind": "priority", "key": images, "priority": 1, "why": "the poster needs them"}],
        "questions": [{"key": "", "question": "Is the poster A1?", "recommended": "Yes"}], "knowledge": []}))
    agent("plan", "--force")
    plan_payload = (stub / "payload.md").read_text()
    got = json.loads(agent("proposals").stdout)
    dd = next(x for x in got["open"] if x["kind"] == "do-date" and x["key"] == poster)
    pr = next(x for x in got["open"] if x["kind"] == "priority")
    qq = next(x for x in got["open"] if x["kind"] == "question")
    check(dd["thread"] == pr["thread"] == poster, f"a box and the box under it share one conversation ({pr['thread']!r})")

    def talk(pid, words, **reply):
        (stub / "reply.json").write_text(json.dumps(dict({"reply": "", "revise": None, "settle": None, "knowledge": []}, **reply)))
        return agent("talk", "--id", str(pid), "--message", words, ok=False)

    r = talk(dd["id"], "why Wednesday?", reply="It is the day after the seminar, while it is fresh.")
    out = json.loads(r.stdout)
    check(r.returncode == 0 and out["reply"].startswith("It is the day after") and not out["revised"] and out["settle"] == "",
          f"the planner answers, and nothing changes on its own ({out})")
    argv = json.loads((stub / "argv.json").read_text())
    talked = (stub / "payload.md").read_text()
    check(argv[argv.index("--agent") + 1] == "longhand-plan" and "talk with you about one of your proposals" in argv[-1],
          "…as the planner, told it is a conversation")
    check(talked.startswith(plan_payload.rstrip()) and "# The student says now\n\nwhy Wednesday?" in talked,
          "…given the very plan it made, then what the student says")
    check(sorted((state / "longhand" / "payloads").glob(f"*-talk-{dd['id']}.md"))[-1].read_text() == talked,
          "…the payload logged, whole")
    turns = json.loads(agent("proposals").stdout)["threads"][poster]
    check([t["role"] for t in turns] == ["student", "agent"] and turns[0]["text"] == "why Wednesday?",
          "the conversation is kept on the box, both turns")
    check(talked.rstrip().endswith("`reply` is never empty."), "…the talk's own format said again, where it is read last")

    # Answered with a plan (2026-10-20 and 10-23, both real talks): asked
    # again once in the same session; still a plan, and the student is told.
    plan_shaped = {"proposals": [], "questions": [], "knowledge": []}
    (stub / "replies.json").write_text(json.dumps([plan_shaped, {"reply": "T moves it; I can only change the do-date.",
                                                                 "revise": None, "settle": None, "knowledge": []}]))
    out = json.loads(agent("talk", "--id", str(dd["id"]), "--message", "change its due date").stdout)
    argv = json.loads((stub / "argv.json").read_text())
    check(out["reply"].startswith("T moves it") and "--session" in argv and "answered with a plan" in argv[-1],
          f"a plan for an answer is asked for again, once, in the same session ({out['reply']!r})")
    (stub / "replies.json").write_text(json.dumps([plan_shaped, plan_shaped]))
    out = json.loads(agent("talk", "--id", str(dd["id"]), "--message", "change its due date").stdout)
    check(out["reply"] == "" and "answered with a plan" in out["turns"][-1]["text"],
          f"…and twice a plan is said as that, never as nothing to add ({out['turns'][-1]['text']!r})")

    r = talk(dd["id"], "I have lab on Wednesday, Thursday instead",
             reply="Thursday then.", revise={"kind": "do-date", "key": poster, "date": day(4), "why": "Wednesday is lab"})
    out = json.loads(r.stdout)
    old, new = (next(x for x in ledger() if x["id"] == i) for i in (dd["id"], out["current"]))
    check(out["revised"] and old["status"] == "revised" and new["status"] == "open" and new["date"] == day(4)
          and new["revises"] == dd["id"], f"a revision replaces the proposal: the old revised, the new open ({out})")
    r = talk(pr["id"], "they are already found", reply="Fine.",
             revise={"kind": "priority", "key": images, "priority": 9, "why": "x"})
    check(not json.loads(r.stdout)["revised"], "a revision that fails the plan's checks is not kept")
    check("why Wednesday?" in (stub / "payload.md").read_text() and "Thursday then." in (stub / "payload.md").read_text(),
          "talking about the box under it carries the same conversation")
    r = talk(pr["id"], "no need for a priority, drop it", reply="Agreed, no priority.", settle="decline")
    out = json.loads(r.stdout)
    p2 = next(x for x in ledger() if x["id"] == pr["id"])
    check(out["settle"] == "decline" and p2["status"] == "declined" and p2["reason"] == "no need for a priority, drop it",
          f"agreeing to drop it declines it, the student's words kept as the reason ({p2.get('reason')!r})")
    r = talk(new["id"], "ok, Thursday works", reply="Good.", settle="accept")
    out = json.loads(r.stdout)
    n2 = next(x for x in ledger() if x["id"] == new["id"])
    check(out["settle"] == "accept" and n2["status"] == "open" and n2["agreed"]["how"] == "accept",
          "agreeing to it is told to the page, which writes it as any accept does")
    agent("proposal", "accept", "--id", str(new["id"]))
    n2 = next(x for x in ledger() if x["id"] == new["id"])
    check(n2["status"] == "accepted" and n2["reason"] == "ok, Thursday works", "…and the acceptance keeps the words")
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "do-date", "key": images, "date": day(3), "why": "before the poster"}], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    im = next(x for x in ledger() if x["kind"] == "do-date" and x["key"] == images and x["status"] == "open")
    out = json.loads(talk(im["id"], "Friday please", reply="Friday it is.", settle="accept",
                          revise={"kind": "do-date", "key": images, "date": day(5), "why": "you asked for Friday"}).stdout)
    check(out["revised"] and out["settle"] == "accept" and out["current"] != im["id"],
          "revised to what they asked, and agreed, in one answer")
    agent("proposal", "accept", "--id", str(out["current"]))
    check(next(x for x in ledger() if x["id"] == out["current"]).get("reason") == "Friday please",
          "…the words said about the proposal it revised are its reason")
    # A question, talked through: the agreed answer is what is kept.
    out = json.loads(talk(qq["id"], "what sizes are there?", reply="A1 or A0; the brief says A1.").stdout)
    check(out["kind"] == "question" and not out["resolved"] and out["thread"] == "?is the poster a1",
          f"a question is talked about too, in a conversation of its own ({out['thread']!r})")
    check("one of your questions" in json.loads((stub / "argv.json").read_text())[-1], "…the planner told it is its question")
    out = json.loads(talk(qq["id"], "then A1, but landscape", reply="Noted.", settle="accept",
                          answer="A1, landscape").stdout)
    q2 = next(x for x in ledger() if x["id"] == qq["id"])
    check(out["resolved"] and q2["status"] == "answered" and q2["answer"] == "A1, landscape"
          and "Is the poster A1? → A1, landscape" in (know / "answers.md").read_text(),
          "agreeing answers it, settled at once, the agreed answer kept for the agent")
    check([u["text"] for u in out["turns"]][-2:] == ["then A1, but landscape", "Noted."], "…the conversation handed back, for the margin")
    # Something it did on its own, talked about: let stand here, undone by the page.
    c = json.loads(cfg.read_text())
    cfg.write_text(json.dumps(dict(c, autonomy={"priority": "do"})))
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "priority", "key": key["essay draft"], "priority": 2, "why": "due in five days"}], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    auto = next(x for x in ledger() if x["kind"] == "priority" and x.get("auto") and x["status"] == "open")
    agent("proposal", "applied", "--id", str(auto["id"]))
    out = json.loads(talk(auto["id"], "why high?", reply="It is due in five days.").stdout)
    check(out["kind"] == "priority" and "already did on your own" in json.loads((stub / "argv.json").read_text())[-1],
          "what it did on its own is talked about too, as done")
    out = json.loads(talk(auto["id"], "please take it off", reply="Taking it off.", settle="decline").stdout)
    check(out["settle"] == "decline" and not out["resolved"] and next(x for x in ledger() if x["id"] == auto["id"])["status"] == "told",
          "…agreeing to undo it leaves the undo to the page")
    agent("proposal", "undo", "--id", str(auto["id"]))
    check(next(x for x in ledger() if x["id"] == auto["id"])["status"] == "undone", "…which records it as any undo")
    cfg.write_text(json.dumps(c))
    check(agent("talk", "--id", str(pr["id"]), "--message", "hm", ok=False).returncode == 2, "…nor a settled proposal")
    (stub / "reply.json").write_text(json.dumps({"proposals": [], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    data = json.loads(re.search(r"```json\n(.*?)\n```", (stub / "payload.md").read_text(), re.S).group(1))
    conv = next((c for c in data.get("conversations", []) if c["key"] == poster), None)
    check(conv is not None and {"who": "student", "said": "ok, Thursday works"} in conv["turns"],
          f"the next plan knows what was said about the box ({conv})")
    agent("proposal", "decline", "--id", str(qq["id"]))

    # A task's one conversation (2026-10-20): the margin's turns about its
    # box and the planner's, merged by time, summoned from the dashboard;
    # and the margin agent, answering there, knows what the planner heard.
    sys.path.insert(0, str(ROOT / "agent"))
    import blocks as blocklib
    blk = next(b for b in blocklib.split(note.read_text()) if b["text"].startswith("- [ ] make the poster"))
    day_state = vault / "agents/longhand/daily" / f"{TODAY.isoformat()}.json"
    day_state.parent.mkdir(parents=True, exist_ok=True)
    st = json.loads(day_state.read_text()) if day_state.exists() else {"date": TODAY.isoformat(), "blocks": {}, "suggestions": [], "runs": []}
    st.setdefault("blocks", {})[blk["hash"]] = {
        "state": "reply", "reply": "A poster wants its argument first.", "at": "2000-01-01T09:00:00", "session": "",
        "chat": [{"role": "student", "text": "where do I start?", "at": "2000-01-01T09:05:00"},
                 {"role": "agent", "text": "With the one sentence it argues.", "at": "2000-01-01T09:05:00"}]}
    day_state.write_text(json.dumps(st))
    th = json.loads(agent("thread", "--key", images).stdout)
    texts = [t["text"] for t in th["turns"]]
    check(th["thread"] == poster and th["chat"] == {"date": TODAY.isoformat(), "hash": blk["hash"]},
          f"a box under another summons the conversation of the box it is under, which takes messages in the margin ({th['chat']})")
    check(texts[:3] == ["A poster wants its argument first.", "where do I start?", "With the one sentence it argues."]
          and "why Wednesday?" in texts and [t["who"] for t in th["turns"]][:3] == ["margin"] * 3,
          "…the margin's turns and the planner's, one conversation, in the order said")
    th2 = json.loads(agent("thread", "--id", str(dd["id"])).stdout)
    check(th2["turns"] == th["turns"], "a proposal's conversation is the same one")
    (stub / "reply.json").write_text(json.dumps({"reply": "Start with the sentence, then the images."}))
    agent("chat", "--hash", blk["hash"], "--message", "and the images?", "--date", TODAY.isoformat())
    told_margin = (stub / "payload.md").read_text()
    check("# This box with the planner" in told_margin and "student: I have lab on Wednesday" in told_margin,
          "the margin agent, answering about the box, reads what was said with the planner")
    th = json.loads(agent("thread", "--key", poster).stdout)
    check([t["text"] for t in th["turns"]][-2:] == ["and the images?", "Start with the sentence, then the images."],
          "…and its answer joins the one conversation")
    # Each row's chat, in brief (slice 2 of docs/keys-proposal.md): the same
    # one conversation, its size and its last turn, for the dashboard.
    nxt = {t["key"]: t for t in json.loads(agent("next", "--days", "7").stdout)["tasks"]}
    ch = nxt[poster].get("chat")
    check(ch is not None and ch["turns"] == len(th["turns"]) and ch["role"] == "agent" and ch["who"] == "margin"
          and ch["text"] == "Start with the sentence, then the images." and ch["hash"] == blk["hash"] and ch["at"]
          and ch["thread"] == poster,
          f"next gives a task its chat: how many turns, and the last one ({ch})")
    check(nxt[images].get("chat") == ch, "…a box under it shares the one it is under")
    quiet = [k for k, t in nxt.items() if k not in (poster, images) and not t.get("private")]
    check(quiet and all("chat" not in nxt[k] for k in quiet if not any(
          x.get("key") == k for x in ledger())), "…and a box never talked about has none")
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "do-date", "key": poster, "date": day(6), "why": "after the lab"}], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    later = next(x for x in ledger() if x["kind"] == "do-date" and x["key"] == poster and x["status"] == "open")
    talk(later["id"], "could it be the weekend?", reply="Saturday works too.")
    (stub / "reply.json").write_text(json.dumps({"reply": "Then Saturday for the images."}))
    agent("chat", "--hash", blk["hash"], "--message", "ok", "--date", TODAY.isoformat())
    sent = json.loads((stub / "argv.json").read_text())[-1]
    check("--session" in json.loads((stub / "argv.json").read_text()) and "Meanwhile" in sent
          and "could it be the weekend?" in sent and "I have lab on Wednesday" not in sent and "after the lab" in sent,
          "…continuing its session, it is told only what it has not seen, and the open proposals")

    # A plan that fails (an expired key) is not today's plan: the next
    # opening tries again, rather than waiting for tomorrow.
    (stub / "reply.json").write_text("not json")
    (bindir / "opencode").write_text("#!/bin/sh\necho '{\"type\":\"error\",\"error\":\"This API key has expired\"}'\n")
    r = agent("plan", "--force", ok=False)
    check(r.returncode == 1 and "expired" in r.stdout, "a plan that fails says why")
    st = json.loads((state / "longhand" / "plan.json").read_text())
    check("hash" not in st and "expired" in st["error"], "…and is not counted as today's plan")
    (bindir / "opencode").write_text(STUB)

    # An answer given while a plan is thinking is kept: the plan reads the
    # ledger again before it writes (it wrote back what it read before the
    # model, and the answer was lost, 2026-10-25).
    (stub / "reply.json").write_text(json.dumps({"proposals": [],
        "questions": [{"key": "", "question": "Is the hall free on Friday?", "recommended": "Yes"}], "knowledge": []}))
    agent("plan", "--force")
    hall = next(x for x in ledger() if x.get("question") == "Is the hall free on Friday?")
    agent("plan", "--force")
    check([x["status"] for x in ledger() if x.get("question") == "Is the hall free on Friday?"] == ["open"],
          "a question asked again in the same words, while still open, is not recorded twice")
    (stub / "reply.json").write_text(json.dumps({"proposals": [], "questions": [], "knowledge": []}))
    (stub / "sleep").write_text("1.5")
    n = calls()
    slow = subprocess.Popen([sys.executable, str(AGENT), "plan", "--force"], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, env=env)
    for _ in range(50):
        if calls() > n:
            break
        time.sleep(0.05)
    agent("proposal", "accept", "--id", str(hall["id"]))
    slow.wait()
    (stub / "sleep").unlink()
    check(next(x for x in ledger() if x["id"] == hall["id"])["status"] == "answered",
          f"an answer given while a plan runs is kept ({next(x for x in ledger() if x['id'] == hall['id'])['status']})")

    # A model of its own for planning.
    c = json.loads(cfg.read_text())
    cfg.write_text(json.dumps(dict(c, planModel="openai/gpt-6-luna", model="opencode-go/deepseek", variant="high")))
    (stub / "reply.json").write_text(json.dumps({"proposals": [], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    argv = json.loads((stub / "argv.json").read_text())
    check(argv[argv.index("--model") + 1] == "openai/gpt-6-luna",
          f"planModel gives the planner its own model, without the margin's variant ({argv[argv.index('--model') + 1]})")
    cfg.write_text(json.dumps(c))

    # Prose alone is something to read now (a deadline may be in it, slice 5);
    # an empty week is nothing to plan: no model call.
    note.write_text("Just prose today.\n")
    n = calls()
    out = json.loads(agent("plan", "--force").stdout)
    check(out["ran"] and calls() == n + 1, "a week of prose with no box is read: a deadline may be in the writing")
    note.write_text("")
    n = calls()
    out = json.loads(agent("plan", "--force").stdout)
    check(not out["ran"] and calls() == n, f"with nothing to plan, no model is asked ({out.get('why')})")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
