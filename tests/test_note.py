"""A note's own conversation, the runner's side (docs/files.md, "Talking
about a note", 2026-10-27): one conversation per note, kept by its path in
the agent's folder; the note whole on the first message and again only when
it changed; a block pointed at; asking is the consent for a note marked
private or a day before the horizon, but never for a private callout, a
never-shared file, or a secret; the note itself is never written — against
a stub model and a throwaway vault.

Run: python3 tests/test_note.py
"""
import hashlib
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
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
n = len([f for f in os.listdir(d) if f.startswith("call-")])
stdin = sys.stdin.read()
json.dump({"argv": args, "stdin": stdin}, open(os.path.join(d, f"call-{n}.json"), "w"))
reply = {"reply": f"answer {n}", "knowledge": [], "read": [],
         "proposals": [{"kind": "deadline", "title": "made up", "date": "2030-01-01", "why": "no"}]}
print(json.dumps({"type": "text", "sessionID": "ses_note", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="note-test-"))
    vault = tmp / "vault"
    (vault / "human" / "Daily").mkdir(parents=True)
    course = vault / "human" / "Studies" / "FHOÖ"
    course.mkdir(parents=True)
    note = course / "Session 1.md"
    text = ("---\ndate: 2023-03-01\nagent: false\n---\n# Session 1\n\nReflexive thematic analysis: themes are built.\n\n"
            "> [!private]\n> SECRET-CALLOUT not for the agent\n\n- [ ] read Braun and Clarke\n")
    note.write_text(text)
    old_day = vault / "human" / "Daily" / "2022-05-04.md"
    old_day.write_text("Journal: a long walk by the river.\n")
    (vault / "human" / "Personal").mkdir(parents=True)
    (vault / "human" / "Personal" / "Kontoauszug.md").write_text("money\n")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m", "horizon": "2026-09-17"}))
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

    rel = "human/Studies/FHOÖ/Session 1.md"
    talk = vault / "agents/longhand/notes" / (hashlib.md5(rel.encode()).hexdigest()[:16] + ".json")

    agent("note", "--file", rel, "--message", "what did I say about themes?")
    first = calls()[-1]
    pay = first["stdin"]
    check("Reflexive thematic analysis: themes are built." in pay and f"# The note: `{rel}`" in pay,
          "the first message carries the note whole, by its path")
    check("not today's note" in pay and "Propose nothing" in pay, "…told what this conversation is")
    check("SECRET-CALLOUT" not in pay and "agent: false" not in pay, "…never its private callout, nor its frontmatter")
    check(pay.rstrip().endswith("what did I say about themes?"), "…and what the student says")
    t = json.loads(talk.read_text())
    check(t["path"] == rel and t["session"] == "ses_note" and [x["role"] for x in t["turns"]] == ["student", "agent"]
          and t["turns"][1]["text"] == "answer 0", "kept in the agent's folder by the note's md5, with its session")
    check("proposals" not in t["turns"][1], "a proposal made anyway is not taken")
    check(note.read_text() == text, "the note is never written")

    box = next(b for b in blocks.split(note.read_text()) if "Braun" in b["text"])
    agent("note", "--file", rel, "--message", "and this?", "--block", box["hash"])
    second = calls()[-1]
    msg = second["argv"][-1]
    check("--session" in second["argv"] and second["stdin"] == "" and "themes are built" not in msg,
          "a later message continues the session; the note unchanged is not sent again")
    check("# The part the student points at" in msg and "> - [ ] read Braun and Clarke" in msg,
          "…the block pointed at goes with it")
    note.write_text(text.replace("themes are built", "themes are built, not found"))
    agent("note", "--file", rel, "--message", "and now?")
    check("# The note as it reads now" in calls()[-1]["argv"][-1] and "not found" in calls()[-1]["argv"][-1],
          "changed since, it is sent again")

    agent("note", "--file", "human/Daily/2022-05-04.md", "--message", "how was that day?")
    check("a long walk by the river" in calls()[-1]["stdin"], "a day before the horizon: asking about it is the consent")
    r = agent("note", "--file", "human/Personal/Kontoauszug.md", "--message", "x", ok=False)
    check(r.returncode != 0 and "never shared" in r.stderr, "a document of money is never shared, even asked about")
    r = agent("note", "--file", "../outside.md", "--message", "x", ok=False)
    check(r.returncode != 0, "nothing outside the vault")
    payloads = list((tmp / "state").rglob("*-note.md"))
    check(len(payloads) == 4, f"every message logged before inference ({len(payloads)})")
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
