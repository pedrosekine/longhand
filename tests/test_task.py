#!/usr/bin/env python3
"""Cross-check the JS and Python checkbox grammars, then the rules they are
there to enforce: the three kinds, the heading path, the parent box, and
lines that only look like tasks.

Run: python3 tests/test_task.py   (needs node on PATH for the JS side)
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import task  # noqa: E402

JS_SHIM = """
const fs = require('fs');
let src = fs.readFileSync(process.argv[1], 'utf8').replace('.pragma library', '');
const m = {};
new Function('module', src + '\\nmodule.parse = parse;\\nmodule.scan = scan;\\nmodule.where = where;'
  + '\\nmodule.setField = setField;\\nmodule.setPriority = setPriority;\\nmodule.setState = setState;'
  + '\\nmodule.nextPriority = nextPriority;\\nmodule.sameWords = sameWords;\\nmodule.setWords = setWords;\\nmodule.identity = identity;')(m);
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify({
  lines: input.lines.map(m.parse),
  notes: input.notes.map(m.scan),
  wheres: input.notes.map(n => m.scan(n).map(m.where)),
  identities: input.lines.concat(input.notes).map(m.identity),
  edits: input.edits.map(e => e[1] === 'field' ? m.setField(e[0], e[2], e[3])
    : e[1] === 'prio' ? m.setPriority(e[0], e[2])
    : e[1] === 'state' ? m.setState(e[0], e[2])
    : e[1] === 'same' ? m.sameWords(e[0], e[2])
    : e[1] === 'words' ? m.setWords(e[0], e[2])
    : e[1] === 'identity' ? m.identity(e[0])
    : m.nextPriority(e[0])),
}));
"""

LINES = [
    # Inside a quote or a callout (2026-10-27): the `> ` is lead, not nesting.
    "> - [ ] call mum",
    "> > - [x] deeper done ✅ 2026-10-27",
    ">\t- [ ] tab after the quote",
    "- [ ] plain",
    "- [ ]",
    "- [ ] ",
    "  - [ ] indented two",
    "\t- [ ] a tab",
    "    * [x] done with a star",
    "+ [/] started",
    "- [-] cancelled",
    "- [X] capital x",
    "- [?] not a state we know",
    "not a checkbox at all",
    "- [ ] read ch.7 #hfpi",
    "- [ ] read ch.7 #hfpi #again",
    "- [ ] call mum 📅 2026-10-16",
    "- [ ] call mum 📅 2026-10-16 9:00",
    "- [ ] call mum 📅 2026-10-16 17:00 ^d6",
    "- [ ] seminar prep ⏳ 2026-10-18",
    "- [ ] seminar prep ⏳ 2026-10-18 📅 2026-10-20",
    "- [ ] top of the pile 🔺",
    "- [ ] high ⏫",
    "- [ ] medium 🔼",
    "- [ ] low 🔽",
    "- [ ] lowest ⏬",
    "- [x] weekly reading 🔁 every week 📅 2026-10-20 ✅ 2026-10-19",
    "- [ ] draft the intro #dtm ⏫ ⏳ 2026-10-18 📅 2026-10-20 17:00 ^d12",
    "- [ ] write up [est:: 90m] #respro",
    "- [ ] write up [est:: 1h] ⏳ 2026-10-17",
    "- [-] abandoned ❌ 2026-10-14",
    "- [ ] chapter #1 of the thing",
    "- [ ] a line with 📅 but no date at all",
    "- [ ] trailing spaces   ",
    "- [ ] 🛫 2026-10-20 ➕ 2026-10-15",
]

NOTES = [
    # Headings pop by level; a box under no heading has no path.
    "- [ ] orphan\n\n# Design Theory #dtm\n\n## Essay 2\n\n- [ ] draft the intro\n"
    "  - [ ] find sources\n    - [ ] the library one\n  - [x] outline\n\n## Reading\n\n- [ ] ch.7\n"
    "\n# Interdisciplinary Seminar #intsem\n\n- [ ] slides ⏳ 2026-10-18\n",
    # A fence and frontmatter are text, not tasks.
    "---\nagent: false\n---\n\n# Notes #hfpi\n\n- [ ] real one\n\n```markdown\n- [ ] in a fence\n```\n\n"
    "~~~\n- [ ] in the other fence\n~~~\n\n- [ ] after the fence\n",
    # A rule is not frontmatter, and a tagged H3 inside an untagged H1 claims.
    "# Untitled\n\n---\n\n### Lab #intsem\n\n- [ ] bring the cable\n",
    # Indentation that goes out further than it came in.
    "# A\n\n- [ ] one\n      - [ ] deep\n  - [ ] shallower\n- [ ] back to the top\n",
    # Empty, and a note of nothing but a heading.
    "",
    "# Only a heading #dtm\n",
    # Callouts (2026-10-27): a private one's boxes are private; nesting holds
    # inside a quote and never crosses its edge; a quote's details stay in it.
    "- [ ] plain box\n  its detail\n\n> [!private]\n> - [ ] private box\n> \t- [ ] nested private\n>   a detail\n"
    "> - [ ] second private\n\n> [!note]\n> - [ ] box in a note callout\n- [ ] after the callout\n",
]


# Changing a line: the words must come back byte for byte, the fields in a
# canonical order, the anchor last. The page is the only writer of notes, so
# these are the only edits a note ever gets that the student did not type.
DATED = "- [ ] draft the intro #dtm 📅 2026-10-20 17:00 ^d12"
EDITS = [
    # [line, op, arg, arg] → expected
    ([DATED, "field", "⏳", "2026-10-18"],
     "- [ ] draft the intro #dtm ⏳ 2026-10-18 📅 2026-10-20 17:00 ^d12"),
    ([DATED, "field", "📅", "2026-10-22"],
     "- [ ] draft the intro #dtm 📅 2026-10-22 ^d12"),
    ([DATED, "field", "📅", ""],
     "- [ ] draft the intro #dtm ^d12"),
    ([DATED, "prio", 2, None],
     "- [ ] draft the intro #dtm ⏫ 📅 2026-10-20 17:00 ^d12"),
    ([DATED, "state", "x", None],
     "- [x] draft the intro #dtm 📅 2026-10-20 17:00 ^d12"),
    (["- [ ] plain", "prio", 2, None], "- [ ] plain ⏫"),
    (["- [ ] plain ⏫", "prio", -1, None], "- [ ] plain 🔽"),
    (["- [ ] plain ⏫", "prio", 0, None], "- [ ] plain"),
    (["- [ ] plain 🔺 ⏳ 2026-10-18", "prio", -2, None], "- [ ] plain ⏬ ⏳ 2026-10-18"),
    (["  - [ ] nested", "field", "⏳", "2026-10-18"], "  - [ ] nested ⏳ 2026-10-18"),
    (["- [ ]", "field", "⏳", "2026-10-18"], "- [ ] ⏳ 2026-10-18"),
    (["- [ ] two   spaces   kept #tag", "prio", 2, None], "- [ ] two   spaces   kept #tag ⏫"),
    (["- [ ] 🔁 every week 📅 2026-10-20", "field", "✅", "2026-10-19"],
     "- [ ] 🔁 every week 📅 2026-10-20 ✅ 2026-10-19"),
    (["- [ ] odd 🧿 something we do not know 📅 2026-10-20", "field", "⏳", "2026-10-18"],
     "- [ ] odd 🧿 something we do not know ⏳ 2026-10-18 📅 2026-10-20"),
    (["not a checkbox", "field", "⏳", "2026-10-18"], "not a checkbox"),
    # Finding the line again after the facts on it have changed: a drop adds
    # ❌ to it, and Ctrl+Z has to find it anyway.
    (["- [-] loose thought ❌ 2026-10-15", "same", "loose thought", None], True),
    (["- [ ] loose thought ⏫", "same", "loose thought", None], True),
    (["- [ ] loose thought again", "same", "loose thought", None], False),
    (["- [ ] read ch.7 #hfpi ⏳ 2026-10-18", "same", "read ch.7 #hfpi", None], True),
    (["# a heading", "same", "a heading", None], False),
    (["- [ ] draft the intro #dtm ⏳ 2026-10-18 📅 2026-10-20 ^d12", "words", "draft the introduction #dtm", None],
     "- [ ] draft the introduction #dtm ⏳ 2026-10-18 📅 2026-10-20 ^d12"),
    (["- [x] old words ", "words", "  new   words ", None], "- [x] new words"),
    # A block's conversation is found by its words: the box, the facts and
    # the anchor are not part of it, nor is the kind of list marker.
    (["- [ ] should I buy a scooter?", "identity", None, None], "- should I buy a scooter?"),
    (["- [x] should I buy a scooter?", "identity", None, None], "- should I buy a scooter?"),
    (["- [-] should I buy a scooter? ❌ 2026-10-17", "identity", None, None], "- should I buy a scooter?"),
    (["- [ ] should I buy a scooter? ⏫ 📅 2026-10-20 17:00 ^d4", "identity", None, None], "- should I buy a scooter?"),
    (["- should I buy a scooter?", "identity", None, None], "- should I buy a scooter?"),
    (["1. should I buy a scooter?", "identity", None, None], "- should I buy a scooter?"),
    (["- [ ] should I buy an e-scooter?", "identity", None, None], "- should I buy an e-scooter?"),
    (["- [ ] list\n  - [x] child ⏳ 2026-10-18\n  more words", "identity", None, None], "- list\n  - child\n  more words"),
    (["a question?", "identity", None, None], "a question?"),
    (["- [ ] #dtm draft [est:: 1h]", "identity", None, None], "- #dtm draft [est:: 1h]"),
    ([0, "cycle", None, None], 2),
    ([2, "cycle", None, None], -1),
    ([-1, "cycle", None, None], 0),
    ([1, "cycle", None, None], -1),
]


def js(payload: dict) -> dict:
    out = subprocess.run(["node", "-e", JS_SHIM, str(ROOT / "plugin-page" / "Task.js")],
                         input=json.dumps(payload).encode(), capture_output=True, check=True)
    return json.loads(out.stdout)


failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    global failures
    fixtures = sorted((ROOT / "tests" / "fixtures").glob("*.md"))
    notes = NOTES + [f.read_text() for f in fixtures]
    other = js({"lines": LINES, "notes": notes, "edits": [e[0] for e in EDITS]})

    for (spec, want), got in zip(EDITS, other["edits"]):
        check(got == want, f"{spec[1]} {spec[2]!r} → {got!r}"
              + ("" if got == want else f" (wanted {want!r})"))

    for spec, want in EDITS:
        if spec[1] == "identity":
            got = task.identity(spec[0])
            check(got == want, f"py identity {spec[0]!r} → {got!r}" + ("" if got == want else f" (wanted {want!r})"))
    texts = LINES + notes
    same = [task.identity(t) for t in texts] == other["identities"]
    check(same, f"{len(texts)} lines and notes have the same identity in both")

    before = failures
    for line, got in zip(LINES, other["lines"]):
        mine = task.parse(line)
        if mine != got:
            failures += 1
            print(f"MISMATCH parse {line!r}\n  py={json.dumps(mine, ensure_ascii=False)}"
                  f"\n  js={json.dumps(got, ensure_ascii=False)}")
    print(("ok   " if failures == before else "FAIL ") + f"{len(LINES)} lines parse the same in both")

    before = failures
    names = [f"note {i}" for i in range(len(NOTES))] + [f.name for f in fixtures]
    for name, text, got, wheres in zip(names, notes, other["notes"], other["wheres"]):
        mine = task.scan(text)
        if mine != got:
            failures += 1
            print(f"MISMATCH scan {name}\n  py={json.dumps(mine, ensure_ascii=False)}"
                  f"\n  js={json.dumps(got, ensure_ascii=False)}")
        if [task.where(t) for t in mine] != wheres:
            failures += 1
            print(f"MISMATCH where {name}")
    print(("ok   " if failures == before else "FAIL ") + f"{len(notes)} notes scan the same in both ({len(fixtures)} of them fixtures)")

    # The three kinds, which is the whole point of the grammar.
    kind = lambda line: task.parse(line)["kind"]
    check(kind("- [ ] ask about the rubric") == "note", "a bare box is a note box")
    check(kind("- [ ] ask about the rubric #dtm") == "note", "a tag alone does not make a task")
    check(kind("- [ ] seminar prep ⏳ 2026-10-18") == "task", "a do-date makes it a task")
    check(kind("- [ ] seminar prep ⏫") == "task", "a priority makes it a task")
    check(kind("- [ ] seminar prep 🔽") == "task", "so does a low one")
    check(kind("- [ ] hand in 📅 2026-10-20") == "deadline", "a due date makes it a deadline")
    check(kind("- [ ] hand in ⏳ 2026-10-18 ^d6") == "deadline", "so does being bound to the store")

    # What the note says about a box.
    t = task.scan(NOTES[0])
    by_title = {x["title"]: x for x in t}
    check(by_title["orphan"]["path"] == [], "a box under no heading has no path")
    check(by_title["orphan"]["project"] == "", "…and no project to inherit")
    check(by_title["draft the intro"]["path"] == ["Design Theory", "Essay 2"],
          "the path is the headings above it, tags stripped")
    check(by_title["draft the intro"]["project"] == "dtm", "the project is claimed from the tagged heading")
    check(by_title["ch.7"]["path"] == ["Design Theory", "Reading"], "an H2 pops the H2 before it")
    check(by_title["slides"]["path"] == ["Interdisciplinary Seminar"], "an H1 pops everything")
    check(by_title["slides"]["project"] == "intsem", "…and claims for its own tag")
    check(by_title["find sources"]["parent"] == by_title["draft the intro"]["line"]
          and by_title["find sources"]["depth"] == 1, "a nested box knows its parent")
    check(by_title["the library one"]["parent"] == by_title["find sources"]["line"]
          and by_title["the library one"]["depth"] == 2, "…two deep as well")
    check(by_title["outline"]["parent"] == by_title["draft the intro"]["line"],
          "a sibling shares the parent")
    check(by_title["ch.7"]["parent"] == -1, "a heading ends the nesting above it")

    # Lines that only look like tasks.
    t = task.scan(NOTES[1])
    check([x["title"] for x in t] == ["real one", "after the fence"],
          "a box in a fence or the frontmatter is text, not a task")
    t = task.scan("- [ ] essay\n  what the brief says\n\n  - [ ] outline\n- [ ] next\n# h\n  under a heading")
    check([x["details"] for x in t] == [2, 0, 0], "a box counts the lines of detail under it, and a sibling or heading ends them")
    t = task.scan("- [ ]\n- [ ] \n- [x]\n- [ ] 📅 2026-10-20 ^d4\n- [ ] words")
    check([x["line"] for x in t] == [3, 4], "an empty box is not a task; a bound one with its words cleared still is")
    check(task.scan(NOTES[2])[0]["path"] == ["Untitled", "Lab"], "a rule is not frontmatter")
    check(task.scan(NOTES[2])[0]["project"] == "intsem", "the innermost tagged heading claims")

    # Boxes inside callouts.
    c = task.scan(NOTES[-1])
    check([x["title"] for x in c] == ["plain box", "private box", "nested private", "second private",
                                       "box in a note callout", "after the callout"],
          f"boxes inside callouts are found ({[x['title'] for x in c]})")
    check([x["private"] for x in c] == [False, True, True, True, False, False], "a private callout's boxes are private, no other's")
    check([x["depth"] for x in c] == [0, 0, 1, 0, 0, 0], "nesting holds inside a quote, and never crosses its edge")
    check([x["details"] for x in c][:4] == [1, 2, 1, 0], "a quote's details stay inside it (a nested box is its parent's detail, as anywhere)")
    check(task.parse("> - [ ] call mum")["lead"] == "> - " and task.parse("> - [ ] call mum")["indent"] == 0,
          "the quote is lead, not nesting")

    # Nesting that goes out further than it came in.
    t = task.scan(NOTES[3])
    check([x["depth"] for x in t] == [0, 1, 1, 0], "an outdent finds the level it belongs to")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
