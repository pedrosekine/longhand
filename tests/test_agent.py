"""The loop's guarantees, tested offline against a stub opencode.

Run: python3 tests/test_agent.py

- allowlist: a private block and a private day never reach the payload
- no-write: the daily note's bytes and mtime are untouched by a run
- apply: transcript, state, ledger, and knowledge land where they should,
  and a knowledge path outside the allowed names is ignored
- open: no model call when nothing is new
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import datetime as dt

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"

STUB = """#!/usr/bin/env python3
import json, sys
import os
os.makedirs(os.environ["STUB_DIR"], exist_ok=True)
open(os.path.join(os.environ["STUB_DIR"], "argv.json"), "w").write(
    json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd()}))
if sys.argv[1:2] == ["session"]:
    print(json.dumps({"info": {"cost": 0.5, "tokens": {"input": 7, "output": 3, "reasoning": 1}}}))
    sys.exit(0)
if os.environ.get("STUB_DEAF"):
    print("DESCRIPTION\\n  Run OpenCode with a message\\nERRORS\\n  Unrecognized flag")
    sys.exit(0)
payload = sys.stdin.read()
open(os.path.join(os.environ["STUB_DIR"], "last_payload.md"), "w").write(payload)
reply = json.loads(open(os.path.join(os.environ["STUB_DIR"], "reply.json")).read())
text = "```json\\n" + json.dumps(reply) + "\\n```"
ev = lambda t, part: print(json.dumps({"type": t, "sessionID": "ses_stub", "part": part}))
ev("step_start", {"type": "step-start"})
ev("text", {"type": "text", "text": text, "time": {"start": 1, "end": 2}})
if not os.environ.get("STUB_FREE"):
    ev("step_finish", {"type": "step-finish", "cost": 0.0002, "tokens": {"input": 100, "output": 20, "reasoning": 5, "total": 125}})
"""

# The test's "today" is the real today: the runner judges recency (the
# tasks panel, what's next) against the clock, so fixed dates go stale.
DAY = dt.date.today().strftime("%Y.%m.%d")
OLD_DAY = (dt.date.today() - dt.timedelta(days=60)).strftime("%Y.%m.%d")

NOTE = """---
agent: true
---
[[agents/longhand/daily/DAY|agent]]

Read the DORO brief again.

- [ ] draft the one-pager by friday

> [!private]
> SECRET-PRIVATE-LINE do not send

