"""The Antigravity route (docs/agent.md, "Reaching a model"), tested offline
against a stub `agy`.

Run: python3 tests/test_antigravity_route.py

- a model named `antigravity/<model>` runs `agy -p` headless, not opencode,
  with a home of Longhand's own (`HOME`), never the student's ~/.gemini
- the agent's own instructions as a custom agent's whole definition, with
  `tools: []`; no slash commands; the agent's own empty directory
- the words and the payload travel together on stdin as one message, so
  "- [ ] …" is never a flag and a payload larger than an argument fits; a
  chat resumes its conversation
- a subscription run costs 0 in the ledger; its tokens are counted
- a run that called a tool (Antigravity always offers `manage_task` and
  `schedule`), or that ran another agent, is dropped, its words unused
- rules, skills or MCP servers in Longhand's Antigravity home: refused
  before any call
- an error Antigravity reports is the run's error, and its session is not
  kept
- a session another route began (opencode's `ses_…`) is not resumed
- the effort rides on the model's slug; one Antigravity has no slug for is
  refused before any call
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import test_agent as base  # noqa: E402

ROOT = base.ROOT
DAY = base.DAY
CID = "6a6e0000-0000-4000-8000-00000000a001"

STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
argv = sys.argv[1:]
stdin = sys.stdin.read()
home = os.environ.get("HOME", "")
open(os.path.join(d, "agy_argv.json"), "w").write(json.dumps({"argv": argv, "cwd": os.getcwd(), "stdin": stdin,
                                                               "home": home, "userprofile": os.environ.get("USERPROFILE", "")}))
def opt(name):
    return argv[argv.index(name) + 1] if name in argv else None
convs = os.path.join(home, ".gemini", "antigravity-cli", "conversations")
os.makedirs(convs, exist_ok=True)
n = len(os.listdir(convs))
cid = opt("--conversation") or "%s"[:-4] + "%%04x" %% (0xa001 + n)
def emit(ev, **p):
    print(json.dumps(dict({"event": ev}, **p)))
def result(status, response="", error=""):
    r = {"conversation_id": cid, "status": status, "response": response, "num_turns": 1,
         "usage": {"input_tokens": 1000, "output_tokens": 40, "thinking_tokens": 12, "cache_read_tokens": 0,
                   "total_tokens": 1040}}
    if error:
        r["error"] = error
    emit("result", result=r)
if opt("--conversation") and not os.path.exists(os.path.join(convs, cid + ".db")):
    result("ERROR", error="conversation not found: " + cid)
    sys.exit(1)
agent = opt("--agent")
defn = os.path.join(home, ".gemini", "config", "agents", agent + ".md")
if not os.path.exists(defn):
    result("ERROR", error="agent not found: " + agent)
    sys.exit(1)
if os.environ.get("STUB_ERROR"):
    result("ERROR", error="RESOURCE_EXHAUSTED: You have reached your quota.")
    sys.exit(1)
open(os.path.join(convs, cid + ".db"), "w").write("")
emit("init", conversation_id=cid, init={"model": opt("--model"), "cwd": os.getcwd(),
     "agent": os.environ.get("STUB_OTHER_AGENT") or agent, "tools": ["manage_task", "run_command", "schedule"],
     "permission_mode": "request-review"})
emit("step_update", step_update={"conversation_id": cid, "step_index": 0, "state": "DONE", "step_type": "user_input"})
if opt("--conversation"):
    # As agy 1.5.16 does on every resume: its own notice, no tool on it.
    emit("step_update", step_update={"conversation_id": cid, "step_index": 1, "state": "DONE",
         "step_type": "system_message", "duration_seconds": "0.0004"})
if os.environ.get("STUB_NOTICE_TOOL"):
    emit("step_update", step_update={"conversation_id": cid, "step_index": 1, "state": "DONE",
         "step_type": "system_message", "tool_name": "schedule"})
if os.environ.get("STUB_TOOL_CALL"):
    emit("step_update", step_update={"conversation_id": cid, "step_index": 1, "state": "DONE", "step_type": "tool",
         "tool_name": "manage_task", "tool_info": {"name": "manage_task", "parameters": {"Action": "list"}}})
reply = json.loads(open(os.path.join(d, "reply.json")).read())
text = "```json\\n" + json.dumps(reply) + "\\n```"
emit("step_update", step_update={"conversation_id": cid, "step_index": 2, "state": "DONE",
     "step_type": "agent_response", "text_delta": text})
result("SUCCESS", text + "\\n")
""" % CID


