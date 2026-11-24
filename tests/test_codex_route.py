"""The Codex route (docs/agent.md, "Reaching a model"), tested offline
against a stub `codex`.

Run: python3 tests/test_codex_route.py

- a model named `codex/<model>` runs `codex exec`, not opencode, in
  Longhand's own Codex folder (`CODEX_HOME`), never ~/.codex
- not signed in there: refused before any call, saying how to sign in
- the agent's rule, flag by flag: every tool feature off, no web search, no
  skills, environment or permission notes, a read-only sandbox, no user
  config or rules, the agent's own instructions in place of Codex's, the
  agent's own empty directory
- the words and the payload travel together on stdin, so "- [ ] …" is never
  a flag and a resumed session gets its payload too; a chat resumes
- a ChatGPT run costs 0 in the ledger; its tokens are counted
- a run whose session file shows a tool called, or anything attached beyond
  the agent's instructions, Codex's running notes and the student's words
  (AGENTS.md), or that left no session file to check, is dropped, its words
  unused
- an error Codex reports is the run's error, and its session is not kept
- a session another route began (opencode's `ses_…`) is not resumed
- an effort Codex has no place for (`ultra`, sub-agents) is refused before
  any call
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import test_agent as base  # noqa: E402

ROOT = base.ROOT
DAY = base.DAY
SID = "019a0000-0000-7000-8000-00000000c0de"

STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
argv = sys.argv[1:]
said = sys.stdin.read()
home = os.environ.get("CODEX_HOME", "")
open(os.path.join(d, "codex_argv.json"), "w").write(json.dumps({"argv": argv, "cwd": os.getcwd(), "stdin": said,
                                                                 "home": home}))
resume = len(argv) > 1 and argv[1] == "resume"
# Each new session its own id, as Codex gives: the first is SID.
n = int(open(os.path.join(d, "codex_n")).read()) if os.path.exists(os.path.join(d, "codex_n")) else 0
if not resume:
    open(os.path.join(d, "codex_n"), "w").write(str(n + 1))
sid = argv[-2] if resume else "%s"[:-4] + "%%04x" %% (0xc0de + n)
cs = [argv[i + 1] for i, a in enumerate(argv) if a == "-c"]
ifile = json.loads(next(c.split("=", 1)[1] for c in cs if c.startswith("model_instructions_file=")))
instr = open(ifile).read()
day = os.path.join(home, "sessions", "2026", "11", "18")
path = os.path.join(day, "rollout-2026-11-18T10-00-00-" + sid + ".jsonl")
if resume and not os.path.exists(path):
    print("Error: thread/resume failed: no rollout found for thread id " + sid, file=sys.stderr)
    sys.exit(1)
print(json.dumps({"type": "thread.started", "thread_id": sid}))
print(json.dumps({"type": "turn.started"}))
if os.environ.get("STUB_ERROR"):
    print(json.dumps({"type": "error", "message": "You've hit your usage limit."}))
    print(json.dumps({"type": "turn.failed", "error": {"message": "You've hit your usage limit."}}))
    sys.exit(1)
def item(kind, **p):
    return json.dumps({"type": kind, "payload": p}) + "\\n"
def msg(role, text):
    return item("response_item", type="message", role=role, content=[{"type": "input_text", "text": text}])
reply = json.loads(open(os.path.join(d, "reply.json")).read())
text = "```json\\n" + json.dumps(reply) + "\\n```"
if not os.environ.get("STUB_NO_ROLLOUT"):
    os.makedirs(day, exist_ok=True)
    lines = ""
    if not resume:
        lines += item("session_meta", id=sid, base_instructions={"text": instr, "provenance": {"type": "custom"}})
        lines += msg("developer", instr)
        lines += msg("developer", "<collaboration_mode># Collaboration Mode: Default</collaboration_mode>")
        lines += msg("developer", "<multi_agent_role>You are `/root`.</multi_agent_role>")
    if os.environ.get("STUB_AGENTS_MD"):
        lines += msg("user", "# AGENTS.md instructions\\n\\n<INSTRUCTIONS>\\nread the vault\\n</INSTRUCTIONS>")
    lines += msg("user", said.strip())
    if os.environ.get("STUB_TOOL_CALL"):
        lines += item("response_item", type="function_call", name="list_agents", arguments="{}")
    lines += item("response_item", type="message", role="assistant", content=[{"type": "output_text", "text": text}])
    with open(path, "a") as f:
        f.write(lines)
print(json.dumps({"type": "item.completed", "item": {"id": "item_0", "type": "error",
                                                     "message": "Code Mode is unavailable"}}))
print(json.dumps({"type": "item.completed", "item": {"id": "item_r", "type": "reasoning",
                                                     "text": "**Reading the brief**\\n**Checking the DORO deadline**"}}))
print(json.dumps({"type": "item.completed", "item": {"id": "item_1", "type": "agent_message", "text": text}}))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1000, "cached_input_tokens": 800,
                                                      "output_tokens": 40, "reasoning_output_tokens": 12}}))
""" % SID


