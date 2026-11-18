"""The Claude Code route (docs/agent.md, "Reaching a model"), tested offline
against a stub `claude`.

Run: python3 tests/test_claude_route.py

- a model named `claude-code/<model>` runs through Claude Code, not opencode
- the agent's rule, flag by flag: no tools, no MCP servers, no settings files
  (so no CLAUDE.md, hooks or memory), no slash commands, the agent's own
  instructions as the whole system prompt, the agent's own empty directory
- the payload travels on stdin; a dive-in resumes the same session, and the
  student's words come after `--`, so "- [ ] …" is never a flag
- a subscription run costs 0 in the ledger; an API-key run, what it reports
- no Claude Code memory (both switches set), and a run whose saved transcript
  shows anything attached beyond the allowed kinds — or that left no
  transcript to check — is dropped, its words unused
- a run where Claude Code offered tools anyway is dropped, its words unused
- an error Claude Code reports is the run's error
- a session another route began (opencode's `ses_…`) is not resumed: the
  chat starts afresh, its turns so far carried in the payload
- a run Claude Code refuses before it begins says why, keeps the session the
  chat had, and leaves an error turn in the chat, not an empty answer
- a run stopped from the page (SIGTERM) ends at once, Claude Code with it;
  it is logged as stopped and leaves no turn in the chat
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import test_agent as base  # noqa: E402

ROOT = base.ROOT
DAY = base.DAY

STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
payload = sys.stdin.read()
open(os.path.join(d, "claude_argv.json"), "w").write(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(),
                                                                  "stdin": payload,
                                                                  "env": {k: v for k, v in os.environ.items()
                                                                          if k.startswith("CLAUDE_CODE_")}}))
# The transcript Claude Code saves, with what it attached to the run.
# A slow run, to be stopped: its pid, then a long wait.
if os.environ.get("STUB_SLOW"):
    open(os.path.join(d, "slow.pid"), "w").write(str(os.getpid()))
    import time
    time.sleep(30)
# Refused before any conversation, as `--resume <not its own>` is.
if os.environ.get("STUB_REFUSE"):
    print(json.dumps({"type": "result", "subtype": "error_during_execution", "is_error": True, "num_turns": 0,
                      "session_id": "never-saved", "errors": ["Error: --resume requires a valid session ID. "
                                                              "Provided value is not a UUID"]}))
    sys.exit(1)
if not os.environ.get("STUB_NO_TRANSCRIPT"):
    kinds = ["environment", "model", "session_context", "date", "credential_org", "prompt_snapshot"]
    if os.environ.get("STUB_MEMORY"):
        kinds.insert(2, "instructions")
    t = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "projects", "-agent-cwd")
    os.makedirs(t, exist_ok=True)
    with open(os.path.join(t, "cc-sess.jsonl"), "a") as f:
        for k in kinds:
            f.write(json.dumps({"type": "attachment", "attachment": {"type": k}}) + "\\n")
tools = json.loads(os.environ.get("STUB_TOOLS") or "[]")
key = os.environ.get("STUB_KEY", "none")
print(json.dumps({"type": "system", "subtype": "init", "session_id": "cc-sess", "tools": tools,
                  "mcp_servers": [], "model": "claude-opus-5-5", "apiKeySource": key}))
if os.environ.get("STUB_ERROR"):
    print(json.dumps({"type": "result", "subtype": "error_during_execution", "is_error": True,
                      "result": "Claude usage limit reached", "session_id": "cc-sess"}))
    sys.exit(1)
reply = json.loads(open(os.path.join(d, "reply.json")).read())
text = "```json\\n" + json.dumps(reply) + "\\n```"
print(json.dumps({"type": "assistant", "session_id": "cc-sess",
                  "message": {"content": [{"type": "text", "text": text}]}}))
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": text,
                  "session_id": "cc-sess", "total_cost_usd": 0.0123,
                  "usage": {"input_tokens": 2, "cache_creation_input_tokens": 900, "cache_read_input_tokens": 100,
                            "output_tokens": 40, "output_tokens_details": {"thinking_tokens": 12}}}))
"""


