"""A note's blocks as a PDF (2026-11-04, the first diary): the section a
line is in, from its upmost heading; which blocks start in or out; the
layer's marks gone and the words kept; the two looks; where the file goes,
never over one an export did not make; and the Downloads inbox never
taking an export for a course document. Against export.py directly, and
the CLI against a throwaway vault (the PDF itself only where pandoc and
xelatex are installed).

Run: python3 tests/test_export.py
"""
import datetime as dt
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
import blocks  # noqa: E402
import documents as doclib  # noqa: E402
import export  # noqa: E402

failures = 0

NOTE = """[[agents/longhand/daily/2026-11-02|agent]]

# Project brief #studio
Brief words.

# Reflective Research Diary - 2026.11.02 #studio
- [x] one diary a week until Feb 4th ✅ 2026-11-04
## What has happened
It began with the #studio kick-off, see [[Kick-off notes|the kick-off]] and [[Design Lab]].
## What I have learned
> [!private]
> not for the teachers

> *how do we even define it?*
- first point 📅 2026-11-13 ^d58
- second point
### A smaller heading
Words under it. ^abc-1
# Something else #thesis
Not this.
"""


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def units() -> None:
    bl = blocks.split(NOTE)
    line = NOTE.splitlines().index("## What has happened") + 1
    first, end, title = export.section(bl, line)
    check(title is not None and bl[title]["text"].startswith("# Reflective"),
          "a line under a ## is in the section of its upmost heading, the #")
    check(bl[end]["text"].startswith("# Something else") and all(
        not b["text"].startswith("# Project") for b in bl[first:end]),
          "…which ends at the next heading as high, and starts after the one before")
    check(export.section(bl, None)[:2] == (0, len(bl)), "no line: the whole note")
    check(export.section(bl, 0)[2] is not None and export.section(bl, 0)[:2] == (0, len(bl)),
          "a line above every heading: the whole note too")
    check(export.title_of(bl[title]["text"]) == "Reflective Research Diary - 2026.11.02",
          "the title is the heading's words without its tag")

    why = {b["text"].splitlines()[0][:12]: export.starts_in(b) for b in bl}
    check(why["[[agents/lon"] == (False, "Longhand's link to the agent"), "Longhand's agent link starts out")
    check(why["- [x] one di"] == (False, "a checkbox"), "a checkbox starts out")
    check(why["> [!private]"] == (False, "private"), "a private block starts out")
    check(why["- first poin"] == (True, "") and why["> *how do we"] == (True, ""),
          "a plain list item and a quote start in")

    check(export.clean_line("It began with the #studio kick-off, see [[Kick-off notes|the kick-off]] and [[Design Lab]].")
          == "It began with the kick-off, see the kick-off and Design Lab.",
          "tags go, a wikilink keeps its words (its alias, else its name)")
    check(export.clean_line("- first point 📅 2026-11-13 ^d58") == "- first point", "task dates and block ids go")
    check(export.clean_line("- a ⏫ thing ⏳ 2026-11-03 📅 2026-11-05 17:00") == "- a thing",
          "priorities and dated times go")
    check(export.clean_line("[[agents/longhand/daily/2026-11-02|agent]]") == "agent", "a path's alias")
    check(export.clean_line("C# and #1 and a.b/#frag stay") == "C# and #1 and a.b/#frag stay",
          "what only looks like a tag stays")

    kept = [b for b in bl[first:end] if export.starts_in(b)[0] and b is not bl[title]]
    body = export.assemble(kept, 0, lambda name: None)
    check("- first point\n- second point" in body, "list items next to each other stay one list")
    check("not for the teachers" not in body and "one diary a week" not in body, "nothing that starts out is there")
    check("### A smaller heading" in body and "Words under it." in body and "^abc" not in body,
          "a smaller heading keeps its level under a # title")
    shifted = export.assemble([blocks.split("### Deep\ntext")[0]], 1, lambda name: None)
    check(shifted.startswith("## Deep"), "under a ## title, ### moves up to ##")
    check(export.words("## Not counted\nOne two three.\n- four five") == 5, "words: the prose, not the headings")
    callout = export.clean(blocks.split("> [!note] A title\n> words")[0], 0, lambda n: None)
    check(callout == "> **A title**\n> words", "a callout's kind becomes its title in bold")
    pic = pathlib.Path("/tmp/a picture.png")
    check(export.clean(blocks.split("![[a picture.png]]")[0], 0, lambda n: pic) == f"![](<{pic}>)"
          and export.clean(blocks.split("![[gone.png]]")[0], 0, lambda n: None) == "",
          "a picture by its path, and one not found is left out")

    check(export.name_words("Reflective Research Diary - 2026.11.02 #studio") == {"reflective", "research", "diary"},
          "a name's words: no tags, numbers or dates")
    secs = [{"date": "2026-11-09", "line": 3, "level": 1, "heading": "Reflective Research Diary - 2026.11.09 #studio"},
            {"date": "2026-11-02", "line": 2, "level": 1, "heading": "Reflective Research Diary - 2026.11.02 #studio"},
            {"date": "2026-11-03", "line": 0, "level": 1, "heading": "Team meeting #studio"},
            {"date": "2026-11-16", "line": 1, "level": 1, "heading": "Reflective Research Diary - 2026.11.16 #studio"},
            {"date": "2026-11-04", "line": 5, "level": 0, "heading": ""}]
    got = export.candidates(secs, "Reflective Research Diary 2", dt.date(2026, 11, 13), "%Y-%m-%d")
    check([c["date"] for c in got] == ["2026-11-09", "2026-11-02"],
          "a deadline's section: the headings that share its words, newest first, none after its day")
    got = export.candidates(secs, "Pilot study", dt.date(2026, 11, 13), "%Y-%m-%d")
    check([c["date"] for c in got] == ["2026-11-09", "2026-11-03", "2026-11-02"],
          "…and when none does, every headed section by its day, newest first")

    projects = [{"name": "Design Studio", "tag": "studio"}, {"name": "Master Thesis", "tag": "thesis"}]
    check(export.course_of(bl, first, end, title, projects) == "Design Studio", "the course from the title's tag")

    tex = export.look_tex("omarchy", {"background": "2A2A25", "foreground": "EFEDE4", "accent": "F5845B"})
    check(r"\pagecolor{lhbg}" in tex and "F5845B" in tex and "2A2A25" in tex,
          "omarchy: the theme's ground, text and accent")
    check(r"\pagecolor" not in export.look_tex("minimal", {"background": "2A2A25", "foreground": "EFEDE4"})
          and r"\pagecolor" not in export.look_tex("omarchy", {}),
          "minimal is a white page, and so is omarchy with no theme to read")
    with tempfile.TemporaryDirectory() as t:
        toml = pathlib.Path(t) / "colors.toml"
        toml.write_text('mode = "dark"\naccent = "#F5845B"\nbackground = "#2A2A25"\n')
        check(export.theme_colors(toml) == {"accent": "F5845B", "background": "2A2A25"},
              "the theme's colours read from its colors.toml")

    check(export.file_name("Diary: 1/2?") == "Diary 1 2.pdf", "a title made a file name")
    with tempfile.TemporaryDirectory() as t:
        d = pathlib.Path(t)
        (d / "Diary.pdf").write_bytes(b"theirs")
        check(export.place(d, "Diary", set()).name == "Diary (2).pdf", "never over a file an export did not make")
        check(export.place(d, "Diary", {str(d / "Diary.pdf")}).name == "Diary.pdf", "…but over its own")

    with tempfile.TemporaryDirectory() as t:
        d = pathlib.Path(t)
        mine, theirs = d / "Diary.pdf", d / "Slides.pdf"
        mine.write_bytes(b"%PDF-1.4 mine")
        theirs.write_bytes(b"%PDF-1.4 theirs")
        found = [{"src": str(p), "tag": "studio", "course": "Design Studio", "why": "", "got": "2026-11-04T10:00"}
                 for p in (mine, theirs)]
        new = doclib.proposals(found, [], d / "vault", "projects", skip={doclib.content_hash(mine)})
        check([pathlib.Path(x["src"]).name for x in new] == ["Slides.pdf"],
              "the Downloads inbox never proposes filing an export")


