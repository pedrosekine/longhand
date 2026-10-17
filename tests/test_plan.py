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
open(os.path.join(d, "argv.json"), "w").write(json.dumps(sys.argv[1:]))
open(os.path.join(d, "payload.md"), "w").write(sys.stdin.read())
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

    # A plan that fails (an expired key) is not today's plan: the next
    # opening tries again, rather than waiting for tomorrow.
    (stub / "reply.json").write_text("not json")
    (bindir / "opencode").write_text("#!/bin/sh\necho '{\"type\":\"error\",\"error\":\"This API key has expired\"}'\n")
    r = agent("plan", "--force", ok=False)
    check(r.returncode == 1 and "expired" in r.stdout, "a plan that fails says why")
    st = json.loads((state / "longhand" / "plan.json").read_text())
    check("hash" not in st and "expired" in st["error"], "…and is not counted as today's plan")
    (bindir / "opencode").write_text(STUB)

    # Nothing to plan: no model call.
    note.write_text("Just prose today.\n")
    n = calls()
    out = json.loads(agent("plan", "--force").stdout)
    check(not out["ran"] and calls() == n, f"with nothing to plan, no model is asked ({out['why']})")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
