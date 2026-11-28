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
    pic = pathlib.Path("/vault/a picture.png")         # a path only: never written
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
    check([c["date"] for c in got] == ["2026-11-09", "2026-11-02", "2026-11-03", "2026-11-16"],
          "a deadline's section: the headings that share its words, newest first; then the rest, never dropped")
    check([c["late"] for c in got] == [False, False, False, True],
          "…and those written after its day last, marked late (late work, or more time given)")
    got = export.candidates(secs, "Pilot study", dt.date(2026, 11, 13), "%Y-%m-%d")
    check([c["date"] for c in got] == ["2026-11-09", "2026-11-03", "2026-11-02", "2026-11-16"],
          "…and when none does, every headed section by its day, newest first")
    later = secs + [{"date": "2026-11-20", "line": 0, "level": 1, "heading": "Diary, late #studio"}]
    got = export.candidates(later, "Pilot study", dt.date(2026, 11, 13), "%Y-%m-%d")
    check([c["date"] for c in got if c["late"]] == ["2026-11-16", "2026-11-20"],
          "…the late ones nearest its day first")

    # Fenced code is one block, written as it is (2026-11-28, the export pass).
    code = "# Notes\nBefore it.\n```python\n# a comment, no heading\n- no item\nx = '#ffffff'  # #todo\n```\nAfter it.\n"
    cb = export.split(code)
    check([b["kind"] for b in cb] == ["heading", "paragraph", "code", "paragraph"],
          f"a fenced block is one block: its # comment is no heading ({[b['kind'] for b in cb]})")
    check(export.section(cb, 5)[:2] == (0, 4), "…so a section never splits inside code")
    check(export.clean(cb[2], 0, lambda n: None) == "\n".join(code.splitlines()[2:7]),
          "…and goes as written: its #todo and #ffffff stay")
    check(export.words(export.assemble(cb[1:], 0, lambda n: None)) == 4, "…and its words are not the prose's")
    check([b["hash"] for b in export.split(NOTE)] == [b["hash"] for b in blocks.split(NOTE)],
          "a note without fences: blocks.py's own blocks and hashes")
    check(export.split("a\n```\nnever closed\n# x")[-1]["kind"] == "code", "a fence never closed runs to the end")
    check(export.clean_line("use `#include` and `a[[0]]` with #tag") == "use `#include` and `a[[0]]` with",
          "inline code keeps its # and brackets; a tag outside it goes")
    check(export.clean_line("a -> b <- c <-> d `x->y` [l](http://a->b)", True)
          == "a → b ← c ↔ d `x->y` [l](http://a->b)",
          "arrows written as the note draws them, never in code or a link")
    check(export.clean_line("a -> b") == "a -> b", "…and only when asked (a face that has them)")
    check(export.clean(blocks.split("> [!warning]\n> careful")[0], 0, lambda n: None) == "> **Warning**\n> careful"
          and export.clean(blocks.split("> [!my-tip]-\n> x")[0], 0, lambda n: None) == "> **My tip**\n> x",
          "a callout with no title of its own says its kind")
    check(export.words("- [x] done, see [the notes](https://example.com/a/b/c)") == 4,
          "words: a link's label, not its address; a box is no word")
    check(export.shown(blocks.split("- [ ] read **chapter 2** of [[papers/Moser 2026|Moser]] #thesis 📅 2026-11-13 ^d1")[0])
          == "- [ ] read chapter 2 of Moser"
          and export.shown(blocks.split("> [!note] Seen\n> *quoted* -> [here](https://x.y)")[0]) == "Seen\nquoted → here"
          and export.shown(blocks.split("### Deep #studio")[0]) == "Deep",
          "the sheet's rows: the words that go, without the marks")
    pic = pathlib.Path("/vault/a picture.png")
    check(export.lost(blocks.split("![[a picture.png]] ![[gone.png]] ![[Other note]]")[0],
                      lambda n: pic if n == "a picture.png" else None) == ["gone.png", "Other note"],
          "what will be missing: a picture not found, an embedded note")

    projects = [{"name": "Design Studio", "tag": "studio"}, {"name": "Master Thesis", "tag": "thesis"}]
    check(export.course_of(bl, first, end, title, projects) == "Design Studio", "the course from the title's tag")

    tex = export.look_tex("omarchy", {"background": "2A2A25", "foreground": "EFEDE4", "accent": "F5845B"})
    check(r"\pagecolor{lhbg}" in tex and "F5845B" in tex and "2A2A25" in tex,
          "omarchy: the theme's ground, text and accent")
    check(r"\pagecolor" not in export.look_tex("minimal", {"background": "2A2A25", "foreground": "EFEDE4"})
          and r"\pagecolor" not in export.look_tex("omarchy", {}),
          "minimal is a white page, and so is omarchy with no theme to read")
    check(r"\sethlcolor{lhmark}" in tex and r"\ifdefined\sethlcolor" in tex,
          "omarchy: a highlight in the accent sunk into the ground, not soul's yellow under light text")
    check(export.font() == "Adwaita Sans" and export.font("No Such Face Here") == "Adwaita Sans",
          "the face: the page's own Adwaita Sans, from its cuts, when none asked for is installed")
    check("mainfontoptions=Path=" in " ".join(export.face_options("Adwaita Sans"))
          and export.face_options("Some Face") == ["-V", "mainfont=Some Face"] and export.face_options("") == [],
          "…set by its files, so its bold and italic are its own cuts")
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

    if os.name == "nt":
        have = export.installed_fonts()
        check("Segoe UI" in have or "Arial" in have, "Windows font discovery finds system fonts without fc-list")
        sample = "Segoe UI" if "Segoe UI" in have else "Arial"
        check(export.font(sample) == sample, f"export.font({sample!r}) resolves an installed Windows face")
        check(export.font("NoSuchLonghandFontXYZ") == export.font(),
              "export.font passes over a face asked for that is not installed")
        check(export.font() == "Segoe UI" or "iA Writer Quattro S" in have or "iA Writer Duo S" in have,
              "with no face asked for, Windows' reading face rather than pandoc's Computer Modern")

        # No theme file on Windows: the omarchy look is Windows' own light
        # or dark and accent, as the page draws there.
        sys.path.insert(0, str(ROOT / "windows"))
        import palette  # noqa: E402
        for dark in (False, True):
            got = palette.theme(dark)
            check(got["background"] == palette.GROUND[dark][0] and got["foreground"] == palette.GROUND[dark][1]
                  and got["accent"].startswith("#") and len(got["accent"]) == 7,
                  f"Windows' {'dark' if dark else 'light'} ground, text and accent under a theme's names")
        if not export.COLORS.is_file():
            got = export.theme_colors()
            check({"background", "foreground", "accent", "muted", "blue"} <= set(got)
                  and all(len(v) == 6 and not v.startswith("#") for v in got.values()),
                  "no colors.toml on Windows: the theme's colours are Windows' own")
            check(r"\pagecolor{lhbg}" in export.look_tex("omarchy", got),
                  "…and the omarchy look is drawn in them, not a white page")
        with tempfile.TemporaryDirectory() as t:
            check(export.theme_colors(pathlib.Path(t) / "none.toml") == {},
                  "a colors.toml asked for by name and missing is still no colours")


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
    two = NOTE.splitlines().index("Words under it. ^abc-1")
    got = json.loads(agent("export", "--date", "2026-11-02", "--select", f"{two}:{two + 1}", "--list").stdout)
    check([r["text"] for r in got["blocks"] if r["in"]] == ["Words under it. ^abc-1", "# Something else #thesis"],
          f"a selection into the next section: its blocks there too ({[r['text'] for r in got['blocks'] if r['in']]})")
    pick = next(r["hash"] for r in got["blocks"] if r["text"].startswith("> [!private]"))
    got = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--blocks", pick, "--list").stdout)
    check([r["kind"] for r in got["blocks"] if r["in"]] == ["callout"], "--blocks: the person's picks, a private one too")
    first = next(r for r in got["blocks"] if r["text"] == "- second point")
    check(first["show"] == "- second point" and first["level"] == 0 and first["lost"] == []
          and next(r for r in got["blocks"] if r["kind"] == "heading" and r["why"] != "the title")["level"] == 2,
          "each row says what it shows, its level, and what it will miss")

    (vault / "Daily" / "2026-11-05.md").write_text("# Twice\n\n---\n\nOne.\n\n---\n\nTwo.\n\n---\n")
    got = json.loads(agent("export", "--date", "2026-11-05", "--line", "0", "--list").stdout)
    rules = [r for r in got["blocks"] if r["text"] == "---"]
    check(len(rules) == 3 and len({r["hash"] for r in rules}) == 1, "three rules: one hash")
    got = json.loads(agent("export", "--date", "2026-11-05", "--line", "0", "--list",
                           "--blocks", f"{rules[1]['start']}:{rules[1]['hash']}").stdout)
    check([r["start"] for r in got["blocks"] if r["in"]] == [rules[1]["start"]],
          "--blocks START:HASH picks one of identical blocks, not all three")
    got = json.loads(agent("export", "--date", "2026-11-05", "--line", "0", "--list",
                           "--blocks", f"{rules[1]['start'] + 1}:{rules[1]['hash']}").stdout)
    check(sum(r["in"] for r in got["blocks"]) == 1, "…moved a line, the nearest with its words")
    got = json.loads(agent("export", "--date", "2026-11-05", "--line", "0", "--list", "--blocks", rules[0]["hash"]).stdout)
    check(sum(r["in"] for r in got["blocks"]) == 3, "…and a bare hash (the page before) every block with it")
    r = agent("export", "--date", "2026-11-29", "--list", ok=False)
    check(r.returncode == 2 and "nothing is written on 29 November 2026 yet" in r.stderr and str(vault) not in r.stderr,
          f"a day with no note says so, not its path ({r.stderr.strip()!r})")

    (cfgdir / "longhand" / "settings.json").write_text(json.dumps({"export": {"author": "B. Student"}}))
    got = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--list").stdout)
    check(got["author"] == "B. Student" and got["pdf"].startswith(str(out)),
          "the name set from the page joins config.json's export, its folder kept")
    (cfgdir / "longhand" / "settings.json").unlink()

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
    check(got["from"]["date"] == "2026-11-03" and got["from"]["of"] == 3 and not got["from"]["late"]
          and got["title"] == "Reflective Research Diary 2"
          and got["pdf"].endswith("Reflective Research Diary 2.pdf") and got["date"] == "3 November 2026",
          f"--for a deadline: its likeliest section, named after it ({got.get('from')})")
    got = json.loads(agent("export", "--for", "Reflective Research Diary 2", "--tag", "studio", "--due", "2026-11-13",
                           "--pick", "1", "--list").stdout)
    check(got["from"]["date"] == "2026-11-02" and got["from"]["pick"] == 1, "--pick: the next one found")
    got = json.loads(agent("export", "--for", "Reflective Research Diary 2", "--tag", "studio", "--due", "2026-10-01",
                           "--list").stdout)
    check(got["from"]["late"] and got["from"]["date"] == "2026-11-02",
          f"nothing written by its day: what was written after, said as late ({got['from']})")
    r = agent("export", "--for", "Pilot", "--tag", "nosuch", ok=False)
    check(r.returncode == 2 and "no section of #nosuch" in r.stderr, "no section of its course at all: said, not guessed")

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
    check(not made["replaces"], "a first export replaces nothing")
    listed = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--list").stdout)
    check(listed["replaces"], "…a second says it will replace its own")
    (out / "Theirs.pdf").write_bytes(b"%PDF-1.4 theirs")
    listed = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--list").stdout)
    check(listed["taken"] == sorted([pdf.name, "Theirs.pdf"]) and listed["ours"] == [pdf.name],
          "…and lists the folder's PDFs and which an export made, for the sheet to name any title's file")
    (out / "Theirs.pdf").unlink()
    again = json.loads(agent("export", "--date", "2026-11-02", "--line", line, "--look", "omarchy").stdout)
    check(again["pdf"] == made["pdf"] and len(list(out.glob("*.pdf"))) == 1, "a second export replaces its own file")
    record = json.loads((state / "longhand" / "exports.json").read_text())["files"]
    check(len(record) == 1 and record[0]["sha256"] == doclib.content_hash(pdf), "…and the record holds what it is now")
    check(not list(out.glob(".*")), "no half-written file is left beside it")
    got = json.loads(agent("export", "--for", "Reflective Research Diary 9", "--tag", "studio", "--due", "2026-11-02",
                           "--list").stdout)
    check(got["from"]["before"] == ["Reflective Research Diary - 2026.11.02"],
          f"…and a deadline's export says that section was exported before, and as what ({got['from']['before']})")
    got = json.loads(agent("export", "--for", "Project brief 9", "--tag", "studio", "--due", "2026-11-02",
                           "--list").stdout)
    check(got["from"]["heading"] == "Project brief" and got["from"]["before"] == [],
          f"…but not another section of that day ({got['from']})")

    # Code and a highlight on the theme's ground: the PDF is made.
    (vault / "Daily" / "2026-11-06.md").write_text("# Code #studio\n==marked== -> on\n```python\n# c\nx = 1\n```\n")
    made = json.loads(agent("export", "--date", "2026-11-06", "--line", "1", "--look", "omarchy").stdout)
    text = subprocess.run(["pdftotext", made["pdf"], "-"], capture_output=True, text=True).stdout \
        if shutil.which("pdftotext") else ""
    check(pathlib.Path(made["pdf"]).is_file() and (not text or ("→ on" in text and "# c" in text)),
          f"…code and a highlight in the omarchy look, the arrow drawn ({text!r})")


def main() -> int:
    units()
    end_to_end()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