def flag(argv, name):
    return argv[argv.index(name) + 1] if name in argv else None


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
        # Claude Code's own folder, a throwaway one: never ~/.claude.
        t.env["CLAUDE_CONFIG_DIR"] = str(t.tmp / "claude-config")
        stub = t.tmp / "bin" / "claude"
        stub.write_text(STUB)
        stub.chmod(0o755)
        cfg = json.loads(t.cfg.read_text())
        cfg.update(model="claude-code/claude-opus-5-5", variant="high", claude=str(stub))
        t.cfg.write_text(json.dumps(cfg))
        sys.path.insert(0, str(ROOT / "agent"))
        import blocks
        at_block = next(b for b in blocks.split(base.NOTE) if b["text"].startswith("@ "))
        state = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json"

        print("-- a first pass goes through Claude Code")
        t.set_reply(reply="You said the brief was unclear.")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0, f"run exits 0 ({r.stderr.strip()[-300:]})")
        check(not (t.stub_dir / "argv.json").exists(), "opencode was not called")
        called = json.loads((t.stub_dir / "claude_argv.json").read_text())
        argv = called["argv"]
        check(argv[0] == "-p", "headless: one pass, then exit")
        check(flag(argv, "--model") == "claude-opus-5-5", "the model, without the route's prefix")
        check(flag(argv, "--effort") == "high", "the variant is the effort")
        check(flag(argv, "--output-format") == "stream-json" and "--verbose" in argv,
              "the events, with what was offered the model")
        check(flag(argv, "--tools") == "", "no tools")
        check("--strict-mcp-config" in argv and "--mcp-config" not in argv, "no MCP servers")
        check(flag(argv, "--setting-sources") == "", "no settings files: no CLAUDE.md, hooks or memory")
        check("--disable-slash-commands" in argv, "no skills or slash commands")
        check("--bare" not in argv, "not --bare, which refuses the subscription sign-in")
        system = flag(argv, "--system-prompt") or ""
        defn = (ROOT / "agent" / "opencode" / "longhand.md").read_text()
        check(system and system.strip() in defn and not system.startswith("---") and "permission:" not in system,
              "the agent's own instructions, without opencode's frontmatter, as the whole system prompt")
        check("--resume" not in argv, "a first pass starts a new session")
        check(argv[-2] == "--", "the message after --")
        check(called["env"].get("CLAUDE_CODE_DISABLE_AUTO_MEMORY") == "1"
              and called["env"].get("CLAUDE_CODE_DISABLE_ORG_MEMORY") == "1",
              "no Claude Code memory, the home folder's or the organisation's")
        check(pathlib.Path(called["cwd"]).resolve() == (t.state_home / "longhand" / "agent-cwd").resolve(),
              "run from the agent's own empty directory")
        check("Read the DORO brief again." in called["stdin"] and "SECRET-PRIVATE-LINE" not in called["stdin"],
              "the payload on stdin, the private line not in it")
        s = json.loads(state.read_text())
        check(s["blocks"][at_block["hash"]]["session"] == "cc-sess", "the session kept for a dive-in")
        tr = (t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md").read_text()
        check("You said the brief was unclear." in tr, "the reply lands in the transcript")
        run = s["runs"][-1]
        check(run["cost"] == 0 and run["tokens"]["input"] == 1002 and run["tokens"]["output"] == 40,
              "a subscription run costs nothing per token; its tokens are counted")
        row = (t.state_home / "longhand" / "cost.tsv").read_text().splitlines()[-1].split("\t")
        check(row[10] == "claude-code/claude-opus-5-5#high" and not row[11], "the ledger names the route's model")

        # Since slice 3 of "One conversation" (2026-11-18) one agent answers
        # every chat: the pass's session was the margin agent's, so the first
        # message of the chat starts the one agent's own; the next resumes it.
        print("-- a chat: the one agent's own session, then resumed")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "what do you mean?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        argv = json.loads((t.stub_dir / "claude_argv.json").read_text())["argv"]
        day_defn = (ROOT / "agent" / "opencode" / "longhand-day.md").read_text()
        check("--resume" not in argv and (flag(argv, "--system-prompt") or "x").strip() in day_defn,
              "the first message of a chat is the one agent's, not the margin pass's session")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "- [ ] why do you think so?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        argv = json.loads((t.stub_dir / "claude_argv.json").read_text())["argv"]
        check(flag(argv, "--resume") == "cc-sess", "the next resumes its session")
        check(argv[-2] == "--" and "- [ ] why do you think so?" in argv[-1], "the student's words, never a flag")

        print("-- a session another route began is not resumed")
        rec_hash = at_block["hash"]
        s = json.loads(state.read_text())
        s["blocks"][rec_hash]["session"] = "ses_from_opencode"
        state.write_text(json.dumps(s))
        r = t.agent("chat", "--hash", rec_hash, "--message", "and tomorrow instead?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "claude_argv.json").read_text())
        check("--resume" not in called["argv"], "no --resume with opencode's session")
        check("# This chat so far" in called["stdin"] and "why do you think so?" in called["stdin"]
              and "Read the DORO brief again." in called["stdin"],
              "the whole context again, with what was said so far")
        check(json.loads(state.read_text())["blocks"][rec_hash]["session"] == "cc-sess", "Claude Code's session kept from now on")

        print("-- refused before it began: said, and the session kept")
        t.env["STUB_REFUSE"] = "1"
        r = t.agent("chat", "--hash", rec_hash, "--message", "one more", "--date", DAY)
        t.env.pop("STUB_REFUSE")
        s = json.loads(state.read_text())
        check(r.returncode != 0 and "Claude Code refused the run" in s["runs"][-1]["error"]
              and "not a UUID" in s["runs"][-1]["error"], "the error is Claude Code's own words")
        check(s["blocks"][rec_hash]["session"] == "cc-sess", "the chat's session is not replaced by one never saved")
        last = s["blocks"][rec_hash]["chat"][-1]
        check(last["role"] == "agent" and "refused" in last.get("error", "") and last["text"] == "",
              "the chat holds the failure, not an empty answer")
        print("-- stopped from the page")
        import os, signal, subprocess, time
        before = len(json.loads(state.read_text())["blocks"][rec_hash]["chat"])
        t.env["STUB_SLOW"] = "1"
        (t.stub_dir / "slow.pid").unlink(missing_ok=True)
        run = subprocess.Popen([sys.executable, str(base.AGENT), "chat", "--hash", rec_hash, "--message", "never mind",
                                "--date", DAY], env=t.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        for _ in range(100):
            if (t.stub_dir / "slow.pid").exists():
                break
            time.sleep(0.05)
        t0 = time.time()
        run.send_signal(signal.SIGTERM)
        out, err = run.communicate(timeout=15)
        took = time.time() - t0
        t.env.pop("STUB_SLOW")
        pid = int((t.stub_dir / "slow.pid").read_text())
        gone = False
        for _ in range(40):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                gone = True
                break
            time.sleep(0.05)
        s = json.loads(state.read_text())
        check(took < 5 and run.returncode != 0 and "stopped" in err, f"it ends at once, and says so ({took:.1f}s, {err.strip()[-80:]})")
        check(gone, "…Claude Code with it, nothing left running")
        check(len(s["blocks"][rec_hash]["chat"]) == before and s["blocks"][rec_hash]["session"] == "cc-sess",
              "…no turn in the chat, the session as it was")
        check(s["runs"][-1]["error"] == "stopped", "…and the run logged as stopped")
        print("-- an API key is billed, and says so")
        t.env["STUB_KEY"] = "ANTHROPIC_API_KEY"
        t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_KEY")
        run = json.loads(state.read_text())["runs"][-1]
        check(abs(run["cost"] - 0.0123) < 1e-9, "the reported cost in the ledger")

        print("-- tools offered anyway: the run is dropped")
        t.set_reply(reply="WORDS-FROM-A-RUN-WITH-TOOLS")
        t.env["STUB_TOOLS"] = json.dumps(["Bash", "Read"])
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_TOOLS")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "offered the agent tools" in run["error"] and "Bash" in run["error"],
              "the run fails and says which tools")
        check("WORDS-FROM-A-RUN-WITH-TOOLS" not in (t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md").read_text(),
              "its words never reach the transcript")

        print("-- memory attached anyway: the run is dropped")
        t.set_reply(reply="WORDS-FROM-A-RUN-WITH-MEMORY")
        t.env["STUB_MEMORY"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_MEMORY")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "attached more than the payload" in run["error"] and "instructions" in run["error"],
              "the run fails and names what was attached")
        check("WORDS-FROM-A-RUN-WITH-MEMORY" not in (t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md").read_text(),
              "its words never reach the transcript")
        # the transcript keeps every run of the session: start the next ones clean
        for f in (t.tmp / "claude-config" / "projects").glob("*/cc-sess.jsonl"):
            f.unlink()

        print("-- no transcript to check: the run is dropped")
        t.env["STUB_NO_TRANSCRIPT"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_NO_TRANSCRIPT")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "no transcript" in run["error"], "unchecked is not trusted")

        print("-- an error Claude Code reports")
        t.env["STUB_ERROR"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_ERROR")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "usage limit" in run["error"], "the run fails with Claude Code's words")

        print("-- the effort written on the model, as opencode writes a variant")
        cfg.update(model="claude-code/claude-opus-5-5#xhigh", variant="")
        t.cfg.write_text(json.dumps(cfg))
        t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        argv = json.loads((t.stub_dir / "claude_argv.json").read_text())["argv"]
        check(flag(argv, "--model") == "claude-opus-5-5" and flag(argv, "--effort") == "xhigh", "model and effort apart")
        cfg.update(model="claude-code/claude-opus-5-5#loud")
        t.cfg.write_text(json.dumps(cfg))
        (t.stub_dir / "claude_argv.json").unlink()
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode != 0 and "no effort 'loud'" in r.stderr and not (t.stub_dir / "claude_argv.json").exists(),
              "an effort Claude Code does not know is refused before any call")

        print("-- any other model still goes through opencode")
        cfg["model"] = "openai/gpt-6.1-sol"
        t.cfg.write_text(json.dumps(cfg))
        (t.stub_dir / "claude_argv.json").unlink(missing_ok=True)
        t.set_reply(reply="from opencode")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and (t.stub_dir / "argv.json").exists()
              and not (t.stub_dir / "claude_argv.json").exists(), "opencode, not Claude Code")
    finally:
        t.cleanup()

    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
