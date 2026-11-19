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
said = stdin + " ".join(args)
read = [{"file": os.environ.get("STUB_READ", "")}] if "READ-PAPER" in said and "# What you asked for" not in said else []
reply = {"reply": f"answer {n}", "knowledge": [], "read": read,
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
        return [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"), key=lambda f: int(f.stem[5:]))]

    rel = "human/Studies/FHOÖ/Session 1.md"
    talk = vault / "agents/longhand/notes" / (hashlib.md5(rel.encode()).hexdigest()[:16] + ".json")

    agent("note", "--file", rel, "--message", "what did I say about themes?")
    first = calls()[-1]
    pay = first["stdin"]
    check("Reflexive thematic analysis: themes are built." in pay and f"# The note: `{rel}`" in pay,
          "the first message carries the note whole, by its path")
    check("not today's note" in pay and "Propose only what the student asks for" in pay and "# What you may propose" in pay,
          "…told what this conversation is, and what it may propose when asked (slice 4 of One conversation)")
    check("SECRET-CALLOUT" not in pay and "agent: false" not in pay, "…never its private callout, nor its frontmatter")
    check(pay.rstrip().endswith("what did I say about themes?"), "…and what the student says")
    t = json.loads(talk.read_text())
    check(t["path"] == rel and t["session"] == "ses_note" and [x["role"] for x in t["turns"]] == ["student", "agent"]
          and t["turns"][1]["text"] == "answer 0", "kept in the agent's folder by the note's md5, with its session")
    check(t["turns"][1].get("proposals") == [] and t["turns"][1].get("unoffered") == ["deadline · made up"],
          f"a proposal that does not hold is not taken, and said ({t['turns'][1].get('unoffered')})")
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

    # Helpful or not (the improvement loop): the student's word on an
    # answer in a note's conversation, kept on its turn and in feedback.tsv.
    # Turns: 0 asked, 1 "answer 0", 2 asked with a block, 3 "answer 1", …
    agent("rate", "down", "--note", rel, "--turn", "3")
    t = json.loads(talk.read_text())
    check(t["turns"][3]["rating"]["value"] == "down" and "rating" not in t["turns"][1],
          "rated not helpful: kept on its turn of the note's conversation")
    fb = (tmp / "state" / "longhand" / "feedback.tsv").read_text().splitlines()[-1].split("\t")
    check(fb[2] == f"note:{rel}#3" and fb[3] == "note" and fb[4] == "down" and fb[7].endswith("-note.md"),
          f"…and in feedback.tsv, with the payload that made it ({fb})")
    agent("rate", "none", "--note", rel, "--turn", "3")
    check("rating" not in json.loads(talk.read_text())["turns"][3], "the same word again takes it back")
    check(agent("rate", "up", "--note", rel, "--turn", "2", ok=False).returncode != 0, "…never a student's turn")
    check(agent("rate", "up", "--note", "human/Studies/none.md", "--turn", "1", ok=False).returncode != 0,
          "…nor a note with no conversation")
    agent("rate", "down", "--note", rel, "--turn", "3")
    review = agent("review").stdout
    check("## Talking about a note" in review and "1 not helpful" in review and f"about `{rel}`" in review
          and "answer 1" in review and f"eval add {fb[7]} --job day" in review,
          "the weekly review lists the miss, with the command that makes it a case")
    # A later message made a case: joined to the conversation's first
    # message and the turns between, as a day case is.
    agent("eval", "add", fb[7], "--id", "note-miss")
    case = json.loads((vault / "agents/longhand/evals/cases/note-miss.json").read_text())
    pay = case["payload"]
    check(case["job"] == "day" and "# This conversation" in pay and "Longhand: answer 0" in pay
          and "and this?" in pay.split("# The next message")[-1],
          f"a note's answer becomes a day case, its conversation joined to its first message ({pay[-600:]!r})")
    payloads = list((tmp / "state").rglob("*-note.md"))
    check(len(payloads) == 4, f"every message logged before inference ({len(payloads)})")
    # A paper (plan.md item 15, step 2): a PDF's conversation, kept as a
    # note's; its marks travel, the marks pointed at with their page's
    # text, the paper whole only when the agent asks to read it.
    sys.path.insert(0, str(ROOT / "tests"))
    from test_read import pdf as lined_pdf
    paper = "human/_Attachments/Course/Smith 2020.pdf"
    lined_pdf(vault / paper, [["Why testing helps", "Retrieval changes the memory it retrieves."] + ["filler line one"] * 8,
                              ["Spacing compounds the effect.", "Sessions a day apart beat one sitting."] + ["filler two"] * 8,
                              ["The closing argument, page three only."]])
    read_cli = ROOT / "cli" / "longhand-read"

    def mark(page, words, kind="h"):
        r = subprocess.run([str(read_cli), "mark", "--pdf", paper, "--page", str(page), "--text", words, "--kind", kind,
                            "--day", "2026-11-15"], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr

    mark(1, "Retrieval changes the memory")
    mark(2, "Sessions a day apart", "q")
    reading = vault / "human" / "Readings" / "Smith 2020.md"
    subprocess.run([str(read_cli), "note", "--pdf", paper, "--id", "h2", "--text", "does sleep matter?"],
                   capture_output=True, text=True, env=env, check=True)
    before_note, before_pdf = reading.read_text(), (vault / paper).read_bytes()
    agent("note", "--file", paper, "--message", "what is this paper about?")
    pay = calls()[-1]["stdin"]
    check("reading a paper" in pay and f"# The paper: `{paper}`" in pay and "3 pages." in pay,
          "a paper's first message says what this is, and names the paper")
    check("- `h1` p. 1, highlight, 2026-11-15: “Retrieval changes the memory”" in pay
          and "- `h2` p. 2, question, 2026-11-15: “Sessions a day apart”\n  their note: does sleep matter?" in pay,
          "…with what they marked, kinds, days and their notes")
    check("The closing argument" not in pay and "Spacing compounds" not in pay, "…but not the paper's text")
    check(f'`read` with {{"file": "{paper}"}}' in pay and "“exact words” (p. 12)" in pay and "`h3:`" in pay,
          "…told to read it whole when asked about the whole, to quote with the page, to answer questions one by one")
    ptalk = vault / "agents/longhand/notes" / (hashlib.md5(paper.encode()).hexdigest()[:16] + ".json")
    check(json.loads(ptalk.read_text())["path"] == paper, "kept as a note's conversation, by the PDF's path")

    agent("note", "--file", paper, "--message", "explain this", "--marks", "h2")
    msg = calls()[-1]["argv"][-1]
    check("# The student points at `h2` (p. 2, question)" in msg and "> Sessions a day apart" in msg
          and "Their note on it: does sleep matter?" in msg, "a mark pointed at goes with the message, with their note")
    check("## Page 2 of the paper, where it stands" in msg and "Spacing compounds the effect." in msg
          and "Why testing helps" not in msg, "…and its page's text, only that page")
    check("# What they have marked" not in msg, "the marks unchanged are not sent again")
    t = json.loads(ptalk.read_text())
    check(t["turns"][-2].get("marks") == ["h2"], "the turn keeps which marks it pointed at")

    mark(3, "The closing argument")
    agent("note", "--file", paper, "--message", "and h1 and h3?", "--marks", "h1,h3")
    msg = calls()[-1]["argv"][-1]
    check("# What they have marked, as it is now" in msg and "`h3` p. 3" in msg, "a new mark: the marks are sent again")
    check(msg.count("## Page") == 2, "…each pointed-at mark with its own page")

    n0 = len(calls())
    env["STUB_READ"] = paper
    agent("note", "--file", paper, "--message", "summarise it READ-PAPER")
    follow = calls()[-1]["argv"][-1]
    check(len(calls()) == n0 + 2 and "# What you asked for" in follow and "The closing argument, page three only." in follow
          and "(not read" not in follow,
          "asked to read it, the agent is given the paper whole, though its folder is not searched")
    check((vault / paper).read_bytes() == before_pdf, "the PDF is never written")

    # What the student is reading, for the day's agent (plan.md item 15):
    # the paper marked today, its project, and its questions no answer has
    # come to — h2 was answered above, a new one waits.
    subprocess.run([str(read_cli), "tag", "--pdf", paper, "--tag", "thesis"], capture_output=True, text=True, env=env, check=True)
    r = subprocess.run([str(read_cli), "mark", "--pdf", paper, "--page", "2", "--text", "Sessions a day apart beat one sitting",
                        "--kind", "q"], capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    waiting_id = next(m["id"] for m in json.loads(r.stdout)["marks"] if m["text"] == "Sessions a day apart beat one sitting")
    rd = json.loads(subprocess.run([str(read_cli), "reading"], capture_output=True, text=True, env=env).stdout)
    smith = next(x for x in rd["papers"] if x["title"] == "Smith 2020")
    check(smith["tags"] == ["thesis"] and [w["id"] for w in smith["waiting"]] == [waiting_id],
          f"reading: the paper, its project, the questions still waiting (the answered one not) ({smith})")
    agent("day", "--message", "what is on today?")
    pay = calls()[-1]["stdin"]
    check("# What the student is reading" in pay and "**Smith 2020** #thesis" in pay
          and "1 question waiting:" in pay and "Sessions a day apart beat one sitting" in pay,
          "the day's first message says what the student is reading, with the questions waiting")
    check("Do not answer those questions here" in pay, "…and that answering them is the paper's own chat's")

    lined_pdf(vault / "human" / "Personal" / "garden plans.pdf", [["Where the roses go this spring"] * 30])

    # Another paper pointed at with `@` in a paper's chat (2026-11-19, the
    # student: "@ a different paper so I can mention it to the agent"): it
    # comes as they read it — its project, their marks and notes — never
    # its text unasked; the paper talked about is not pointed at twice, a
    # private one is counted, never shown.
    other = "human/Studies/Moser 2026.pdf"
    lined_pdf(vault / other, [["Stress hotspots on the way to work."] + ["filler moser"] * 8,
                              ["Body signals give an unbiased record of the ride."] + ["more filler"] * 8])
    r = subprocess.run([str(read_cli), "mark", "--pdf", other, "--page", "2", "--text", "an unbiased record", "--kind", "q",
                        "--day", "2026-11-18"], capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    subprocess.run([str(read_cli), "note", "--pdf", other, "--id", "h1", "--text", "unbiased, really?"],
                   capture_output=True, text=True, env=env, check=True)
    subprocess.run([str(read_cli), "tag", "--pdf", other, "--tag", "thesis"], capture_output=True, text=True, env=env, check=True)
    env.pop("STUB_READ", None)
    agent("note", "--file", paper, "--message", "does Moser agree?", "--marks", "h1", "--refs", json.dumps([
        {"file": other}, {"file": paper}, {"file": "human/Personal/garden plans.pdf"}]))
    def sent():
        c = calls()[-1]
        return c["stdin"] if c["argv"][-1] == "Context follows on stdin." else c["argv"][-1]
    msg = sent()
    check(f"# The paper the student points at: Moser 2026 (`{other}`)" in msg and "2 pages. Its project: #thesis." in msg
          and "- `h1` p. 2, question, 2026-11-18: “an unbiased record”\n  their note: unbiased, really?" in msg,
          "a paper pointed at comes with its project, their marks and their notes")
    check(f'`read` with {{"file": "{other}"}}' in msg and f"(`{other}`, p. 12)" in msg and "Stress hotspots" not in msg,
          "…to be read when asked, quoted by its path and page, never its text unasked")
    check(f"# The paper the student points at: Smith 2020 (`{paper}`)" not in msg and "(1 more they pointed at cannot be shown" in msg
          and "roses" not in msg, "…the paper talked about is not pointed at again; a private one is counted, not shown")
    check(msg.index("# The paper the student points at") < msg.index("# The student says")
          and "# The student points at `h1`" in msg, "…beside its own mark, before what the student says")
    t = json.loads(ptalk.read_text())
    asked = next(x for x in t["turns"] if x.get("text") == "does Moser agree?")
    check(asked.get("refs") == [{"file": other, "kind": "paper", "head": "Moser 2026"}] and asked.get("marks") == ["h1"],
          f"the turn keeps what it pointed at, for its chips ({asked.get('refs')})")
    logged = [json.loads(l) for f in (vault / "agents").rglob("*.jsonl") if "convers" in str(f)
              for l in f.read_text().splitlines() if l.strip()]
    said = [x for x in logged if x.get("text") == "does Moser agree?"]
    check(said and said[0]["subjects"] == [f"paper:{paper}"],
          f"…a paper's chat kept from search (its folder is off) files nothing under the paper it points at ({said[0]['subjects'] if said else 'not logged'})")
    merk = "human/Studies/Merk 2021.pdf"
    lined_pdf(vault / merk, [["Stress where a near miss once happened."] + ["filler merk"] * 8])
    agent("note", "--file", other, "--message", "and Merk?", "--refs", json.dumps([{"file": merk}]))
    logged = [json.loads(l) for f in (vault / "agents").rglob("*.jsonl") if "convers" in str(f)
              for l in f.read_text().splitlines() if l.strip()]
    said = [x for x in logged if x.get("text") == "and Merk?"]
    check(said and f"paper:{other}" in said[0]["subjects"] and f"paper:{merk}" in said[0]["subjects"],
          f"…one the agent may see is filed under both papers, so the other's chat remembers it ({said[0]['subjects'] if said else 'not logged'})")
    n0 = len(calls())
    env["STUB_READ"] = other
    agent("note", "--file", paper, "--message", "read Moser READ-PAPER", "--refs", json.dumps([{"file": other}]))
    follow = calls()[-1]["argv"][-1]
    check(len(calls()) == n0 + 2 and "Body signals give an unbiased record" in follow and "(not read" not in follow,
          "asked to read the paper pointed at, the agent is given it")
    env.pop("STUB_READ", None)
    agent("note", "--file", rel, "--message", "and that paper?", "--refs", json.dumps([{"file": other}]))
    pay = sent()
    check(f"# The paper the student points at: Moser 2026 (`{other}`)" in pay, "a note's chat may point at a paper too")
    r = agent("note", "--file", paper, "--message", "x", "--refs", "not json", ok=False)
    check(r.returncode != 0 and "--refs" in r.stderr, "…and --refs that is not JSON is refused")

    r = agent("note", "--file", "human/Personal/garden plans.pdf", "--message", "x", ok=False)
    check(r.returncode != 0 and "private" in r.stderr,
          f"a PDF in a private folder is never talked about ({r.stderr.strip()})")
    lined_pdf(vault / "human" / "Studies" / "scan.pdf", [[]])
    r = agent("note", "--file", "human/Studies/scan.pdf", "--message", "x", ok=False)
    check(r.returncode != 0 and "no words" in r.stderr and "read it first" in r.stderr,
          "a PDF with no words is said to have none, and how to read it")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
