"""A project's file: how one is made, and what in it stays the person's
(2026-10-22).

A project is one file in the agent's knowledge/projects/ — the tag from a
`Tag: #x` line (else the file name), the name from its H1. Until now only
the agent or the person's own editor made one; now the page does, when the
person asks (a new `#tag` in the note, or the sidebar's "new project"), and
the agent may only propose one. Once a project exists the agent may add to
its file, but never rename it or change its tag: the name and the tag are
what the sidebar, `@` and every heading in the notes go by.
"""
from __future__ import annotations

import re
from pathlib import Path

TAG = re.compile(r"[\w/-]{1,40}")
TAG_LINE = re.compile(r"Tag:\s*`?#([\w/-]+)")
NAME_MAX = 80


def clean_tag(tag: str) -> str:
    """The tag as written, without its `#`; "" when it cannot be one."""
    t = str(tag or "").strip().lstrip("#")
    return t if TAG.fullmatch(t) else ""


def clean_name(name: str) -> str:
    return re.sub(r"\s+", " ", str(name or "")).strip()[:NAME_MAX]


def file_name(tag: str) -> str:
    """The file a new project is written to: its tag, in the characters a
    knowledge file may have (a `/` or a letter outside ASCII becomes `-`)."""
    return re.sub(r"[^A-Za-z0-9._-]", "-", tag)[:64] + ".md"


def stub(name: str, tag: str) -> str:
    return f"# {name}\n\n- Tag: `#{tag}`\n"


def read(folder: Path) -> list[dict]:
    """Every project file: its file, name and tag."""
    out = []
    for f in sorted(folder.glob("*.md")) if folder.is_dir() else []:
        try:
            text = f.read_text()
        except OSError:
            continue
        out.append({"file": f.name, "name": name_of(text, f.stem), "tag": tag_of(text, f.stem)})
    return out


def name_of(text: str, stem: str) -> str:
    return next((l[2:].strip() for l in text.splitlines() if l.startswith("# ")), stem)


def tag_of(text: str, stem: str) -> str:
    m = TAG_LINE.search(text)
    return m.group(1) if m else stem


def taken(folder: Path, tag: str) -> bool:
    """Whether a project already goes by this tag, or its file exists."""
    low = tag.lower()
    return (folder / file_name(tag)).exists() or any(p["tag"].lower() == low for p in read(folder))


def keep_identity(old: str, new: str, stem: str) -> str:
    """The agent's rewrite of a project file, with the file's name (its H1)
    and its tag as they were: whatever else it changes, the project is not
    renamed or re-tagged behind the person."""
    name, tag = name_of(old, stem), tag_of(old, stem)
    lines = new.split("\n")
    h1 = next((i for i, l in enumerate(lines) if l.startswith("# ")), -1)
    if h1 >= 0:
        lines[h1] = "# " + name
    else:
        lines = ["# " + name, ""] + lines
        h1 = 0
    had_line = TAG_LINE.search(old) is not None
    at = next((i for i, l in enumerate(lines) if TAG_LINE.search(l)), -1)
    if at >= 0:
        # The line may say more than the tag (a course code, the term); only
        # the tag itself is put back.
        lines[at] = TAG_LINE.sub(lambda m: m.group(0)[:m.start(1) - m.start(0)] + tag, lines[at], count=1)
    elif had_line:
        lines[h1 + 1:h1 + 1] = ["", f"- Tag: `#{tag}`"]
    return "\n".join(lines)
