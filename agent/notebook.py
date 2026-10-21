"""The agent's notebook, seen and corrected by the person (docs/agent.md,
slice 3, 2026-10-18).

The notebook is the agent's knowledge folder: `profile.md`, `patterns.md`,
`projects/<name>.md`, which the model rewrites whole; `answers.md`, the
person's answers to its questions; `dismissed.md`, what they dismissed. The
person sees it line by line and may **correct** a line or **forget** it.
Local code does both at once in the agent's file, and records it in
`corrections.md` — written by Longhand, read by the agent every run, never
written by it. Every time the model rewrites a file, the record is applied
again (`enforce`), so a correction made once stays made even when the model
copies the old line back.
"""
from __future__ import annotations

import datetime as dt
import re
from pathlib import Path

CORRECTIONS = "corrections.md"
ANSWERS = "answers.md"
DISMISSED = "dismissed.md"
# What the model never writes and is not shown as its own notes.
NOT_THE_MODELS = (CORRECTIONS, ANSWERS, DISMISSED)

HEAD = ("# The student's corrections\n\n"
        "What the student corrected in the agent's notes, or told it to forget. Written by Longhand when they do it "
        "in Settings, never by the agent; these overrule the agent's own notes.\n\n")
ENTRY = re.compile(r"^- (\d{4}-\d{2}-\d{2}) · (forget|correct) · ([^:]+): «(.*?)»(?: → «(.*)»)?\s*$")
LINE = re.compile(r"^(\s*)(?:[-*+] |\d+\. )?(.*)$")


def norm(text: str) -> str:
    """How two lines are compared: case, spacing and a trailing full stop
    do not make them different."""
    return re.sub(r"\s+", " ", text).strip().rstrip(".").casefold()


