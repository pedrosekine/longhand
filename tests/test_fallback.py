"""The fallback model (docs/agent.md, "Reaching a model"), tested offline
against a stub `codex` (the model in use) and a stub `claude` (Opus, the
fallback).

Run: python3 tests/test_fallback.py

- a pass the model in use fails (a usage limit) is answered by
  `fallbackModel`, and the ledger and the transcript name the model that
  answered (the transcript named the one that failed: 2026-11-24)
- the model that failed is passed over for a while: the next pass goes
  straight to the fallback, and once the while is over, back to it
- a chat that had a session on the failed model falls back afresh: the
  whole context, with the chat so far, logged before it is sent
- the fallback's own session is resumed while it stands in
- without `fallbackModel`, a failure stays a failure
"""
import datetime as dt
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import test_agent as base  # noqa: E402
import test_claude_route as claude_route  # noqa: E402
import test_codex_route as codex_route  # noqa: E402

ROOT = base.ROOT
DAY = base.DAY
PRIMARY = "codex/gpt-6.2-sol#high"
FALLBACK = "claude-code/claude-opus-5-5#medium"


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
        t.env["CLAUDE_CONFIG_DIR"] = str(t.tmp / "claude-config")
        # Each stub fails on a switch of its own: STUB_ERROR fails Codex only.
        for name, stub in (("codex", codex_route.STUB),
                           ("claude", claude_route.STUB.replace('"STUB_ERROR"', '"STUB_CLAUDE_ERROR"'))):
            f = t.tmp / "bin" / name
            f.write_text(stub)
            f.chmod(0o755)
        home = t.state_home / "longhand" / "codex"
        home.mkdir(parents=True)
        (home / "auth.json").write_text("{}")
        cfg = json.loads(t.cfg.read_text())
        cfg.update(model=PRIMARY, codex=str(t.tmp / "bin" / "codex"), claude=str(t.tmp / "bin" / "claude"))
        t.cfg.write_text(json.dumps(cfg))
        sys.path.insert(0, str(ROOT / "agent"))
        import blocks
        at_block = next(b for b in blocks.split(base.NOTE) if b["text"].startswith("@ "))
        state = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.json"
        transcript = t.vault / "agents" / "longhand" / "daily" / f"{DAY}.md"
        down = t.state_home / "longhand" / "fallback.json"
        codex_argv, claude_argv = t.stub_dir / "codex_argv.json", t.stub_dir / "claude_argv.json"

        def ledger_model():
            return (t.state_home / "longhand" / "cost.tsv").read_text().splitlines()[-1].split("\t")[10]

        def small_line():
            """The last pass's small line in the transcript: what it cost, and who answered."""
            return [l for l in transcript.read_text().splitlines() if l.startswith("<small>")][-1]

        print("-- without a fallback, a failure stays a failure")
        t.set_reply(reply="from the fallback")
        t.env["STUB_ERROR"] = "1"
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode != 0 and "usage limit" in r.stderr and not claude_argv.exists() and not down.exists(),
              "the run fails with the model's words, nothing else is tried")

        print("-- a pass the model in use fails is answered by the fallback")
        cfg["fallbackModel"] = FALLBACK
        t.cfg.write_text(json.dumps(cfg))
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and codex_argv.exists() and claude_argv.exists(),
              f"Codex was tried, then Claude Code answered ({r.stderr.strip()[-200:]})")
        check("from the fallback" in transcript.read_text(), "the fallback's reply lands in the transcript")
        check(ledger_model() == FALLBACK, "the ledger names the model that answered")
        check(small_line().endswith("claude-code/claude-opus-5-5 · medium, in place of codex/gpt-6.2-sol · high</small>"),
              f"…and so does the transcript, and in whose place ({small_line()})")
        argv = json.loads(claude_argv.read_text())["argv"]
        check(argv[argv.index("--model") + 1] == "claude-opus-5-5" and argv[argv.index("--effort") + 1] == "medium",
              "the fallback at its own effort, not the config's variant")
        check("passed over until" in r.stderr and PRIMARY in r.stderr, "it says so, and until when")
        d = json.loads(down.read_text())
        check(d["model"] == PRIMARY and "usage limit" in d["error"], "the model that failed is passed over, with why")

        print("-- while it is passed over, passes go straight to the fallback")
        codex_argv.unlink()
        t.set_reply(reply="still the fallback")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and not codex_argv.exists() and ledger_model() == FALLBACK, "Codex is not called")
        check("claude-opus-5-5" in small_line() and "codex" not in small_line(),
              f"the transcript names the fallback, which was asked first ({small_line()})")

        print("-- once the while is over, the model in use again")
        t.env.pop("STUB_ERROR")
        d["until"] = (dt.datetime.now() - dt.timedelta(minutes=1)).isoformat(timespec="seconds")
        down.write_text(json.dumps(d))
        t.set_reply(reply="back on codex")
        r = t.agent("run", "--trigger", "mention", "--hash", at_block["hash"], "--date", DAY)
        check(r.returncode == 0 and codex_argv.exists() and ledger_model() == PRIMARY, "Codex answers")
        check(small_line().endswith("codex/gpt-6.2-sol#high</small>") and "in place of" not in small_line(),
              f"…and the transcript's line is as it always was ({small_line()})")

        print("-- a chat with a session on the failed model falls back afresh")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "what do you mean?", "--date", DAY)
        check(r.returncode == 0, f"a chat on Codex ({r.stderr.strip()[-200:]})")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "and why Friday?", "--date", DAY)
        check(r.returncode == 0 and json.loads(codex_argv.read_text())["argv"][1] == "resume",
              "…resumed on Codex")
        claude_argv.unlink()
        t.env["STUB_ERROR"] = "1"
        t.set_reply(reply="FALLBACK-IN-THE-CHAT")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "- [ ] one more thing", "--date", DAY)
        check(r.returncode == 0 and claude_argv.exists(), f"the fallback answers the chat ({r.stderr.strip()[-200:]})")
        called = json.loads(claude_argv.read_text())
        check("--resume" not in called["argv"], "afresh: Codex's session is not Claude Code's")
        check("# This chat so far" in called["stdin"] and "why Friday?" in called["stdin"]
              and "Read the DORO brief again." in called["stdin"] and "one more thing" in called["stdin"],
              "the whole context, the chat so far, the new words")
        logged = sorted(t.state_home.glob("longhand/payloads/*-fallback.md"))
        check(logged and "# This chat so far" in logged[-1].read_text(), "logged before it was sent")
        s = json.loads(state.read_text())
        chat = s["blocks"][at_block["hash"]]["chat"]
        check(chat[-1]["role"] == "agent" and "FALLBACK-IN-THE-CHAT" in chat[-1]["text"], "the answer is in the chat")

        print("-- the fallback's own session is resumed while it stands in")
        r = t.agent("chat", "--hash", at_block["hash"], "--message", "thanks", "--date", DAY)
        called = json.loads(claude_argv.read_text())
        check(r.returncode == 0 and "--resume" in called["argv"]
              and called["argv"][called["argv"].index("--resume") + 1] == "cc-sess", "Claude Code resumes its session")
    finally:
        t.cleanup()

    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
