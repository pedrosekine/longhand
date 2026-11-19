"""The names a paper and a note are shown by (2026-11-19, the student, at
the `@` list: "can we have the meaningful names instead of the file names
in there?", and the same name everywhere one is shown).

A paper named by its BibTeX key (`moser2023individual.pdf`, as the thesis
keeps them) is shown as its bibliography has it: "Moser et al. 2023", its
title beside it where there is room. The entry comes from the nearest .bib
that has the key, nearest by the folders the two share (a project's own
bibliography before another project's). Any other paper is its file's
name, which filing already makes "Surname Year Title". A note is its first
heading, a paper's reading notes "<the paper> — reading notes", else the
file's name; a private note always its file's name.

One rule for the `@` list and its chips (`conversation --files`), a
paper's header and its marks list (`longhand-read state`), the day's READ
list (`longhand-read days`), the project's papers (`longhand-read papers`)
and a quote of another paper in a chat. The files are never renamed.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

SKIP = {"archive", "build"}


def bib_fields(body: str) -> dict:
    """An entry's fields, `name = {value}`, `name = "value"` or `name =
    2019`, braces nested as BibTeX nests them."""
    out, i = {}, 0
    while True:
        m = re.compile(r"(\w+)\s*=\s*(?:([{\"])|(\d+))").search(body, i)
        if not m:
            return out
        if m.group(3):
            out[m.group(1).lower()] = m.group(3)
            i = m.end()
            continue
        close, depth, j = ("}" if m.group(2) == "{" else '"'), 1, m.end()
        while j < len(body) and depth:
            c = body[j]
            if m.group(2) == "{" and c == "{":
                depth += 1
            elif c == close and body[j - 1] != "\\":
                depth -= 1
            j += 1
        out[m.group(1).lower()] = body[m.end():j - 1]
        i = j


def _plain(v: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[{}]|\\(?=[_&%$#])", "", v)).strip()


def _surname(n: str) -> str:
    return (n.split(",")[0] if "," in n else n.split()[-1]).strip()


def entries(text: str) -> dict:
    """A .bib's entries by key (lower case): {authors, year, title}, the
    authors as "Moser", "Moser and Resch" or "Moser et al."."""
    out = {}
    for m in re.finditer(r"@\w+\s*\{\s*([^,\s]+)\s*,", text):
        end = text.find("\n@", m.end())
        fields = bib_fields(text[m.end():end if end >= 0 else len(text)])
        names = [n.strip() for n in re.split(r"\s+and\s+", _plain(fields.get("author", fields.get("editor", "")))) if n.strip()]
        first = _surname(names[0]) if names else ""
        year = (re.search(r"\d{4}", fields.get("year", "") or fields.get("date", "")) or [""])[0]
        out.setdefault(m.group(1).lower(), {
            "authors": first + (" et al." if len(names) > 2 else f" and {_surname(names[1])}" if len(names) == 2 else ""),
            "year": year, "title": _plain(fields.get("title", ""))})
    return out


def label(c: dict) -> str:
    """ "Moser et al. 2023" for a bibliography's entry; "" without authors."""
    return f"{c['authors']} {c.get('year', '')}".strip() if c and c.get("authors") else ""


class Bibs:
    """The vault's bibliographies, read once: every .bib outside hidden,
    `_`, archive and build folders."""

    def __init__(self, vault: Path, under: str = ""):
        self.vault = Path(vault)
        self.books: list[tuple[tuple, dict]] = []    # (its folder's parts, vault-relative; its entries)
        top = self.vault / under if under else self.vault
        for d, dirs, files in os.walk(top) if top.is_dir() else []:
            dirs[:] = sorted(x for x in dirs if not x.startswith((".", "_")) and x not in SKIP)
            for f in sorted(files):
                if not f.endswith(".bib"):
                    continue
                try:
                    text = (Path(d) / f).read_text(errors="replace")
                except OSError:
                    continue
                self.books.append((Path(d).relative_to(self.vault).parts, entries(text)))

    def cite(self, rel: str, near: str = "") -> dict:
        """A paper's entry, by its file's stem: from the .bib nearest to
        `near` (a project's folder), else to the paper itself."""
        key = Path(rel).stem.lower()
        at = Path(near or str(Path(rel).parent)).parts
        best, score = {}, -1
        for parts, got in self.books:
            if key not in got:
                continue
            n = 0
            while n < min(len(parts), len(at)) and parts[n] == at[n]:
                n += 1
            if n > score:
                best, score = got[key], n
        return best

    def paper(self, rel: str, near: str = "") -> tuple[str, str]:
        """(its name, its title): ("Moser et al. 2023", "An Individual-…"),
        or (the file's stem, "") when no bibliography has it."""
        c = self.cite(rel, near)
        return (label(c), c.get("title", "")) if label(c) else (Path(rel).stem, "")


def heading(text: str) -> str:
    """A note's first line when it is a `# heading`, past its frontmatter:
    its words, links and emphasis taken off."""
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                lines = lines[i + 1:]
                break
        else:
            return ""
    for line in lines:
        if not line.strip():
            continue
        m = re.match(r"#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not m:
            return ""
        t = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", m.group(1))
        t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
        return re.sub(r"\s+", " ", re.sub(r"[*_`]+", "", t)).strip()
    return ""


PDF_PATH = re.compile(r"^pdf-path:\s*\"?([^\"\n]+?\.pdf)\"?\s*$", re.M | re.I)


def note(text: str, rel: str, bibs: Bibs | None = None) -> str:
    """A note's name: a paper's reading notes by the paper, any other by
    its first heading, else its file's stem. A note marked private
    (`agent: false`) keeps its file's name: nothing of what it says is
    carried into the conversation's log."""
    if text.startswith("---") and re.search(r"^agent:\s*false\s*$", text[:600], re.M):
        return Path(rel).stem
    m = PDF_PATH.search(text[:600]) if text.startswith("---") else None
    if m and bibs is not None:
        return bibs.paper(m.group(1).strip())[0] + " — reading notes"
    return heading(text) or Path(rel).stem
