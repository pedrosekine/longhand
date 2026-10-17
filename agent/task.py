"""Checkbox lines — Python twin of plugin-page/Task.js.

One grammar for the three kinds of box (note box, task, deadline), the
Obsidian Tasks vocabulary they carry, and what the note around them says:
the headings above a box and the box it is nested under. The reasoning is in
the JS twin's header and in docs/diary.md (2026-10-15).

`tests/test_task.py` runs both over the same lines and notes and fails on
any difference, so neither side may drift.
"""
import re

BOX_RE = re.compile(r"^(\s*)([-*+]) \[([ xX/\-])\](?: (.*))?$")
ANCHOR_RE = re.compile(r"\s\^d(\d+)\s*$")
TAG_RE = re.compile(r"(^|\s)#([\w/-]+)")
FIELD_RE = re.compile(r"\[([a-z]+)::\s*([^\]]*)\]")
DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}))?")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(\S.*?)\s*$")

MARKS = [("📅", "due"), ("⏳", "when"), ("🛫", "start"), ("➕", "created"),
         ("✅", "doneAt"), ("❌", "cancelledAt"), ("🔁", "recur")]
PRIOS = [("🔺", 3), ("⏫", 2), ("🔼", 1), ("🔽", -1), ("⏬", -2)]
MARK_RE = re.compile("(" + "|".join([m[0] for m in MARKS] + [p[0] for p in PRIOS]) + ")")


def _date(s: str) -> str:
    m = DATE_RE.match(s)
    if not m:
        return ""
    return m.group(1) + (" " + ("0" + m.group(2) if len(m.group(2)) == 4 else m.group(2)) if m.group(2) else "")


def parse(line: str) -> dict | None:
    """One checkbox line, or None. Knows nothing of the note around it."""
    m = BOX_RE.match(line)
    if not m:
        return None
    body = re.sub(r"\s+$", "", m.group(4) or "")
    t = {
        "lead": m.group(1) + m.group(2) + " ", "indent": len(m.group(1)), "marker": m.group(2),
        "state": "x" if m.group(3) in "xX" else m.group(3),
        "done": m.group(3) in "xX", "started": m.group(3) == "/", "cancelled": m.group(3) == "-",
        "text": body, "title": "", "tags": [], "project": "", "due": "", "when": "", "start": "",
        "created": "", "doneAt": "", "cancelledAt": "", "recur": "", "priority": 0, "est": "",
        "anchor": 0, "kind": "note",
    }

    rest = body
    a = ANCHOR_RE.search(rest)
    if a:
        t["anchor"] = int(a.group(1))
        rest = rest[:a.start()]

    found = [(mm.start(), mm.group(1)) for mm in MARK_RE.finditer(rest)]
    for i, (at, mark) in enumerate(found):
        to = found[i + 1][0] if i + 1 < len(found) else len(rest)
        seg = rest[at + len(mark):to].strip()
        for glyph, level in PRIOS:
            if glyph == mark:
                t["priority"] = level
        for glyph, key in MARKS:
            if glyph == mark:
                t[key] = seg if key == "recur" else _date(seg)
    words = rest[:found[0][0]] if found else rest

    t["tags"] = [g[1] for g in TAG_RE.findall(words)]
    if t["tags"]:
        t["project"] = t["tags"][0]
    for name, value in FIELD_RE.findall(words):
        if name == "est":
            t["est"] = value.strip()

    t["title"] = re.sub(r"\s+", " ", TAG_RE.sub(r"\1", FIELD_RE.sub(" ", words))).strip()
    t["kind"] = ("deadline" if t["anchor"] > 0 or t["due"] else
                 "task" if t["when"] or t["priority"] else "note")
    return t


def scan(text: str) -> list[dict]:
    """Every checkbox in a note, with its heading path, its project and the
    box it is nested under. A line inside a fence or the frontmatter is
    text, not a task — the regexes this replaces counted both."""
    lines = text.split("\n")
    out: list[dict] = []
    heads: list[dict] = []
    boxes: list[dict] = []
    fence = ""
    front = 1 if lines and re.sub(r"\s+$", "", lines[0]) == "---" else 0
    for i, line in enumerate(lines):
        if front == 1:
            if re.sub(r"\s+$", "", line) == "---":
                front = 2
            continue
        f = FENCE_RE.match(line)
        if f:
            fence = f.group(1) if fence == "" else ("" if f.group(1) == fence else fence)
            continue
        if fence != "":
            continue

        h = HEADING_RE.match(line)
        if h:
            level = len(h.group(1))
            while heads and heads[-1]["level"] >= level:
                heads.pop()
            tags = [g[1] for g in TAG_RE.findall(h.group(2))]
            heads.append({"level": level,
                          "title": re.sub(r"\s+", " ", TAG_RE.sub(r"\1", h.group(2))).strip(),
                          "tag": tags[0] if tags else ""})
            boxes = []
            continue

        t = parse(line)
        # A box with no words is a leftover of editing, not a task
        # (2026-10-17). A bound one keeps its place: its deadline must not be
        # cancelled because its words were cleared.
        if not t or (t["title"] == "" and t["anchor"] == 0):
            continue
        while boxes and boxes[-1]["indent"] >= t["indent"]:
            boxes.pop()
        t["line"] = i
        t["depth"] = len(boxes)
        t["parent"] = boxes[-1]["line"] if boxes else -1
        t["path"] = [x["title"] for x in heads]
        t["claimed"] = ""
        for x in reversed(heads):
            if x["tag"]:
                t["claimed"] = x["tag"]
                break
        if not t["project"]:
            t["project"] = t["claimed"]
        boxes.append({"indent": t["indent"], "line": i})
        out.append(t)
    for t in out:
        t["details"] = details(lines, t["line"], t["indent"])
    return out


def details(lines: list[str], at: int, indent: int) -> int:
    """How many lines of detail a box has: the lines under it indented
    deeper than it, up to the first that is not (docs/tasks.md — details
    stay in the note, under the task)."""
    n = 0
    for line in lines[at + 1:]:
        if line.strip() == "":
            continue
        if len(line) - len(line.lstrip()) <= indent or HEADING_RE.match(line):
            break
        n += 1
    return n


def where(t: dict) -> str:
    """Where a task sits, for a row too narrow for the note."""
    return " › ".join(t.get("path") or [])


ITEM_RE = re.compile(r"^(\s*)(?:[-*+]|\d+[.)])\s+(?:\[[ xX/\-]\](?=\s|$)\s*)?(.*)$")


def identity(text: str) -> str:
    """A block as its conversation knows it: twin of Task.js `identity`.

    Every list line reduced to its words, without its box, its facts or its
    anchor, so ticking, binding or a priority leaves the block the agent
    answered; only changing the words makes it another (2026-10-17).
    """
    out = []
    for line in text.split("\n"):
        m = ITEM_RE.match(line)
        if not m:
            out.append(line)
            continue
        rest = re.sub(r"\s+$", "", m.group(2))
        a = ANCHOR_RE.search(rest)
        if a:
            rest = rest[:a.start()]
        mm = MARK_RE.search(rest)
        if mm:
            rest = rest[:mm.start()]
        out.append(m.group(1) + "- " + re.sub(r"\s+", " ", rest).strip())
    return "\n".join(out)