def opt(argv, name):
    return argv[argv.index(name) + 1] if name in argv else None


def configs(argv):
    return {a.split("=", 1)[0]: a.split("=", 1)[1] for a in (argv[i + 1] for i, x in enumerate(argv) if x == "-c")}


def disabled(argv):
    return {argv[i + 1] for i, x in enumerate(argv) if x == "--disable"}


def main() -> int:
    t = base.T()
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)
            print("FAIL", msg)
        else:
            print("ok  ", msg)

    try:
        stub = t.tmp / "bin" / "codex"
        stub.write_text(STUB)
        stub.chmod(0o755)
        cfg = json.loads(t.cfg.read_text())
        cfg.update(model="codex/gpt-6.2-sol", variant="high", codex=str(stub))
        t.cfg.write_text(json.dumps(cfg))
        sys.path.insert(0, str(ROOT / "agent"))
        import blocks
        at_block = next(b for b in blocks.split(base.NOTE) if b["text"].startswith("@ "))
        state = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json"
        transcript = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md"
        home = t.state_home / "longhand" / "codex"

        print("-- not signed in: refused before any call")
        t.set_reply(reply="You said the brief was unclear.")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode != 0 and "codex login" in r.stderr and str(home) in r.stderr
              and not (t.stub_dir / "codex_argv.json").exists(), "it says how to sign in, and calls nothing")
        check(home.is_dir(), "…and makes the folder, which Codex will not sign in to otherwise")
        (home / "auth.json").write_text("{}")   # what a sign-in leaves; Longhand never reads it

        print("-- a first pass goes through Codex")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0, f"run exits 0 ({r.stderr.strip()[-300:]})")
        check(not (t.stub_dir / "argv.json").exists(), "opencode was not called")
        called = json.loads((t.stub_dir / "codex_argv.json").read_text())
        argv, c = called["argv"], configs(called["argv"])
        check(argv[0] == "exec" and argv[1] != "resume" and "--json" in argv, "one headless pass, its events as JSON")
        check(opt(argv, "-m") == "gpt-6.2-sol", "the model, without the route's prefix")
        check(c.get("model_reasoning_effort") == '"high"', "the variant is the reasoning effort")
        shown = [x[len("status: "):] for x in r.stderr.splitlines() if x.startswith("status: ")]
        check(c.get("model_reasoning_summary") == '"detailed"' and shown[:1] == ["thinking"]
              and "checking the DORO deadline" in shown,
              f"while it thinks, the last heading of its thinking is the status, an acronym kept ({shown})")
        check(pathlib.Path(called["home"]).resolve() == home.resolve(), "Longhand's own Codex folder, never ~/.codex")
        check({"shell_tool", "unified_exec", "code_mode", "code_mode_host", "apps", "plugins", "hooks", "memories",
               "browser_use", "computer_use", "multi_agent", "multi_agent_v2"} <= disabled(argv),
              "every tool feature off, hooks and memories too")
        check(c.get("sandbox_mode") == '"read-only"' and c.get("web_search") == '"disabled"', "read-only, no web search")
        check(c.get("project_doc_max_bytes") == "0" and c.get("skills.include_instructions") == "false"
              and c.get("include_environment_context") == "false"
              and c.get("include_permissions_instructions") == "false",
              "no AGENTS.md, skills, environment or permission notes")
        check("--ignore-user-config" in argv and "--ignore-rules" in argv, "no user config, no rules")
        ifile = pathlib.Path(json.loads(c.get("model_instructions_file", '""')))
        defn = (ROOT / "agent" / "opencode" / "longhand.md").read_text()
        instr = ifile.read_text() if ifile.is_file() else ""
        check(instr and instr.strip() in defn and not instr.startswith("---") and "permission:" not in instr,
              "the agent's own instructions, without opencode's frontmatter, in place of Codex's")
        check(argv[-1] == "-", "the words on stdin, never an argument")
        check(pathlib.Path(called["cwd"]).resolve() == (t.state_home / "longhand" / "agent-cwd").resolve(),
              "run from the agent's own empty directory")
        check(called["stdin"].startswith("Context follows on stdin.") and "<stdin>" in called["stdin"]
              and "Read the DORO brief again." in called["stdin"] and "SECRET-PRIVATE-LINE" not in called["stdin"],
              "the words, then the payload, the private line not in it")
        s = json.loads(state.read_text())
        check(s["blocks"][at_block["hash"]]["session"] == SID, "the session kept for a dive-in")
        check("You said the brief was unclear." in transcript.read_text(), "the reply lands in the transcript")
        run = s["runs"][-1]
        check(run["cost"] == 0 and run["tokens"]["input"] == 1000 and run["tokens"]["output"] == 40
              and run["tokens"]["reasoning"] == 12, "a ChatGPT run costs nothing per token; its tokens are counted")
        row = (t.state_home / "longhand" / "cost.tsv").read_text().splitlines()[-1].split("\t")
        check(row[10] == "codex/gpt-6.2-sol#high" and not row[11], "the ledger names the route's model")

        print("-- a chat: the one agent's own session, then resumed")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "what do you mean?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "codex_argv.json").read_text())
        day_defn = (ROOT / "agent" / "opencode" / "longhand-day.md").read_text()
        ifile = pathlib.Path(json.loads(configs(called["argv"])["model_instructions_file"]))
        check(called["argv"][1] != "resume" and ifile.read_text().strip() in day_defn,
              "the first message of a chat is the one agent's, not the margin pass's session")
        chat_sid = json.loads(state.read_text())["blocks"][at_block["hash"]]["session"]
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "- [ ] why do you think so?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "codex_argv.json").read_text())
        check(chat_sid not in ("", SID) and called["argv"][1] == "resume" and called["argv"][-2] == chat_sid
              and called["argv"][-1] == "-",
              "the next resumes its session")
        check("- [ ] why do you think so?" in called["stdin"]
              and not any("why do you think" in a for a in called["argv"]), "the student's words, never a flag")

        print("-- a session another route began is not resumed")
        s = json.loads(state.read_text())
        s["blocks"][at_block["hash"]]["session"] = "ses_from_opencode"
        state.write_text(json.dumps(s))
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "and tomorrow instead?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "codex_argv.json").read_text())
        check(called["argv"][1] != "resume", "no resume with opencode's session")
        check("# This chat so far" in called["stdin"] and "Read the DORO brief again." in called["stdin"],
              "the whole context again, with what was said so far")

        print("-- a tool called: the run is dropped")
        t.set_reply(reply="WORDS-FROM-A-RUN-WITH-TOOLS")
        t.env["STUB_TOOL_CALL"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_TOOL_CALL")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "call tools" in run["error"] and "list_agents" in run["error"],
              "the run fails and names the tool")
        check("WORDS-FROM-A-RUN-WITH-TOOLS" not in transcript.read_text(), "its words never reach the transcript")

        print("-- AGENTS.md attached: the run is dropped")
        t.set_reply(reply="WORDS-FROM-A-RUN-WITH-AGENTS-MD")
        t.env["STUB_AGENTS_MD"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_AGENTS_MD")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "attached more than the payload" in run["error"] and "AGENTS.md" in run["error"],
              "the run fails and names what was attached")
        check("WORDS-FROM-A-RUN-WITH-AGENTS-MD" not in transcript.read_text(), "its words never reach the transcript")

        print("-- no session file to check: the run is dropped")
        for f in (home / "sessions").rglob("*.jsonl"):
            f.unlink()
        t.env["STUB_NO_ROLLOUT"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_NO_ROLLOUT")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "no session file" in run["error"], "unchecked is not trusted")

        print("-- an error Codex reports")
        t.set_reply(reply="fine")
        t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        kept = json.loads(state.read_text())["blocks"][at_block["hash"]]["session"]
        t.env["STUB_ERROR"] = "1"
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "one more", "--date", DAY)
        t.env.pop("STUB_ERROR")
        s = json.loads(state.read_text())
        check(r.returncode != 0 and "usage limit" in s["runs"][-1]["error"], "the run fails with Codex's words")
        check(s["blocks"][at_block["hash"]]["session"] == kept, "the chat keeps the session it had")

        print("-- the effort written on the model, as opencode writes a variant")
        cfg.update(model="codex/gpt-6.2-sol#xhigh", variant="")
        t.cfg.write_text(json.dumps(cfg))
        t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        argv = json.loads((t.stub_dir / "codex_argv.json").read_text())["argv"]
        check(opt(argv, "-m") == "gpt-6.2-sol" and configs(argv).get("model_reasoning_effort") == '"xhigh"',
              "model and effort apart")
        cfg.update(model="codex/gpt-6.2-sol#ultra")
        t.cfg.write_text(json.dumps(cfg))
        (t.stub_dir / "codex_argv.json").unlink()
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode != 0 and "no effort 'ultra'" in r.stderr and not (t.stub_dir / "codex_argv.json").exists(),
              "ultra (sub-agents) is refused before any call")

        print("-- any other model still goes through opencode")
        cfg["model"] = "openai/gpt-6.2-sol"
        t.cfg.write_text(json.dumps(cfg))
        t.set_reply(reply="from opencode")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and (t.stub_dir / "argv.json").exists()
              and not (t.stub_dir / "codex_argv.json").exists(), "opencode, not Codex")

        if sys.platform == "win32":
            print("-- on Windows, a .cmd shim on PATH is resolved by bare name")
            cmd_dir = t.tmp / "cmd bin"
            cmd_dir.mkdir(parents=True, exist_ok=True)
            py_stub = cmd_dir / "codex_stub.py"
            py_stub.write_text(STUB, encoding="utf-8")
            cmd_shim = cmd_dir / "codex.cmd"
            cmd_shim.write_text(f'@echo off\r\n"{sys.executable}" "{py_stub}" %*\r\n', encoding="utf-8")
            cfg.update(model="codex/gpt-6.2-sol#high", variant="", codex="codex")
            t.cfg.write_text(json.dumps(cfg))
            t.set_reply(reply="from cmd shim")
            old_path = t.env.get("PATH", "")
            t.env["PATH"] = str(cmd_dir) + ";" + old_path
            try:
                (t.stub_dir / "codex_argv.json").unlink(missing_ok=True)
                r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
            finally:
                t.env["PATH"] = old_path
            check(r.returncode == 0 and (t.stub_dir / "codex_argv.json").exists(),
                  f"bare 'codex' resolves codex.cmd in a spaced dir ({r.stderr.strip()[-300:]})")
    finally:
        t.cleanup()

    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