def opt(argv, name):
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
        stub = t.tmp / "bin" / "agy"
        stub.write_text(STUB)
        stub.chmod(0o755)
        cfg = json.loads(t.cfg.read_text())
        cfg.update(model="antigravity/gemini-4-neon", variant="high", antigravity=str(stub))
        t.cfg.write_text(json.dumps(cfg))
        sys.path.insert(0, str(ROOT / "agent"))
        import blocks
        at_block = next(b for b in blocks.split(base.NOTE) if b["text"].startswith("@ "))
        state = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json"
        transcript = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md"
        home = t.state_home / "longhand" / "antigravity"

        print("-- a first pass goes through Antigravity")
        t.set_reply(reply="You said the brief was unclear.")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0, f"run exits 0 ({r.stderr.strip()[-300:]})")
        check(not (t.stub_dir / "argv.json").exists(), "opencode was not called")
        called = json.loads((t.stub_dir / "agy_argv.json").read_text())
        argv = called["argv"]
        check(opt(argv, "-p") == "" and opt(argv, "--input-format") == "stream-json"
              and opt(argv, "--output-format") == "stream-json", "one headless pass, its words and events as JSON")
        check(opt(argv, "--model") == "gemini-4-neon-high", "the model, without the route's prefix, its effort as slug")
        check(pathlib.Path(called["home"]).resolve() == home.resolve(), "Longhand's own Antigravity home")
        if sys.platform == "win32":
            check(pathlib.Path(called["userprofile"]).resolve() == home.resolve(),
                  "on Windows, USERPROFILE is isolated to Longhand's Antigravity home too")
        check("--disable-slash-commands" in argv and "--conversation" not in argv, "no slash commands, a new chat")
        defn = (home / ".gemini" / "config" / "agents" / f"{opt(argv, '--agent')}.md").read_text()
        own = (ROOT / "agent" / "opencode" / "longhand.md").read_text()
        body = defn.split("\n---\n", 1)[1] if "\n---\n" in defn else ""
        check(opt(argv, "--agent") == "longhand" and "\ntools: []\n" in defn and body.strip()
              and body.strip() in own and "permission:" not in defn,
              "the agent's own instructions, without opencode's frontmatter, and no tools")
        check(pathlib.Path(called["cwd"]).resolve() == (t.state_home / "longhand" / "agent-cwd").resolve(),
              "run from the agent's own empty directory")
        sent = json.loads(called["stdin"])
        said = sent["message"]["content"]
        check(sent["event"] == "user" and said.startswith("Context follows on stdin.") and "<stdin>" in said
              and "Read the DORO brief again." in said and "SECRET-PRIVATE-LINE" not in said,
              "the words, then the payload, as one message on stdin; the private line not in it")
        s = json.loads(state.read_text())
        check(s["blocks"][at_block["hash"]]["session"] == CID, "the conversation kept for a dive-in")
        check("You said the brief was unclear." in transcript.read_text(), "the reply lands in the transcript")
        run = s["runs"][-1]
        check(run["cost"] == 0 and run["tokens"]["input"] == 1000 and run["tokens"]["output"] == 40
              and run["tokens"]["reasoning"] == 12, "a subscription run costs nothing per token; its tokens are counted")
        row = (t.state_home / "longhand" / "cost.tsv").read_text().splitlines()[-1].split("\t")
        check(row[10] == "antigravity/gemini-4-neon#high", "the ledger names the route's model")

        print("-- a chat: the one agent's own conversation, then resumed")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "what do you mean?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "agy_argv.json").read_text())
        day_body = (home / ".gemini" / "config" / "agents" / "longhand-day.md").read_text().split("\n---\n", 1)[1]
        check(opt(called["argv"], "--agent") == "longhand-day" and "--conversation" not in called["argv"]
              and day_body.strip() in (ROOT / "agent" / "opencode" / "longhand-day.md").read_text(),
              "the first message of a chat is the one agent's, not the margin pass's conversation")
        chat_cid = json.loads(state.read_text())["blocks"][at_block["hash"]]["session"]
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "- [ ] why do you think so?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "agy_argv.json").read_text())
        check(chat_cid not in ("", CID) and opt(called["argv"], "--conversation") == chat_cid,
              "the next resumes its conversation")
        check(json.loads(state.read_text())["blocks"][at_block["hash"]]["chat"][-1].get("role") == "agent"
              and not json.loads(state.read_text())["runs"][-1].get("error"),
              "…past Antigravity's own notice on a resume (a system message, no tool), answered")
        check("- [ ] why do you think so?" in json.loads(called["stdin"])["message"]["content"]
              and not any("why do you think" in a for a in called["argv"]), "the student's words, never a flag")

        print("-- a session another route began is not resumed")
        s = json.loads(state.read_text())
        s["blocks"][at_block["hash"]]["session"] = "ses_from_opencode"
        state.write_text(json.dumps(s))
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "and tomorrow instead?", "--date", DAY)
        check(r.returncode == 0, f"chat exits 0 ({r.stderr.strip()[-300:]})")
        called = json.loads((t.stub_dir / "agy_argv.json").read_text())
        said = json.loads(called["stdin"])["message"]["content"]
        check("--conversation" not in called["argv"], "no resume with opencode's session")
        check("# This chat so far" in said and "Read the DORO brief again." in said,
              "the whole context again, with what was said so far")

        print("-- a tool called: the run is dropped")
        t.set_reply(reply="WORDS-FROM-A-RUN-WITH-TOOLS")
        t.env["STUB_TOOL_CALL"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_TOOL_CALL")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "call tools" in run["error"] and "manage_task" in run["error"],
              "the run fails and names the tool")
        check("WORDS-FROM-A-RUN-WITH-TOOLS" not in transcript.read_text(), "its words never reach the transcript")

        print("-- a system message that names a tool: still a tool step, dropped")
        t.set_reply(reply="WORDS-FROM-A-NOTICE-WITH-A-TOOL")
        t.env["STUB_NOTICE_TOOL"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_NOTICE_TOOL")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "call tools" in run["error"] and "schedule" in run["error"],
              "the run fails and names the tool")
        check("WORDS-FROM-A-NOTICE-WITH-A-TOOL" not in transcript.read_text(), "its words never reach the transcript")

        print("-- another agent ran: the run is dropped")
        t.set_reply(reply="WORDS-FROM-ANOTHER-AGENT")
        t.env["STUB_OTHER_AGENT"] = "default"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        t.env.pop("STUB_OTHER_AGENT")
        run = json.loads(state.read_text())["runs"][-1]
        check(r.returncode != 0 and "not Longhand's" in run["error"], "the run fails and says whose agent ran")
        check("WORDS-FROM-ANOTHER-AGENT" not in transcript.read_text(), "its words never reach the transcript")

        print("-- a skill in Longhand's Antigravity home: refused before any call")
        skill = home / ".gemini" / "skills" / "omarchy"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("read the vault")
        (t.stub_dir / "agy_argv.json").unlink()
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode != 0 and ".gemini/skills" in r.stderr and not (t.stub_dir / "agy_argv.json").exists(),
              "it names what is there, and calls nothing")
        (skill / "SKILL.md").unlink()
        skill.rmdir()
        (home / ".gemini" / "config" / "mcp_config.json").write_text("")
        t.set_reply(reply="fine")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0, "an empty MCP config, as Antigravity leaves it, is no reason to refuse")

        print("-- an error Antigravity reports")
        kept = json.loads(state.read_text())["blocks"][at_block["hash"]]["session"]
        t.env["STUB_ERROR"] = "1"
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "one more", "--date", DAY)
        t.env.pop("STUB_ERROR")
        s = json.loads(state.read_text())
        check(r.returncode != 0 and "quota" in s["runs"][-1]["error"], "the run fails with Antigravity's words")
        check(s["blocks"][at_block["hash"]]["session"] == kept, "the chat keeps the session it had")

        print("-- the effort written on the model, as opencode writes a variant")
        cfg.update(model="antigravity/gemini-4-neon#xhigh", variant="")
        t.cfg.write_text(json.dumps(cfg))
        t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        argv = json.loads((t.stub_dir / "agy_argv.json").read_text())["argv"]
        check(opt(argv, "--model") == "gemini-4-neon-xhigh", "model and effort as Antigravity's slug")
        cfg.update(model="antigravity/gemini-4-neon#max")
        t.cfg.write_text(json.dumps(cfg))
        (t.stub_dir / "agy_argv.json").unlink()
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode != 0 and "no effort 'max'" in r.stderr and not (t.stub_dir / "agy_argv.json").exists(),
              "an effort Antigravity has no slug for is refused before any call")

        print("-- any other model still goes through opencode")
        cfg["model"] = "openai/gpt-6.2-sol"
        t.cfg.write_text(json.dumps(cfg))
        t.set_reply(reply="from opencode")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and (t.stub_dir / "argv.json").exists()
              and not (t.stub_dir / "agy_argv.json").exists(), "opencode, not Antigravity")
    finally:
        t.cleanup()

    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
