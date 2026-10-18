"""The agent's notebook, visible and corrected (docs/agent.md, slice 3):
forget and correct a line, the record in corrections.md, a correction that
stays made when the model writes the old line back, and what the payloads
carry — against a stub model, a throwaway vault and state.

Run: python3 tests/test_notebook.py
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
import notebook as nb  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# The model writes back whatever knowledge.json holds, the old lines included.
STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
agent = args[args.index("--agent") + 1] if "--agent" in args else ""
if args[:1] != ["run"]:
    sys.exit(0)
open(os.path.join(d, (agent or "longhand") + ".payload"), "w").write(sys.stdin.read())
knowledge = json.load(open(os.path.join(d, "knowledge.json")))
if agent == "longhand-plan":
    reply = {"proposals": [], "questions": [], "knowledge": knowledge}
else:
    reply = {"reply": "", "proposals": [], "suggestions": [], "knowledge": knowledge}
print(json.dumps({"type": "text", "sessionID": "ses_nb", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""

PROFILE = """# Profile

- Master's student. Wants replies in English.
- Grading scale not yet confirmed.
- Lives in Vienna.
  - Commutes to Linz by train.
- Takes Interdisciplinary Seminar.
"""


def units() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="nb-unit-"))
    k = tmp / "knowledge"
    (k / "projects").mkdir(parents=True)
    (k / "profile.md").write_text(PROFILE)
    (k / "projects" / "intsem.md").write_text("# Interdisciplinary Seminar\n\n- Open: which role(s) the student takes.\n")
    (k / "answers.md").write_text("# The student's answers\n\nWhat the student told the agent when it asked. True; never to be asked again.\n\n"
                                  "- 2026-10-17 · essay: which essay? → the IntSem paper\n")
    (k / "dismissed.md").write_text("# Dismissed suggestions\n\n- buy a scooter\n")
    write = lambda f, t: f.write_text(t)  # noqa: E731
    day = dt.date(2026, 10, 18)

    d = nb.read(k)
    check([f["file"] for f in d["files"]] == ["profile.md", "projects/intsem.md"],
          "the notebook lists the agent's own files, profile first — never answers, dismissals or corrections as its notes")
    check(d["files"][0]["title"] == "Profile" and len(d["files"][0]["lines"]) == 5 and d["files"][0]["lines"][3]["depth"] == 1,
          "…each line of a file, nested lines one deeper")
    check(len(d["answers"]) == 1 and "the IntSem paper" in d["answers"][0]["text"], "the student's answers are listed apart")

    nb.forget(k, "profile.md", "lives in vienna", write, day)
    t = (k / "profile.md").read_text()
    check("Vienna" not in t and "Commutes" not in t and "Grading scale" in t, "forget takes the line out, with what is nested under it")
    rec = nb.corrections(k)
    check(len(rec) == 1 and rec[0]["how"] == "forget" and rec[0]["text"] == "Lives in Vienna.", "…and records it in corrections.md")
    nb.forget(k, "projects/intsem.md", "Open: which role(s) the student takes.", write, day)
    check(len(nb.corrections(k)) == 2, "a second forgetting, in another file")

    nb.correct(k, "profile.md", "Grading scale not yet confirmed.", "Grades run 1 (best) to 5; 4 is a pass.", write, day)
    t = (k / "profile.md").read_text()
    check("- Grades run 1 (best) to 5; 4 is a pass.\n" in t and "not yet confirmed" not in t, "correct puts the student's words in the line's place")
    check(nb.corrections(k)[-1]["to"].startswith("Grades run"), "…and records the correction")
    try:
        nb.correct(k, "profile.md", "Grading scale not yet confirmed.", "x", write, day)
        check(False, "a line no longer there cannot be corrected")
    except ValueError as e:
        check("no longer" in str(e), "a line no longer there cannot be corrected")
    for bad in ("corrections.md", "dismissed.md", "../outside.md"):
        try:
            nb.forget(k, bad, "anything", write, day)
            check(False, f"{bad} is refused")
        except ValueError:
            check(True, f"{bad} is not the notebook's to forget from")

    nb.forget(k, "answers.md", "2026-10-17 · essay: which essay? → the IntSem paper", write, day)
    check("IntSem paper" not in (k / "answers.md").read_text() and len(nb.corrections(k)) == 3,
          "an answer of the student's own is simply removed, not recorded (the agent may ask again)")

    # The model writes the old lines back.
    back = PROFILE.replace("Master's student.", "Master's student (IT:U).")
    out = nb.enforce(back, nb.corrections(k))
    check("Vienna" not in out and "Commutes" not in out, "a forgotten line written back by the model is left out again")
    check("Grades run 1 (best) to 5; 4 is a pass." in out and "not yet confirmed" not in out, "…a corrected one is corrected again")
    check("Master's student (IT:U)." in out, "…and the model's other changes stand")
    check(nb.enforce("- lives   in VIENNA\n", nb.corrections(k)) == "", "the match ignores case and spacing")

    sec = "\n".join(nb.payload_section(k))
    check("overrule" in sec and 'forget "Lives in Vienna."' in sec and 'but "Grades run' in sec, "the payload section names each correction")

    gone = nb.take_back(k, 0, write)
    check(gone["text"] == "Lives in Vienna." and len(nb.corrections(k)) == 2, "a correction can be taken back")


def end_to_end() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="nb-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    agent_dir = vault / "agents/longhand"
    k = agent_dir / "knowledge"
    k.mkdir(parents=True)
    (k / "profile.md").write_text(PROFILE)
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/margin"}))
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    (stub / "knowledge.json").write_text(json.dumps([{"file": "profile.md", "content": PROFILE},
                                                      {"file": "corrections.md", "content": "# mine now\n"}]))
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    shown = json.loads(agent("notebook").stdout)
    check(shown["files"][0]["file"] == "profile.md" and shown["corrections"] == [], "notebook shows what the agent knows")
    agent("notebook", "forget", "--file", "profile.md", "--text", "Lives in Vienna.")
    agent("notebook", "correct", "--file", "profile.md", "--text", "Grading scale not yet confirmed.",
          "--to", "4 is a pass.")
    r = agent("notebook", "forget", "--file", "profile.md", "--text", "Lives in Vienna.", ok=False)
    check(r.returncode == 2 and "no longer" in r.stderr, "forgetting a line twice says it is gone")
    check(len(json.loads(agent("notebook").stdout)["corrections"]) == 2, "the CLI records both")

    today = dt.date.today().isoformat()
    (vault / "Daily" / f"{today}.md").write_text("A quiet day.\n")
    agent("run", "--trigger", "open")
    payload = (stub / "longhand.payload").read_text()
    check("# The student's corrections to your notes" in payload and 'forget "Lives in Vienna."' in payload,
          "the margin's payload carries the corrections")
    check("## corrections.md" not in payload, "…as corrections, not as one of the agent's own files")
    t = (k / "profile.md").read_text()
    check("Vienna" not in t and "4 is a pass." in t and "not yet confirmed" not in t,
          "the model writing the old lines back does not undo the corrections")
    check((k / "corrections.md").read_text().startswith("# The student's corrections"),
          "the model cannot write corrections.md")

    (vault / "Daily" / f"{today}.md").write_text("A quiet day.\n\n- [ ] read the paper ⏫\n")
    agent("plan", "--force")
    plan_payload = (stub / "longhand-plan.payload").read_text()
    check("# The student's corrections to your notes" in plan_payload, "the planner's payload carries them too")


def main() -> int:
    units()
    end_to_end()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
