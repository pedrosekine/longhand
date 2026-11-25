"""What Longhand writes and sends ends its lines with "\\n", on every system.

On Linux nothing has to be done for it. On Windows, Python writes "\\r\\n"
for every "\\n" of a file or a pipe opened as text, and the first day on a
real vault (2026-11-24) showed what that costs: the agent's files in a
vault shared with Linux machines, an installed prompt's fingerprint, and
every Codex run dropped — its session file held "\\r\\n" where Longhand had
sent "\\n" (windows/pyshim/longhand_lf.py). Against a stub model, a
throwaway vault and state.

Run: python3 tests/test_line_endings.py
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


# The model keeps what it was sent as it came, byte for byte (every call's:
# it is also asked things with nothing on stdin).
STUB = """#!/usr/bin/env python3
import json, os, sys
sent = sys.stdin.buffer.read()
open(os.path.join(os.environ["STUB_DIR"], "sent.bin"), "ab").write(sent)
reply = json.dumps({"reply": "By when do you want to decide?\\nAnd what would change it?", "proposals": [], "suggestions": [], "knowledge": []})
print(json.dumps({"type": "text", "sessionID": "ses_lines", "part": {"type": "text", "text": "```json\\n" + reply + "\\n```"}}))
"""


def carrying_cr(folder: pathlib.Path) -> list[str]:
    return sorted(p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file() and b"\r" in p.read_bytes())


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="lines-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    agent_dir = vault / "agents/longhand"
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": vault.as_posix(), "daily": {"dir": "Daily", "format": "YYYY-MM-DD",
                                                                   "template": "agents/longhand/templates/daily"},
                               "agentDir": "agents/longhand", "model": "stub/margin", "planModel": "stub/plan"}))
    state = tmp / "state"
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}{os.pathsep}{os.environ['PATH']}")

    def agent(*args):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr + r.stdout
        return r

    # A prompt installed is the repo's, byte for byte: `prompt_version` reads
    # the bytes, and the same prompt must not read as changed on a system
    # that would have written its lines another way.
    agent("install")
    installed = cfgdir / "opencode" / "agent"
    names = ("longhand.md", "longhand-plan.md", "longhand-judge.md", "longhand-day.md")
    check(all((installed / n).read_bytes() == (ROOT / "agent" / "opencode" / n).read_bytes() for n in names),
          "an installed prompt is the repo's file, byte for byte")
    check(not carrying_cr(vault), "install writes the vault's template with \\n: " + ", ".join(carrying_cr(vault)))

    # One pass: what the model is sent, what is logged of it, and what the
    # agent then writes into the vault.
    today = dt.date.today().isoformat()
    (vault / "Daily" / f"{today}.md").write_bytes(
        b"# Reading\n\nShould I buy an e-scooter?\n\n- [ ] ask the shop about the battery\n")
    agent("run", "--trigger", "open")
    sent = (stub / "sent.bin").read_bytes() if (stub / "sent.bin").exists() else b""
    check(b"e-scooter" in sent and sent.count(b"\n") > 2, f"the model was sent the day's context ({len(sent)} bytes, {sent.count(10)} lines)")
    check(b"\r" not in sent, "…with \\n as every line's ending")
    logs = sorted((state / "longhand" / "payloads").glob("*.md"))
    check(bool(logs) and all(b"\r" not in p.read_bytes() for p in logs), "the payload log says it the same way")
    transcript = agent_dir / "daily" / f"{today}.md"
    check(transcript.exists() and transcript.read_bytes().count(b"\n") > 3, "the pass was answered into the agent's own file")
    check(not carrying_cr(vault), "nothing the agent wrote into the vault carries \\r: " + ", ".join(carrying_cr(vault)))
    check(not carrying_cr(state), "nor what it keeps beside it: " + ", ".join(carrying_cr(state)))
    check((vault / "Daily" / f"{today}.md").read_bytes() ==
          b"# Reading\n\nShould I buy an e-scooter?\n\n- [ ] ask the shop about the battery\n", "the note is the file it was")

    print(f"\n{failures} failure(s)")
    return failures


if __name__ == "__main__":
    sys.exit(main())
