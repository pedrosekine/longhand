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
- a run where Claude Code offered tools anyway is dropped, its words unused
- an error Claude Code reports is the run's error
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
                                                                  "stdin": payload}))
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

        print("-- a dive-in resumes the session")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "- [ ] why do you think so?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        argv = json.loads((t.stub_dir / "claude_argv.json").read_text())["argv"]
        check(flag(argv, "--resume") == "cc-sess", "the same session")
        check(argv[-2] == "--" and "- [ ] why do you think so?" in argv[-1], "the student's words, never a flag")

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
