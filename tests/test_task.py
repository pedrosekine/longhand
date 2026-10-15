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
new Function('module', src + '\\nmodule.parse = parse;\\nmodule.scan = scan;\\nmodule.where = where;')(m);
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify({
  lines: input.lines.map(m.parse),
  notes: input.notes.map(m.scan),
  wheres: input.notes.map(n => m.scan(n).map(m.where)),
}));
"""

LINES = [
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
    other = js({"lines": LINES, "notes": notes})

    for line, got in zip(LINES, other["lines"]):
        mine = task.parse(line)
        if mine != got:
            failures += 1
            print(f"MISMATCH parse {line!r}\n  py={json.dumps(mine, ensure_ascii=False)}"
                  f"\n  js={json.dumps(got, ensure_ascii=False)}")
    print(f"ok   {len(LINES)} lines parse the same in both")

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
    print(f"ok   {len(notes)} notes scan the same in both ({len(fixtures)} of them fixtures)")

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
    check(task.scan(NOTES[2])[0]["path"] == ["Untitled", "Lab"], "a rule is not frontmatter")
    check(task.scan(NOTES[2])[0]["project"] == "intsem", "the innermost tagged heading claims")

    # Nesting that goes out further than it came in.
    t = task.scan(NOTES[3])
    check([x["depth"] for x in t] == [0, 1, 1, 0], "an outdent finds the level it belongs to")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