def _files(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    own = sorted(p for p in folder.rglob("*.md") if p.is_file() and p.name not in NOT_THE_MODELS)
    order = {"profile.md": 0, "patterns.md": 1}
    # The days' briefs (`days/<date>.md`) after the rest, the newest first.
    days = sorted((p for p in own if p.parent.name == "days"), key=lambda p: p.name, reverse=True)
    rest = sorted((p for p in own if p.parent.name != "days"),
                  key=lambda p: (order.get(str(p.relative_to(folder)), 2), str(p.relative_to(folder))))
    return rest + days


def _entries_of(folder: Path, f: Path) -> tuple[str, list[dict]]:
    name = str(f.relative_to(folder))
    title, out = "", []
    for i, raw in enumerate(f.read_text(errors="replace").split("\n")):
        if not raw.strip():
            continue
        if raw.startswith("#"):
            title = title or raw.lstrip("#").strip()
            continue
        m = LINE.match(raw)
        out.append({"file": name, "line": i, "depth": len(m.group(1).expandtabs(2)) // 2, "text": m.group(2).strip()})
    return title or name, out


def read(folder: Path) -> dict:
    """The notebook as the Settings sheet shows it: each of the agent's
    files with its lines, the person's answers, and the corrections."""
    files = []
    for f in _files(folder):
        title, lines = _entries_of(folder, f)
        if lines:
            files.append({"file": str(f.relative_to(folder)), "title": title, "lines": lines})
    answers = []
    if (folder / ANSWERS).is_file():
        answers = _entries_of(folder, folder / ANSWERS)[1]
        answers = [a for a in answers if a["depth"] == 0 and not a["text"].startswith("What the student told")]
    return {"files": files, "answers": answers, "corrections": corrections(folder)}


def corrections(folder: Path) -> list[dict]:
    f = folder / CORRECTIONS
    out = []
    for raw in f.read_text(errors="replace").split("\n") if f.is_file() else []:
        m = ENTRY.match(raw)
        if m:
            out.append({"n": len(out), "date": m.group(1), "how": m.group(2), "file": m.group(3),
                        "text": m.group(4), "to": m.group(5) or ""})
    return out


def _save_corrections(folder: Path, items: list[dict], write) -> None:
    body = "".join(f"- {c['date']} · {c['how']} · {c['file']}: «{c['text']}»"
                   + (f" → «{c['to']}»" if c["how"] == "correct" else "") + "\n" for c in items)
    write(folder / CORRECTIONS, HEAD + body)


def _clean(text: str) -> str:
    # One line, and nothing that would break the record's own syntax.
    return re.sub(r"\s+", " ", text).replace("«", "\"").replace("»", "\"").strip()


def _find(folder: Path, file: str, text: str) -> tuple[Path, list[str], int]:
    f = (folder / file).resolve()
    if folder.resolve() not in f.parents or f.name in (CORRECTIONS, DISMISSED) or not f.is_file():
        raise ValueError(f"not a notebook file: {file}")
    lines = f.read_text(errors="replace").split("\n")
    want = norm(text)
    for i, raw in enumerate(lines):
        if raw.strip() and not raw.startswith("#") and norm(LINE.match(raw).group(2)) == want:
            return f, lines, i
    raise ValueError(f"that line is no longer in {file}")


def _span(lines: list[str], i: int) -> int:
    """A line and the lines nested under it: forgetting a list item forgets
    what hangs off it."""
    depth = len(LINE.match(lines[i]).group(1))
    j = i + 1
    while j < len(lines) and lines[j].strip() and len(LINE.match(lines[j]).group(1)) > depth:
        j += 1
    return j


def forget(folder: Path, file: str, text: str, write, today: dt.date | None = None) -> dict:
    """Takes the line (and what is nested under it) out of the file. In the
    agent's files the forgetting is recorded, so it stays forgotten; an
    answer of the person's own is simply removed — the agent may ask again."""
    f, lines, i = _find(folder, file, text)
    old = LINE.match(lines[i]).group(2).strip()
    del lines[i:_span(lines, i)]
    write(f, "\n".join(lines))
    if f.name == ANSWERS:
        return {"how": "forget", "file": file, "text": old, "recorded": False}
    items = corrections(folder)
    if not any(c["how"] == "forget" and norm(c["text"]) == norm(old) for c in items):
        items.append({"date": (today or dt.date.today()).isoformat(), "how": "forget", "file": file,
                      "text": _clean(old), "to": ""})
        _save_corrections(folder, items, write)
    return {"how": "forget", "file": file, "text": old, "recorded": True}


def correct(folder: Path, file: str, text: str, to: str, write, today: dt.date | None = None) -> dict:
    """Puts the person's words in the line's place, keeping its place in the
    list, and records the correction."""
    to = _clean(to)
    if not to:
        raise ValueError("a correction needs the corrected words")
    f, lines, i = _find(folder, file, text)
    if f.name == ANSWERS:
        raise ValueError("an answer is yours: forget it, and answer again when asked")
    m = LINE.match(lines[i])
    old = m.group(2).strip()
    prefix = lines[i][:len(lines[i]) - len(m.group(2))]
    lines[i] = prefix + to
    write(f, "\n".join(lines))
    items = [c for c in corrections(folder) if not (c["how"] == "correct" and norm(c["text"]) == norm(old))]
    items.append({"date": (today or dt.date.today()).isoformat(), "how": "correct", "file": file,
                  "text": _clean(old), "to": to})
    _save_corrections(folder, items, write)
    return {"how": "correct", "file": file, "text": old, "to": to, "recorded": True}


def take_back(folder: Path, n: int, write) -> dict:
    """Removes one correction from the record. The line it changed is not
    restored; the agent is simply no longer held to it."""
    items = corrections(folder)
    if not 0 <= n < len(items):
        raise ValueError(f"no correction #{n}")
    gone = items.pop(n)
    _save_corrections(folder, items, write)
    return gone


def enforce(content: str, items: list[dict]) -> str:
    """A file the model rewrote, with the corrections applied again: a
    forgotten line (and what is nested under it) left out, a corrected
    line's old words replaced by the person's."""
    if not items:
        return content
    forgotten = {norm(c["text"]) for c in items if c["how"] == "forget"}
    fixed = {norm(c["text"]): c["to"] for c in items if c["how"] == "correct"}
    lines = content.split("\n")
    out, i = [], 0
    while i < len(lines):
        raw = lines[i]
        m = LINE.match(raw)
        key = norm(m.group(2)) if raw.strip() and not raw.startswith("#") else ""
        if key and key in forgotten:
            i = _span(lines, i)
            continue
        if key and key in fixed:
            raw = raw[:len(raw) - len(m.group(2))] + fixed[key]
        out.append(raw)
        i += 1
    return "\n".join(out)


def payload_section(folder: Path) -> list[str]:
    """What the model is told of the corrections, every run."""
    items = corrections(folder)
    if not items:
        return []
    out = ["", "# The student's corrections to your notes (they overrule your knowledge files; when you rewrite a file,"
               " keep what they corrected as corrected, and never write back what they told you to forget)", ""]
    for c in items:
        if c["how"] == "forget":
            out.append(f"- {c['date']}, {c['file']}: forget \"{c['text']}\" — it is not true, or not yours to keep.")
        else:
            out.append(f"- {c['date']}, {c['file']}: not \"{c['text']}\" but \"{c['to']}\".")
    return out