@ what did I say about DORO?
""".replace("DAY", DAY)


class T:
    def __init__(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-agent-test-"))
        self.vault = self.tmp / "vault"
        self.daily = self.vault / "inbox" / "Daily"
        self.daily.mkdir(parents=True)
        (self.vault / "human" / "_Secrets").mkdir(parents=True)
        (self.vault / "human" / "_Secrets" / "keys.md").write_text("SECRET-VAULT-FILE\n")
        self.note = self.daily / f"{DAY}.md"
        self.note.write_text(NOTE)
        self.cfg = self.tmp / "config.json"
        self.cfg.write_text(json.dumps({"vault": str(self.vault), "daily": {"dir": "inbox/Daily", "format": "YYYY.MM.DD"},
                                        "agentDir": "agents/longhand", "opencode": str(self.tmp / "bin" / "opencode")}))
        (self.tmp / "bin").mkdir()
        stub = self.tmp / "bin" / "opencode"
        stub.write_text(STUB)
        stub.chmod(0o755)
        pomo = self.tmp / "bin" / "pomo"
        pomo.write_text("#!/usr/bin/env python3\nimport sys, os, json\n"
                        "open(os.environ['STUB_DIR'] + '/pomo_args.json', 'w').write(json.dumps(sys.argv[1:]))\n"
                        "print('report' in sys.argv and '{}' or 'pomo: deadline #7 · Fri 18 Sep 17:00 · one-pager · DORO')\n")
        pomo.chmod(0o755)
        self.stub_dir = self.tmp / "stub"
        self.stub_dir.mkdir()
        self.state_home = self.tmp / "state"
        self.env = dict(os.environ, LONGHAND_CONFIG=str(self.cfg), XDG_STATE_HOME=str(self.state_home),
                        STUB_DIR=str(self.stub_dir), PATH=str(self.tmp / "bin") + ":" + os.environ["PATH"])
        # keep `pomo report` out of it: an empty PATH entry first means the real pomo is still found;
        # that is fine — its output is just another allowlisted source.

    def agent(self, *args):
        return subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=self.env)

    def set_reply(self, **kw):
        base = {"reply": "", "proposals": [], "suggestions": [], "knowledge": []}
        base.update(kw)
        (self.stub_dir / "reply.json").write_text(json.dumps(base))

    def cleanup(self):
        shutil.rmtree(self.tmp)


def _hash_of(t, line: str) -> str:
    """The hash the page would send for the block holding this line."""
    sys.path.insert(0, str(ROOT / "agent"))
    import blocks as blocklib
    for b in blocklib.split(t.note.read_text()):
        if line in b["text"]:
            return b["hash"]
    raise AssertionError("no block holds " + line)


def main() -> int:
    t = T()
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)
            print("FAIL", msg)
        else:
            print("ok  ", msg)

    try:
        # Hash of the "@" block, computed the same way the page does.
        sys.path.insert(0, str(ROOT / "agent"))
        import blocks
        blks = blocks.split(NOTE)
        at_block = next(b for b in blks if b["text"].startswith("@ "))
        priv = next(b for b in blks if b["private"] and b["kind"] == "callout")

        # 1. allowlist: context contains the note minus private, never the secrets folder
        r = t.agent("context", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0, f"context exits 0 ({r.stderr.strip()})")
        check("SECRET-PRIVATE-LINE" not in r.stdout, "private callout absent from payload")
        check("SECRET-VAULT-FILE" not in r.stdout, "vault secrets folder absent from payload")
        check(f"[[agents/longhand/daily/{DAY}|agent]]" not in r.stdout, "template link line absent from payload")
        check("Read the DORO brief again." in r.stdout and "draft the one-pager" in r.stdout, "visible blocks present")
        check(f"block: {at_block['hash']}" in r.stdout, "fired block named")

        # 2. a private block cannot be the trigger
        r = t.agent("context", "--trigger", "question", "--hash", priv["hash"], "--date", DAY)
        check(r.returncode != 0, "private block refused as trigger")

        # 3. run: note untouched, artifacts written, knowledge guarded
        before = (t.note.read_bytes(), t.note.stat().st_mtime_ns)
        t.set_reply(reply="You said the brief was unclear.",
                    proposals=[{"kind": "deadline", "title": "one-pager", "when": "friday", "project": "DORO"}],
                    suggestions=[{"text": "book a slot", "evidence": "one-pager due friday"}],
                    knowledge=[{"file": "projects/DORO.md", "content": "one-pager due friday"},
                               {"file": "../../../escape.md", "content": "nope"},
                               {"file": "profile.md", "content": "student of IT-U"}])
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0, f"run exits 0 ({r.stderr.strip()})")
        after = (t.note.read_bytes(), t.note.stat().st_mtime_ns)
        check(before == after, "daily note bytes and mtime untouched by a run")
        sent = (t.stub_dir / "last_payload.md").read_text()
        check("SECRET-PRIVATE-LINE" not in sent, "model received no private text")
        tr = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md"
        st = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json"
        check(tr.exists() and "You said the brief was unclear." in tr.read_text(), "transcript written with reply")
        check("add deadline: one-pager — friday · DORO" in tr.read_text(), "proposal rendered as a checkbox")
        s = json.loads(st.read_text())
        check(s["blocks"][at_block["hash"]]["state"] == "reply", "state marks fired block as reply")
        check(all(b["hash"] in s["blocks"] for b in blks if not b["private"] and "|agent]]" not in b["text"]),
              "every visible block marked seen")
        check(priv["hash"] not in s["blocks"], "private block not in state")
        check(s["blocks"][at_block["hash"]]["session"] == "ses_stub", "session id kept for dive-in")
        check((t.vault / "agents/longhand/knowledge/projects/DORO.md").read_text() == "one-pager due friday\n",
              "knowledge file written")
        check((t.vault / "agents/longhand/knowledge/profile.md").exists(), "profile written")
        check(not (t.vault / "escape.md").exists() and not (t.tmp / "escape.md").exists(), "path escape ignored")
        ledger = (t.state_home / "longhand" / "cost.tsv").read_text().splitlines()
        check(len(ledger) == 2 and "0.000200" in ledger[1], "cost ledger has one run")
        payloads = list((t.state_home / "longhand" / "payloads").glob("*.md"))
        check(len(payloads) == 1 and "SECRET-PRIVATE-LINE" not in payloads[0].read_text(), "payload logged, clean")

        # 4. open with nothing new → no model call
        (t.stub_dir / "last_payload.md").unlink()
        r = t.agent("run", "--trigger", "open", "--date", DAY)
        check(r.returncode == 0 and "nothing new" in r.stdout, "open pass skips when nothing changed")
        check(not (t.stub_dir / "last_payload.md").exists(), "no model call on a quiet open")

        # 5. private day → refused
        t.note.write_text(NOTE.replace("agent: true", "agent: false"))
        r = t.agent("context", "--trigger", "open", "--date", DAY)
        check(r.returncode != 0 and "agent: false" in r.stderr, "agent: false day refused")

        # 6. dive-in: chat continues the session, ack marks it read
        t.note.write_text(NOTE)
        before = (t.note.read_bytes(), t.note.stat().st_mtime_ns)
        t.set_reply(reply="Because you wrote it was unclear.")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "why do you think so?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()})")
        s = json.loads(st.read_text())
        rec = s["blocks"][at_block["hash"]]
        check([c["role"] for c in rec.get("chat", [])] == ["student", "agent"], "chat turns recorded")
        check(rec.get("read") is False, "new agent turn is unread")
        check("**you:** why do you think so?" in tr.read_text(), "chat turn in transcript")
        check(t.note.read_bytes() == before[0], "note still untouched after chat")
        r = t.agent("ack", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and json.loads(st.read_text())["blocks"][at_block["hash"]]["read"] is True, "ack marks read")

        # 7. accept: the proposal runs through pomo, is recorded, never twice
        r = t.agent("accept", "--hash", at_block["hash"], "--index", "0", "--date", DAY)
        check(r.returncode == 0, f"accept exits 0 ({r.stderr.strip()})")
        argv = json.loads((t.stub_dir / "pomo_args.json").read_text())
        check(argv == ["deadline", "add", "one-pager", "--project", "DORO", "friday"], f"pomo called with {argv}")
        s = json.loads(st.read_text())
        acc = s["blocks"][at_block["hash"]]["proposals"][0].get("accepted")
        check(bool(acc) and acc["id"] == 7, "proposal recorded as accepted with the new id")
        check("accepted" in tr.read_text() and "#7" in tr.read_text(), "acceptance in transcript")
        (t.stub_dir / "pomo_args.json").unlink()
        r = t.agent("accept", "--hash", at_block["hash"], "--index", "0", "--date", DAY)
        check(r.returncode == 0 and not (t.stub_dir / "pomo_args.json").exists(), "second accept is a no-op")
        r = t.agent("accept", "--hash", at_block["hash"], "--index", "5", "--date", DAY)
        check(r.returncode != 0, "missing proposal index refused")
        check(t.note.read_bytes() == before[0], "note untouched after accept")

        # 8. a list submission: several hashes, one record each, shared group
        t.note.write_text(NOTE + "\n- [ ] alpha\n- [ ] beta\n")
        b2 = blocks.split(t.note.read_text())
        items = [b["hash"] for b in b2 if b["text"] in ("- [ ] alpha", "- [ ] beta")]
        t.set_reply(reply="Two tasks, no dates.")
        r = t.agent("run", "--trigger", "checkbox", "--hash", ",".join(items), "--date", DAY)
        check(r.returncode == 0, f"grouped run exits 0 ({r.stderr.strip()})")
        sent = (t.stub_dir / "last_payload.md").read_text()
        check("> - [ ] alpha\n> - [ ] beta" in sent and "one submission" in sent, "both items quoted as one submission")
        s = json.loads(st.read_text())
        check(all(s["blocks"][h]["state"] == "reply" and s["blocks"][h]["group"] == items for h in items), "reply on every item, group recorded")
        r = t.agent("ack", "--hash", items[1], "--date", DAY)
        s = json.loads(st.read_text())
        check(all(s["blocks"][h]["read"] is True for h in items), "ack on one item reads the whole group")
        # One reply's proposals sit on every item: accepted on one, accepted on all.
        t.set_reply(reply="Dated.", proposals=[{"kind": "deadline", "title": "alpha", "when": "friday"},
                                               {"kind": "deadline", "title": "beta", "when": "friday"}])
        t.agent("run", "--trigger", "checkbox", "--hash", ",".join(items), "--date", DAY)
        r = t.agent("accept", "--hash", items[1], "--index", "0", "--date", DAY)
        s = json.loads(st.read_text())
        check(r.returncode == 0 and all(s["blocks"][h]["proposals"][0].get("accepted", {}).get("id") == 7 for h in items)
              and not any(s["blocks"][h]["proposals"][1].get("accepted") for h in items),
              "accepting on one item marks that proposal accepted on every item, and only that one")
        (t.stub_dir / "pomo_args.json").unlink()
        r = t.agent("accept", "--hash", items[0], "--index", "0", "--date", DAY)
        check(r.returncode == 0 and not (t.stub_dir / "pomo_args.json").exists(), "…so the other item does not add it again")
        t.note.write_text(NOTE)

        # 8b. a box answered, then ticked: the record keeps its words key, and
        # a chat on it (by the hash it was answered under) still runs and
        # tells the agent how the block reads now (2026-10-17).
        t.note.write_text(NOTE + "\n- [ ] should I buy a scooter?\n")
        q = _hash_of(t, "should I buy a scooter?")
        t.set_reply(reply="What would you use it for?")
        r = t.agent("run", "--trigger", "checkbox", "--hash", q, "--date", DAY)
        rec = json.loads(st.read_text())["blocks"][q]
        import task as tasklib
        check(r.returncode == 0 and rec.get("key") == blocks.fnv1a(tasklib.identity("- [x] should I buy a scooter? ✅ 2026-10-17")),
              f"an answered block keeps the key of its words ({rec.get('key')})")
        t.note.write_text(NOTE + "\n- [x] should I buy a scooter?\n")
        t.set_reply(reply="Then a bike will do.")
        r = t.agent("chat", "--hash", q, "--message", "commuting", "--date", DAY)
        sent = (t.stub_dir / "argv.json").read_text()
        rec = json.loads(st.read_text())["blocks"][q]
        check(r.returncode == 0 and [c["role"] for c in rec.get("chat", [])] == ["student", "agent"],
              f"a chat on the ticked box continues its conversation ({r.stderr.strip()})")
        check("The block now reads:\\n\\n- [x] should I buy a scooter?" in sent, "…telling the agent it is ticked now")
        t.note.write_text(NOTE)

        # 9. tasks: open checkboxes across days, today recent, old collapsed
        old = t.daily / f"{OLD_DAY}.md"
        old.write_text("- [ ] ancient task\n- [x] done task\n")
        r = t.agent("tasks")
        tasks = json.loads(r.stdout)
        check([x["text"] for x in tasks] == ["draft the one-pager by friday", "ancient task"], f"tasks listed newest first: {tasks}")
        check(tasks[0]["recent"] is True and tasks[1]["recent"] is False, "recent flag by age")
        check(tasks[0]["line"] == 7, "line index points at the checkbox line")

        # 10. what's next, dismissals remembered, suggestions deduped
        r = t.agent("next")
        nx = json.loads(r.stdout)
        check(any(x["kind"] == "suggestion" and x["text"] == "book a slot" for x in nx["raised"]), "suggestion listed in next")
        sug = next(x for x in nx["raised"] if x["kind"] == "suggestion")
        r = t.agent("dismiss", "--date", sug["date"], "--kind", "suggestion", "--index", str(sug["index"]))
        check(r.returncode == 0, f"dismiss exits 0 ({r.stderr.strip()})")
        dm = t.vault / "agents/longhand/knowledge/dismissed.md"
        check(dm.exists() and "book a slot" in dm.read_text(), "dismissal written to dismissed.md")
        nx = json.loads(t.agent("next").stdout)
        check(not any(x["text"] == "book a slot" for x in nx["raised"]), "dismissed suggestion gone from next")
        r = t.agent("context", "--trigger", "open", "--date", DAY)
        check("Intentions and outcomes" in r.stdout and "draft the one-pager by friday" in r.stdout, "outcomes in payload")

        # …and the intentions section honours the same allowlist as the rest
        # of the payload: it read whole notes until 2026-10-15.
        recent = dt.date.today() - dt.timedelta(days=2)
        (t.daily / f"{recent.strftime('%Y.%m.%d')}.md").write_text(
            "- [ ] a visible intention\n\n> [!private]\n> - [ ] SECRET-BOX do not send\n")
        quiet = dt.date.today() - dt.timedelta(days=3)
        (t.daily / f"{quiet.strftime('%Y.%m.%d')}.md").write_text(
            "---\nagent: false\n---\n\n- [ ] HIDDEN-DAY-BOX\n")
        r = t.agent("context", "--trigger", "open", "--date", DAY)
        check("a visible intention" in r.stdout, "a box from an earlier day is an intention")
        check("HIDDEN-DAY-BOX" not in r.stdout, "but not one from a day marked agent: false")
        nx = json.loads(t.agent("next").stdout)
        # A box inside a callout is a quoted line, so neither the payload nor
        # the dashboard reads it as a box at all. Pinned here because that is
        # what makes the private case safe today: teach the grammar to read
        # quoted boxes and this check fails, which is the point — the payload
        # filter above would then be the only thing standing in the way.
        check("SECRET-BOX" not in r.stdout
              and not any("SECRET-BOX" in x["text"] for x in nx["tasks"]),
              "a box inside a callout is a quote, not a task, on either side")
        check("dismissed (do not raise again" in r.stdout and "book a slot" in r.stdout, "dismissed list in payload")
        t.set_reply(reply="", suggestions=[{"text": "Book a slot!", "evidence": "x"}, {"text": "new idea", "evidence": "y"}])
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        s = json.loads(st.read_text())
        texts = [x["text"] for x in s["suggestions"]]
        check(texts.count("book a slot") == 1 and "Book a slot!" not in texts and "new idea" in texts, f"dismissed suggestion not re-added: {texts}")
        t.set_reply(reply="", knowledge=[{"file": "dismissed.md", "content": "wiped"}])
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check("book a slot" in dm.read_text(), "model cannot overwrite dismissed.md")

        # 11. the next payload carries what was said earlier today
        t.set_reply(reply="Brief was unclear, you said.")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        r = t.agent("context", "--trigger", "open", "--date", DAY)
        check("What you already said today" in r.stdout and "Brief was unclear, you said." in r.stdout, "earlier replies in payload")
        check("Already raised today" in r.stdout and "new idea" in r.stdout, "earlier suggestions listed")
        r = t.agent("context", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        head = r.stdout.split("# Today's note")[0]
        check("Brief was unclear, you said." not in head, "the fired block's own reply is not echoed back")

        # 12. stray editor: hash of an edited block no longer matches → refused, no run
        t.note.write_text(NOTE)
        r = t.agent("run", "--trigger", "question", "--hash", "deadbeef", "--date", DAY)
        check(r.returncode != 0, "unknown block hash refused")

        # 13. stats: read-only signals from the notes, the ledger and the page's usage log
        (t.state_home / "longhand").mkdir(parents=True, exist_ok=True)
        import time as _t
        now = int(_t.time())
        (t.state_home / "longhand" / "usage.tsv").write_text(
            f"{now}\topen\twindow\n{now}\tfind\t\n{now}\tday\t3\n{now}\tclose\t120\n")
        before = t.note.read_bytes()
        r = t.agent("stats", "--days", "2", "--json")
        st = json.loads(r.stdout)
        today_row = st["days"][-1]
        check(r.returncode == 0 and today_row["written"] == 1 and today_row["ticked"] == 0, f"stats counts checkboxes ({today_row['written']})")
        check(today_row["words"] > 0 and "SECRET" not in json.dumps(st), "stats counts words, carries no text")
        check(st["totals"]["page_opens"] == 1 and st["totals"]["page_minutes"] == 2, "stats reads the page's opens and minutes")
        check(st["totals"]["features"].get("find") == 1 and st["totals"]["features"].get("day:past") == 1, "stats reads features")
        check(st["totals"]["agent_runs"] >= 1, "stats reads the cost ledger")
        check(t.note.read_bytes() == before, "stats writes nothing")

        # 14. projects: the tags that exist, soonest session first
        pd = t.vault / "agents/longhand/knowledge/projects"
        pd.mkdir(parents=True, exist_ok=True)
        import datetime as _dt
        soon = _dt.date.today() + _dt.timedelta(days=2)
        later = _dt.date.today() + _dt.timedelta(days=9)
        past = _dt.date.today() - _dt.timedelta(days=3)
        (pd / "intsem.md").write_text(f"# Interdisciplinary Seminar\n\n- Tag: `#intsem` — notes under the H1\n"
                                      f"  - {later:%a %d %b}: 10:45–12:15 (Gold)\n")
        (pd / "dtm.md").write_text(f"# Design Theory & Methods\n\n- Tag: `#dtm`\n  - {past:%a %d %b}: 09:00–10:00 (Old)\n"
                                   f"  - {soon:%a %d %b}: 13:15–15:45, 16:00–17:00 (Seminar Room 1)\n")
        (pd / "thesis.md").write_text("# Thesis\n\nNo sessions, no Tag line.\n")
        pr = json.loads(t.agent("projects").stdout)
        check([p["tag"] for p in pr] == ["dtm", "intsem", "DORO", "thesis"], f"projects soonest first, file name as fallback tag ({[p['tag'] for p in pr]})")
        check(pr[0]["next"]["at"].endswith("13:15") and pr[0]["next"]["room"] == "Seminar Room 1", f"next session read ({pr[0]['next']})")
        check(pr[1]["name"] == "Interdisciplinary Seminar" and pr[3]["next"] is None, "name from the H1; no sessions, no next")
        # Fixed dates from here on, so the clock cannot move the answers.
        (pd / "intsem.md").write_text("# Interdisciplinary Seminar\n\n- Tag: `#intsem`\n"
                                      "  - Mon 12 Oct: 10:45–12:15, 13:15–15:45 (Gold)\n"
                                      "  - Tue 15 Dec: 10:45–12:15 (Infineon Seminar room 1)\n")
        def nxt(now):
            pr = json.loads(t.agent("projects", "--now", now).stdout)
            return next(p["next"] for p in pr if p["tag"] == "intsem")
        check(nxt("2026-10-12T09:00")["at"] == "2026-10-12T10:45", "before class: today's first slot")
        n = nxt("2026-10-12T11:00")
        check(n["at"] == "2026-10-12T10:45" and n["now"] is True, "during the first slot: it, and under way")
        check(nxt("2026-10-12T12:30")["at"] == "2026-10-12T13:15", "between slots: the afternoon one")
        check(nxt("2026-10-12T18:00")["at"] == "2026-12-15T10:45", "after class: the next session, not today's")
        check(nxt("2027-01-11T09:00") is None, "in January, October is last October: nothing next")
        check(nxt("2026-12-01T09:00")["at"] == "2026-12-15T10:45", "December reads as this December")

        # 15. sections: a project's notes across days, found by its tag
        # A tagged H1 claims its H2s and H3s; only another H1 ends it.
        (t.daily / f"{DAY}.md").write_text(
            "[[agents/longhand/daily/x|agent]]\n\n"
            "# Interdisciplinary Seminar #intsem\n"
            "Gabriel on digital sovereignty\n"
            "## Learning goals\n"
            "- [ ] send the email\n"
            "- [x] read the abstract\n"
            "### Deeper still #intsem\n"
            "the same section, not a second one\n"
            "# Research Proficiency #respro\n"
            "## Supervisors\n"
            "- Frank Neffke\n")
        (t.daily / f"{OLD_DAY}.md").write_text(
            "# Interdisciplinary Seminar #intsem\n"
            "the first week\n"
            "## Untagged heading\n"
            "still intsem's\n")
        se = json.loads(t.agent("sections", "--tag", "intsem").stdout)
        check(len(se) == 2, f"one section per day, the nested tagged heading absorbed ({len(se)})")
        check([r["date"] for r in se] == [DAY, OLD_DAY], f"newest day first ({[r['date'] for r in se]})")
        check(se[0]["title"] == "Interdisciplinary Seminar" and se[0]["level"] == 1, f"title without the tag ({se[0]['title']!r})")
        check(se[0]["line"] == 2, f"the heading's own line, to open the note on ({se[0]['line']})")
        check(se[0]["open"] == 1 and se[0]["done"] == 1, f"its checkboxes counted ({se[0]['open']}/{se[0]['done']})")
        check([x["text"] for x in se[0]["sub"]] == ["Learning goals", "Deeper still #intsem"],
              f"the headings under it, as its index ({[x['text'] for x in se[0]['sub']]})")
        check("Frank Neffke" not in json.dumps(se), "another H1 ends the section")
        check(se[0]["preview"] == ["Gabriel on digital sovereignty", "- [ ] send the email"],
              f"preview skips the link line and the headings ({se[0]['preview']})")
        check(se[1]["sub"][0]["text"] == "Untagged heading", "an untagged H2 does not end an H1")
        check([r["date"] for r in json.loads(t.agent("sections", "--tag", "respro").stdout)] == [DAY],
              "the other tag gets its own section")
        check(json.loads(t.agent("sections", "--tag", "nothing").stdout) == [], "a tag nobody wrote: nothing")
        check(len(json.loads(t.agent("sections", "--tag", "intsem", "--days", "7").stdout)) == 1,
              "--days leaves the old day out")

        # 16. a sent block carries its project's earlier notes — and only
        # those. What is kept out of today's note is kept out of these.
        PRIV = (t.daily / f"{OLD_DAY}.md")
        PRIV.write_text(
            "# Interdisciplinary Seminar #intsem\n"
            "the first week, reviews explained\n"
            "> [!private]\n> SECRET-OLD-DAY not for the agent\n"
            "# Research Proficiency #respro\n"
            "OTHER-COURSE-WORDS\n")
        shut = t.daily / f"{(dt.date.today() - dt.timedelta(days=30)):%Y.%m.%d}.md"
        shut.write_text("---\nagent: false\n---\n# Interdisciplinary Seminar #intsem\nSHUT-DAY-WORDS\n")
        t.note.write_text("[[agents/longhand/daily/x|agent]]\n\n"
                          "# Interdisciplinary Seminar #intsem\n"
                          "## Today\n"
                          "@ what did I say about reviews?\n")
        ctx = t.agent("context", "--trigger", "mention",
                      "--hash", _hash_of(t, "@ what did I say about reviews?")).stdout
        check("reviews explained" in ctx, "a sent block carries its project's earlier notes")
        check("SECRET-OLD-DAY" not in ctx, "a private callout in an earlier note stays private")
        check("OTHER-COURSE-WORDS" not in ctx, "another course's section of that day is not sent")
        check("SHUT-DAY-WORDS" not in ctx, "a day marked agent: false is left out whole")
        check("#intsem" in ctx and "earlier daily notes" in ctx, "the payload names what it is carrying")
        openctx = t.agent("context", "--trigger", "open").stdout
        check("reviews explained" not in openctx, "the automatic open pass is not widened")
        # 17. how opencode is called. The flags moved under it once and every
        # run failed for a day while the page said nothing — the invocation
        # is part of the contract now, not an implementation detail.
        print("-- the call to opencode")
        t.note.write_text(NOTE)
        (t.stub_dir / "argv.json").unlink(missing_ok=True)
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        called = json.loads((t.stub_dir / "argv.json").read_text())
        argv = called["argv"]
        check(argv[0] == "run", "opencode is asked to run")
        check("--standalone" in argv, "a server of its own, nothing resident")
        check(argv[argv.index("--format") + 1] == "json", "machine-readable events")
        check(argv[argv.index("--agent") + 1] == "longhand", "Longhand's agent, with its denied tools")
        check(not ({"--pure", "--dir", "--variant"} & set(argv)), "no flag opencode no longer knows")
        check(pathlib.Path(called["cwd"]).resolve() == (t.state_home / "longhand" / "agent-cwd").resolve(),
              "run from the agent's own empty directory, never a project")

        # A run that says nothing at all did not run. opencode prints its
        # usage and exits 0 when it does not know a flag.
        print("-- a silent failure is a failure")
        env_was = t.env.get("STUB_DEAF")
        t.env["STUB_DEAF"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        if env_was is None:
            t.env.pop("STUB_DEAF")
        check(r.returncode != 0, "the runner exits non-zero")
        last = json.loads((t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json").read_text())["runs"][-1]
        check("Unrecognized flag" in last["error"], "what opencode said is kept")

        # The ledger when the events carry no price: asked of the session.
        print("-- the price, asked of the session")
        t.env["STUB_FREE"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_FREE")
        last = json.loads((t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json").read_text())["runs"][-1]
        check(abs(last["cost"] - 0.5) < 1e-9, "cost read back from the session")
        check(last["tokens"]["total"] == 11, "and its tokens")
    finally:
        t.cleanup()

    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
