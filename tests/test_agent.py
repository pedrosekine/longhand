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
AGENT = ROOT / "agent" / "student-agent"

STUB = """#!/usr/bin/env python3
import json, sys
payload = sys.stdin.read()
import os
os.makedirs(os.environ["STUB_DIR"], exist_ok=True)
open(os.path.join(os.environ["STUB_DIR"], "last_payload.md"), "w").write(payload)
reply = json.loads(open(os.path.join(os.environ["STUB_DIR"], "reply.json")).read())
text = "```json\\n" + json.dumps(reply) + "\\n```"
ev = lambda t, part: print(json.dumps({"type": t, "sessionID": "ses_stub", "part": part}))
ev("step_start", {"type": "step-start"})
ev("text", {"type": "text", "text": text, "time": {"start": 1, "end": 2}})
ev("step_finish", {"type": "step-finish", "cost": 0.0002, "tokens": {"input": 100, "output": 20, "reasoning": 5, "total": 125}})
"""

# The test's "today" is the real today: the runner judges recency (the
# tasks panel, what's next) against the clock, so fixed dates go stale.
DAY = dt.date.today().strftime("%Y.%m.%d")
OLD_DAY = (dt.date.today() - dt.timedelta(days=60)).strftime("%Y.%m.%d")

NOTE = """---
agent: true
---
[[agents/student/daily/DAY|agent]]

Read the DORO brief again.

- [ ] draft the one-pager by friday

> [!private]
> SECRET-PRIVATE-LINE do not send

@ what did I say about DORO?
""".replace("DAY", DAY)


class T:
    def __init__(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="student-agent-test-"))
        self.vault = self.tmp / "vault"
        self.daily = self.vault / "inbox" / "Daily"
        self.daily.mkdir(parents=True)
        (self.vault / "human" / "_Secrets").mkdir(parents=True)
        (self.vault / "human" / "_Secrets" / "keys.md").write_text("SECRET-VAULT-FILE\n")
        self.note = self.daily / f"{DAY}.md"
        self.note.write_text(NOTE)
        self.cfg = self.tmp / "config.json"
        self.cfg.write_text(json.dumps({"vault": str(self.vault), "daily": {"dir": "inbox/Daily", "format": "YYYY.MM.DD"},
                                        "agentDir": "agents/student", "opencode": str(self.tmp / "bin" / "opencode")}))
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
        self.env = dict(os.environ, OMARCHY_STUDENT_CONFIG=str(self.cfg), XDG_STATE_HOME=str(self.state_home),
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
        check(f"[[agents/student/daily/{DAY}|agent]]" not in r.stdout, "template link line absent from payload")
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
        tr = t.vault / "agents" / "student" / "daily" / f"{DAY}.md"
        st = t.vault / "agents" / "student" / "daily" / f"{DAY}.json"
        check(tr.exists() and "You said the brief was unclear." in tr.read_text(), "transcript written with reply")
        check("add deadline: one-pager — friday · DORO" in tr.read_text(), "proposal rendered as a checkbox")
        s = json.loads(st.read_text())
        check(s["blocks"][at_block["hash"]]["state"] == "reply", "state marks fired block as reply")
        check(all(b["hash"] in s["blocks"] for b in blks if not b["private"] and "|agent]]" not in b["text"]),
              "every visible block marked seen")
        check(priv["hash"] not in s["blocks"], "private block not in state")
        check(s["blocks"][at_block["hash"]]["session"] == "ses_stub", "session id kept for dive-in")
        check((t.vault / "agents/student/knowledge/projects/DORO.md").read_text() == "one-pager due friday\n",
              "knowledge file written")
        check((t.vault / "agents/student/knowledge/profile.md").exists(), "profile written")
        check(not (t.vault / "escape.md").exists() and not (t.tmp / "escape.md").exists(), "path escape ignored")
        ledger = (t.state_home / "omarchy-student" / "cost.tsv").read_text().splitlines()
        check(len(ledger) == 2 and "0.000200" in ledger[1], "cost ledger has one run")
        payloads = list((t.state_home / "omarchy-student" / "payloads").glob("*.md"))
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
        dm = t.vault / "agents/student/knowledge/dismissed.md"
        check(dm.exists() and "book a slot" in dm.read_text(), "dismissal written to dismissed.md")
        nx = json.loads(t.agent("next").stdout)
        check(not any(x["text"] == "book a slot" for x in nx["raised"]), "dismissed suggestion gone from next")
        r = t.agent("context", "--trigger", "open", "--date", DAY)
        check("Intentions and outcomes" in r.stdout and "draft the one-pager by friday" in r.stdout, "outcomes in payload")
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
    finally:
        t.cleanup()

    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
