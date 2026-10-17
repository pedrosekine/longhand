"""The improvement loop (docs/agent.md): a reply's rating, the prompt
version on every run, eval cases from real runs, the check before a prompt
is installed, and the weekly review — against a stub model and judge, a
throwaway vault and state.

Run: python3 tests/test_loop.py
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
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# The model answers by which agent is asked: the margin from margin.txt, the
# judge with one verdict per criterion from judge.json.
STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
agent = args[args.index("--agent") + 1] if "--agent" in args else ""
payload = sys.stdin.read()
open(os.path.join(d, agent + ".payload"), "w").write(payload)
if agent == "longhand-judge":
    reply = open(os.path.join(d, "judge.json")).read()
elif agent == "longhand":
    reply = json.dumps({"reply": open(os.path.join(d, "margin.txt")).read(), "proposals": [], "suggestions": [], "knowledge": []})
else:
    reply = json.dumps({"proposals": [], "questions": [], "knowledge": []})
print(json.dumps({"type": "text", "sessionID": "ses_loop", "part": {"type": "text", "text": "```json\\n" + reply + "\\n```"}}))
"""


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="loop-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    agent_dir = vault / "agents/longhand"
    (agent_dir / "daily").mkdir(parents=True)
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/margin", "planModel": "stub/plan"}))
    state = tmp / "state"
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

    today = dt.date.today().isoformat()
    agent("install")
    installed = cfgdir / "opencode" / "agent"
    check(all((installed / n).exists() for n in ("longhand.md", "longhand-plan.md", "longhand-judge.md")),
          "install writes the margin's, the planner's and the judge's definitions")

    # A margin run, as recorded: its prompt version and model on the block.
    (vault / "Daily" / f"{today}.md").write_text("Should I buy an e-scooter?\n")
    (stub / "margin.txt").write_text("By when do you want to decide?")
    payload = state / "longhand" / "payloads" / "scooter.md"
    payload.parent.mkdir(parents=True, exist_ok=True)
    payload.write_text("# Trigger\nkind: checkbox\n\n> - [ ] Should I buy an e-scooter?\n\n# Today's note\n\nShould I buy an e-scooter?\n")
    st = {"date": today, "blocks": {"abc123": {"state": "reply", "reply": "By when do you want to decide?", "trigger": "checkbox",
                                               "head": "- [ ] Should I buy an e-scooter?", "prompt": "p1", "model": "stub/margin",
                                               "payload": str(payload), "read": True}},
          "runs": [{"at": today + "T10:00:00", "trigger": "checkbox", "prompt": "p1", "model": "stub/margin"}],
          "suggestions": [], "observations": []}
    (agent_dir / "daily" / f"{today}.json").write_text(json.dumps(st))

    # The rating.
    out = json.loads(agent("rate", "down", "--hash", "abc123").stdout)
    rec = json.loads((agent_dir / "daily" / f"{today}.json").read_text())["blocks"]["abc123"]
    check(out["rating"] == "down" and rec["rating"]["value"] == "down", "a reply rated not helpful is kept on its block")
    fb = (state / "longhand" / "feedback.tsv").read_text().splitlines()
    check(len(fb) == 2 and "\tdown\tp1\tstub/margin\t" in fb[1], "…and in feedback.tsv, with the prompt and model that made it")
    agent("rate", "none", "--hash", "abc123")
    check("rating" not in json.loads((agent_dir / "daily" / f"{today}.json").read_text())["blocks"]["abc123"], "…and can be taken back")
    agent("rate", "down", "--hash", "abc123")

    # The review: what missed, and how to make it a case.
    rv = agent("review").stdout
    check("1 not helpful" in rv and "By when do you want to decide?" in rv, "the review lists the reply rated not helpful")
    check(f"longhand-agent eval add {payload} --job margin" in rv, "…with the command that makes it an eval case")
    check("never checked" in rv, "…and says the prompt in use has never been checked")
    w = json.loads(agent("review", "--if-due").stdout)
    check(w["written"].endswith(".md") and pathlib.Path(w["written"]).exists(), "--if-due writes the week's review into the vault")
    check(json.loads(agent("review", "--if-due").stdout)["written"] == "", "…once a week, not at every opening")

    # A case from that run.
    agent("eval", "add", str(payload), "--job", "margin", "--id", "scooter", "--answer", "By when do you want to decide?")
    case_file = agent_dir / "evals" / "cases" / "scooter.json"
    case = json.loads(case_file.read_text())
    check(case["payload"] == payload.read_text() and case["answer_then"].startswith("By when"),
          "eval add keeps the payload and the answer that missed, in the vault")
    case["rules"]["must_not_match"] = [r"\bby when\b"]
    case["criteria"] = ["Engages with the substance of the question."]
    case_file.write_text(json.dumps(case))

    # The same reply fails it…
    (stub / "judge.json").write_text(json.dumps({"results": [{"pass": False, "why": "asks only when"}]}))
    r = agent("eval", "run", ok=False)
    check(r.returncode == 1 and "FAIL scooter" in r.stdout and "by when" in r.stdout.lower(), "the old answer fails its case: the rule and the judge")
    judge_payload = (stub / "longhand-judge.payload").read_text()
    check("Engages with the substance" in judge_payload and "Should I buy an e-scooter?" in judge_payload,
          "the judge is given the criteria, the answer and the payload it was made from")
    # …a better one passes.
    (stub / "margin.txt").write_text("It trades against the tram pass — how far is campus from the flat?")
    (stub / "judge.json").write_text(json.dumps({"results": [{"pass": True, "why": "weighs it"}]}))
    r = agent("eval", "run")
    check("PASS scooter" in r.stdout and "1/1 cases pass" in r.stdout, f"a better answer passes ({r.stdout.splitlines()[-2]})")
    results = sorted((agent_dir / "evals" / "results").glob("*.json"))
    last = json.loads(results[-1].read_text())
    check(last["jobs"][0]["model"] == "stub/margin" and len(last["jobs"][0]["prompt"]) == 10,
          "each run is kept with the prompt's version and the model")
    st_ = json.loads(agent("eval", "status", "--json").stdout)
    margin = next(x for x in st_["rows"] if x["job"] == "margin" and x["prompts"] == "repo")
    check(margin["checked"] == "passed", "eval status: the repo's margin prompt has passed on the configured model")

    # The check before a prompt change.
    (installed / "longhand.md").write_text((installed / "longhand.md").read_text() + "\n<!-- an older install -->\n")
    r = agent("install")
    check(r.returncode == 0, "a changed prompt that passed its cases installs")
    (installed / "longhand.md").write_text((installed / "longhand.md").read_text() + "\n<!-- older again -->\n")
    for f in (agent_dir / "evals" / "results").glob("*.json"):
        f.unlink()
    r = agent("install", ok=False)
    check(r.returncode != 0 and "has not passed its eval cases" in r.stderr, "one that has not passed is refused")
    r = agent("install", "--force")
    check(r.returncode == 0, "…unless told to (--force)")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