def end_to_end() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="export-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    (vault / "Daily" / "2026-11-02.md").write_text(NOTE)
    folder = vault / "agents" / "longhand" / "knowledge" / "projects"
    folder.mkdir(parents=True)
    (folder / "studio.md").write_text("# Design Studio\n\n- Tag: `#studio`\n")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    out = tmp / "Downloads"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand",
                               "export": {"author": "A. Student", "dir": str(out)}}))
    state = tmp / "state"
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir))

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    line = str(NOTE.splitlines().index("It began with the #studio kick-off, see [[Kick-off notes|the kick-off]] and [[Design Lab]]."))
    got = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--list").stdout)
    check(got["title"] == "Reflective Research Diary - 2026.11.02" and got["course"] == "Design Studio"
          and got["author"] == "A. Student" and got["date"] == "2 November 2026",
          f"--list: the title, course, author and day ({got['title']!r}, {got['course']!r})")
    check(got["pdf"] == str(out / "Reflective Research Diary - 2026.11.02.pdf"), "…and the file it would write, in Settings' folder")
    ins = [r["text"].splitlines()[0] for r in got["blocks"] if r["in"]]
    check("## What has happened" in ins and not any(t.startswith("- [x]") for t in ins)
          and not any("Project brief" in t or "Something else" in t for t in ins),
          "…and the section's blocks, each in or out")
    check(not out.exists(), "--list writes nothing")
    check(sum(r["words"] for r in got["blocks"] if r["in"]) == got["words"],
          "each block's words add up to the whole, for the sheet's count")

    sel = NOTE.splitlines().index("- first point 📅 2026-11-13 ^d58")
    got = json.loads(agent("export", "--date", "2026-11-02", "--select", f"{sel}:{sel + 1}", "--list").stdout)
    check([r["text"].splitlines()[0] for r in got["blocks"] if r["in"]] == ["- first point 📅 2026-11-13 ^d58", "- second point"]
          and any(r["why"] == "outside the selection" for r in got["blocks"]),
          "a selection: only the blocks it touches, in its section")
    box = NOTE.splitlines().index("- [x] one diary a week until Feb 4th ✅ 2026-11-04")
    got = json.loads(agent("export", "--date", "2026-11-02", "--select", f"{box}:{box + 5}", "--list").stdout)
    ins = {r["text"].splitlines()[0][:12]: r["in"] for r in got["blocks"]}
    why = {r["text"].splitlines()[0][:12]: r["why"] for r in got["blocks"]}
    check(ins["- [x] one di"] and not ins["> [!private]"] and why["> [!private]"] == "private",
          "…a checkbox selected goes in; a private block selected stays out")
    pick = next(r["hash"] for r in got["blocks"] if r["text"].startswith("> [!private]"))
    got = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--blocks", pick, "--list").stdout)
    check([r["kind"] for r in got["blocks"] if r["in"]] == ["callout"], "--blocks: the person's picks, a private one too")

    r = agent("export", "--date", "2026-11-02", "--look", "pink", ok=False)
    check(r.returncode == 2 and "--look" in r.stderr, "an unknown look is refused")
    r = agent("export", "--file", "../outside.md", ok=False)
    check(r.returncode == 2 and "outside the vault" in r.stderr, "a file outside the vault is refused")
    cfg.write_text(json.dumps(dict(json.loads(cfg.read_text()), export={"dir": str(vault / "Daily")})))
    r = agent("export", "--date", "2026-11-02", "--line", line, ok=False)
    check(r.returncode == 2 and "refusing to write under the daily folder" in r.stderr
          and not any(p.suffix == ".pdf" for p in (vault / "Daily").iterdir()),
          "never into the notes, wherever Settings points")
    cfg.write_text(json.dumps(dict(json.loads(cfg.read_text()), export={"author": "A. Student", "dir": str(out)})))

    (vault / "Daily" / "2026-11-03.md").write_text("# Reflective Research Diary - 2026.11.03 #studio\nThe second week.\n")
    got = json.loads(agent("export", "--for", "Reflective Research Diary 2", "--tag", "studio", "--due", "2026-11-13", "--list").stdout)
    check(got["from"]["date"] == "2026-11-03" and got["from"]["of"] == 2 and got["title"] == "Reflective Research Diary 2"
          and got["pdf"].endswith("Reflective Research Diary 2.pdf") and got["date"] == "3 November 2026",
          f"--for a deadline: its likeliest section, named after it ({got.get('from')})")
    got = json.loads(agent("export", "--for", "Reflective Research Diary 2", "--tag", "studio", "--due", "2026-11-13",
                           "--pick", "1", "--list").stdout)
    check(got["from"]["date"] == "2026-11-02" and got["from"]["pick"] == 1, "--pick: the next one found")
    r = agent("export", "--for", "Reflective Research Diary 2", "--tag", "studio", "--due", "2026-10-01", ok=False)
    check(r.returncode == 2 and "no section" in r.stderr, "nothing written by its day: said, not guessed")

    if not (shutil.which("pandoc") and shutil.which("xelatex")):
        print("skip the PDF itself: pandoc or xelatex is not installed")
        return
    made = json.loads(agent("export", "--date", "2026-11-02", "--line", line).stdout)
    pdf = pathlib.Path(made["pdf"])
    check(pdf.is_file() and pdf.read_bytes()[:5] == b"%PDF-", "the PDF is made")
    text = subprocess.run(["pdftotext", str(pdf), "-"], capture_output=True, text=True).stdout \
        if shutil.which("pdftotext") else ""
    if text:
        check("Reflective Research Diary" in text and "A. Student" in text and "Design Studio" in text
              and "It began with the kick-off" in text, "…with its header and the kept words")
        check("#studio" not in text and "not for the teachers" not in text and "one diary a week" not in text
              and "d58" not in text, "…and without what was left out")
    again = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--look", "omarchy").stdout)
    check(again["pdf"] == made["pdf"] and len(list(out.glob("*.pdf"))) == 1, "a second export replaces its own file")
    record = json.loads((state / "longhand" / "exports.json").read_text())["files"]
    check(len(record) == 1 and record[0]["sha256"] == doclib.content_hash(pdf), "…and the record holds what it is now")
    check(not list(out.glob(".*")), "no half-written file is left beside it")
    got = json.loads(agent("export", "--for", "Reflective Research Diary 9", "--tag", "studio", "--due", "2026-11-02",
                           "--list").stdout)
    check(got["from"]["before"] == ["Reflective Research Diary - 2026.11.02"],
          f"…and a deadline's export says that day was exported before, and as what ({got['from']['before']})")


def main() -> int:
    units()
    end_to_end()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
