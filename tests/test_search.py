"""Search for the day's conversation (agent/search.py, slice 2): the folders
the student switches on, the never-list — private notes and blocks,
_Secrets, types, names, what gitleaks flags — masking, citations by file and
line; and the runner's search-then-answer, against a stub model.

Run: python3 tests/test_search.py
"""
import datetime as dt
import json
import os
import pathlib
import random
import string
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
sys.path.insert(0, str(ROOT / "tests"))
import search  # noqa: E402
from test_documents import pdf  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def vault_at(tmp: pathlib.Path) -> pathlib.Path:
    v = tmp / "vault"
    day = v / "human" / "Daily"
    day.mkdir(parents=True)
    (day / "2026-10-12.md").write_text("# Research Proficiency #respro\n\nShortlist of supervisors: Frauenberger or Neffke.\n\n"
                                       "> [!private]\n> The shortlist worries me, secretly.\n")
    (day / "2026-10-13.md").write_text("---\nagent: false\n---\nThe shortlist, privately.\n")
    r = random.Random(3)
    token = "ghp_" + "".join(r.choice(string.ascii_letters + string.digits) for _ in range(36))
    (day / "2026-10-14.md").write_text(f"Shortlist script token {token}\n\nPay the shortlist fee to AT61 1904 3002 3457 3201.\n")
    (v / "human" / "Studies").mkdir(parents=True)
    (v / "human" / "Studies" / "Reflexive thematic analysis.md").write_text("Braun and Clarke: themes are built, not found.\n")
    pdf(v / "human" / "Studies" / "RTA reading.pdf", "Shortlist of themes in reflexive analysis")
    (v / "human" / "Studies" / "Rechnung Oktober.md").write_text("Shortlist invoice\n")
    (v / "human" / "Studies" / "slides.docx").write_text("Shortlist in a docx\n")
    (v / "human" / "Personal").mkdir(parents=True)
    (v / "human" / "Personal" / "diary.md").write_text("The shortlist, personally.\n")
    (v / "human" / "_Secrets").mkdir(parents=True)
    (v / "human" / "_Secrets" / "shortlist.md").write_text("Shortlist secret.\n")
    return v


def units(tmp: pathlib.Path) -> None:
    v = vault_at(tmp)
    cache = tmp / "cache"
    check("human/_Secrets" not in search.folders(v), "_Secrets is never even listed")
    on = search.switched(v, {})
    check(on["human/Daily"] and on["human/Studies"] and not on["human/Personal"], "defaults: Daily and Studies on, Personal off")
    check(search.switched(v, {"searchFolders": {"human/Personal": True, "human/Studies": False}})["human/Personal"]
          and not search.switched(v, {"searchFolders": {"human/Studies": False}})["human/Studies"],
          "the student's switches win over the defaults")

    r = search.search(v, on, "shortlist", cache)
    paths = {h["path"] for h in r["hits"]}
    texts = " ".join(h["text"] for h in r["hits"])
    check("human/Daily/2026-10-12.md" in paths and any(h["where"] == "line 3" for h in r["hits"] if h["path"] == "human/Daily/2026-10-12.md"),
          f"a passage comes with its file and line ({sorted(paths)})")
    check("secretly" not in texts and "privately" not in texts, "never a private block, never a private note")
    check(not any("Personal" in p or "_Secrets" in p or "Rechnung" in p or p.endswith(".docx") for p in paths),
          "never a folder switched off, _Secrets, a name of money, or another type")
    check("ghp_" not in texts and r["withheld"].get("secret", 0) >= 1, "a passage gitleaks flags is withheld, and counted")
    check("AT61" not in texts and "[IBAN masked]" in texts, "an IBAN is masked")
    check(any(h["path"].endswith("RTA reading.pdf") and h["where"] == "p. 1" for h in r["hits"]), "a PDF's passage comes with its page")
    check(r["withheld"].get("private") == 1 and r["withheld"].get("name") == 1 and r["withheld"].get("type") == 1,
          f"what was withheld is counted, never named ({r['withheld']})")

    w = search.read(v, on, "human/Studies/Reflexive thematic analysis.md", cache)
    check(w.get("complete") and "[line 1]" in w["text"] and "Braun and Clarke" in w["text"], "a file is read whole, with its lines")
    check(search.read(v, on, "human/Personal/diary.md", cache).get("error") == "in a folder that is switched off",
          "…never one in a folder switched off")
    check(search.read(v, on, "human/Daily/2026-10-13.md", cache).get("error") == "private", "…never a private note")
    check(search.read(v, on, "human/_Secrets/shortlist.md", cache).get("error") == "never shared", "…never _Secrets")
    check(search.read(v, on, "../../etc/passwd", cache).get("error") == "not a file in the vault", "…never outside the vault")


STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
n = len([f for f in os.listdir(d) if f.startswith("call-")])
json.dump({"argv": args, "stdin": sys.stdin.read()}, open(os.path.join(d, f"call-{n}.json"), "w"))
if n == 0:
    reply = {"reply": "", "knowledge": [], "search": [{"words": "shortlist supervisors"}], "read": []}
elif n == 1:
    reply = {"reply": "", "knowledge": [], "search": [], "read": [{"file": "human/Daily/2026-10-12.md"}]}
else:
    reply = {"reply": "You wrote it in human/Daily/2026-10-12.md line 3.", "knowledge": [], "search": [], "read": []}
print(json.dumps({"type": "text", "sessionID": "ses_s", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def end_to_end(tmp: pathlib.Path) -> None:
    v = vault_at(tmp / "e2e")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(v), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD"}, "horizon": "2000-01-01",
                               "agentDir": "agents/longhand", "model": "stub/m"}))
    (v / "human" / "Daily" / f"{dt.date.today().isoformat()}.md").write_text("A plain day.\n")
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")
    r = subprocess.run([sys.executable, str(AGENT), "day", "--message", "where did I write about the shortlist?"],
                       capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    calls = [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"))]
    check(len(calls) == 3, f"search, then read, then the answer: three runs, one session ({len(calls)})")
    check("# What you may search" in calls[0]["stdin"] and "`human/Daily`" in calls[0]["stdin"]
          and "`human/Personal`" not in calls[0]["stdin"], "the first message names the folders it may search")
    second = calls[1]["argv"][-1]
    check("## Searched for “shortlist supervisors”" in second and "`human/Daily/2026-10-12.md` line 3" in second
          and "secretly" not in second and "Withheld by the student's rules" in second,
          "the search's passages come back with their file and line; what was withheld is said, not shown")
    third = calls[2]["argv"][-1]
    check("## `human/Daily/2026-10-12.md` — whole" in third and "do not ask for more" in third,
          "a file asked for is read whole, and the last round says to answer")
    st = json.loads(next((v / "agents/longhand/daily").glob("*.json")).read_text())
    turn = st["day"]["turns"][-1]
    check(turn["text"].startswith("You wrote it in") and turn["searched"][0]["hits"][0]["path"] == "human/Daily/2026-10-12.md"
          and turn["files"][0]["path"] == "human/Daily/2026-10-12.md", "the answer keeps what was searched and read")


def horizon(tmp: pathlib.Path) -> None:
    """The agent's horizon (docs/files.md, 2026-10-26): daily notes from
    before it are held back like private ones; unset, it is the first day
    the agent kept, or today on a vault it never ran in."""
    print("-- the horizon")
    tmp = tmp / "horizon"
    tmp.mkdir()
    v = vault_at(tmp)
    cache = tmp / "cache"
    hide = lambda rel: rel.startswith("human/Daily/2026-10-12")
    r = search.search(v, {"human/Daily": True}, "shortlist", cache, hide=hide)
    check(all(h["path"] != "human/Daily/2026-10-12.md" for h in r["hits"]) and r["withheld"].get("horizon") == 1,
          "a hidden day is not searched, and counted as held back")
    check(search.read(v, {"human/Daily": True}, "human/Daily/2026-10-12.md", cache, hide=hide).get("error")
          == "a day before the agent's horizon", "nor read whole")

    cfgdir = tmp / "config"
    cfg = cfgdir / "longhand" / "config.json"
    cfg.parent.mkdir(parents=True)
    cfg.write_text(json.dumps({"vault": str(v), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand"}))
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir))

    def agent(*args):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)

    today = dt.date.today().isoformat()
    h = agent("horizon")
    check(h["horizon"] == today and not h["set"] and h["before"] == 3,
          f"a vault the agent never ran in: the horizon is today, every earlier day behind it ({h})")
    check(agent("search", "--words", "shortlist")["withheld"].get("horizon") == 3, "and search holds them all back")
    kept = v / "agents" / "longhand" / "daily"
    kept.mkdir(parents=True)
    (kept / "2026-10-13.json").write_text("{}")
    (kept / "2026-10-20.json").write_text("{}")
    h = agent("horizon")
    check(h["horizon"] == "2026-10-13" == h["default"] and h["before"] == 1,
          f"unset, it is the first day the agent kept ({h})")
    hits = agent("search", "--words", "shortlist supervisors")["hits"]
    check(not any(x["path"] == "human/Daily/2026-10-12.md" for x in hits), "the day before it is not found")
    (cfg.parent / "settings.json").write_text(json.dumps({"horizon": "2026-10-01"}))
    h = agent("horizon")
    check(h["horizon"] == "2026-10-01" and h["set"] and h["default"] == "2026-10-13" and h["before"] == 0,
          f"set in Settings, it wins ({h})")
    check(any(x["path"] == "human/Daily/2026-10-12.md" for x in agent("search", "--words", "shortlist supervisors")["hits"]),
          "and a day after it is found again")


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="search-test-"))
    units(tmp)
    end_to_end(tmp)
    horizon(tmp)
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
