"""Course documents: the Downloads inbox, filing, and the index the agent
consults (docs/agent.md, slice 4, 2026-10-18).

The inbox is the Downloads folder (and the folders directly in it, such as
an unpacked export), which also holds invoices and an ID certificate. So matching is local and quiet: a PDF belongs to a course when
its file name or its first two pages name the course (its code or its
title), or when it was downloaded during one of the course's classes or in
the two hours after. A PDF that matches nothing is never listed, named,
stored or shown to the agent — the scan's cache keeps only a hash of its
name. A match becomes a proposal ("file it in Human Factors as …?"), and
only the person's accepting moves it.

Filed documents live in the vault at `projects/<tag>/docs/`, outside git
(they can be downloaded again). The agent sees an index of them on a run
about the course: a line each, never their contents (reading one whole and
searching one are the next step).
"""
from __future__ import annotations

import datetime as dt
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

WINDOW_DAYS = 60                         # older downloads are not the semester's
AFTER_CLASS = dt.timedelta(hours=2)
BEFORE_CLASS = dt.timedelta(minutes=15)


def _name_key(p: Path, st: os.stat_result) -> str:
    # The cache never holds a file's name: an invoice stays unnamed.
    return hashlib.sha1(f"{p.name}\0{st.st_mtime_ns}\0{st.st_size}".encode()).hexdigest()


def content_hash(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _words(text: str) -> str:
    return re.sub(r"[\s_.\-]+", " ", text).casefold()


def _names(course: dict) -> list[str]:
    """What names a course: its code, its title (with "&" read as "and"
    too), and its tag as a word of its own ("DTM_week2.pdf")."""
    out = [course.get("code", ""), course["name"]]
    if "&" in course["name"]:
        out.append(course["name"].replace("&", "and"))
    names = [_words(x).strip() for x in out if x and len(x) >= 4]
    if len(course.get("tag", "")) >= 3:
        names.append(course["tag"].casefold())
    return names


def names_course(text: str, course: dict) -> bool:
    t = " " + _words(text) + " "
    return any(re.search(r"(?<![a-z0-9])" + re.escape(n) + r"(?![a-z0-9])", t) for n in _names(course))


def first_pages(p: Path) -> str:
    try:
        r = subprocess.run(["pdftotext", "-l", "2", str(p), "-"], capture_output=True, text=True, timeout=30)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def pdf_info(p: Path) -> dict:
    try:
        r = subprocess.run(["pdfinfo", str(p)], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    out = {}
    for line in r.stdout.splitlines():
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip()
    return out


def title_of(p: Path, info: dict) -> str:
    """The document's own title when it has a sensible one, else its file
    name made readable."""
    t = html.unescape(info.get("Title") or "").strip()
    bad = not (4 <= len(t) <= 120) or re.search(r"\.(docx?|pptx?|pdf|tex)$|^untitled|^microsoft|^slide \d|^\d+$", t, re.I)
    if bad:
        t = p.stem
        t = re.sub(r"[ _]?\(\d+\)$|_\d+$", "", t)
        t = re.sub(r"[_]+", " ", t)
    t = re.sub(r"[\\/:*?\"“”<>|]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()[:120] or p.stem


def class_at(when: dt.datetime, events: list[dict], courses: list[dict], matches) -> tuple[dict, dict] | None:
    """The course whose class the download fell in (or just after);
    `matches(event, code)` is the timetable's own test."""
    for e in events:
        if e["start"] - BEFORE_CLASS <= when <= e["end"] + AFTER_CLASS:
            for c in courses:
                if c.get("code") and matches(e, c["code"]):
                    return c, e
    return None


def inbox_pdfs(inbox: Path) -> list[Path]:
    """The inbox's PDFs: at its top and one folder down (an unpacked
    course export), hidden folders skipped."""
    out = []
    for p in sorted(inbox.iterdir()):
        if p.is_dir() and not p.name.startswith("."):
            out += [q for q in sorted(p.iterdir()) if q.suffix.lower() == ".pdf" and q.is_file()]
        elif p.suffix.lower() == ".pdf" and p.is_file():
            out.append(p)
    return out


def scan(inbox: Path, courses: list[dict], events: list[dict], cache: dict, now: dt.datetime,
         matches=None) -> list[dict]:
    """The inbox's PDFs that belong to a course, each with why. `cache`
    (updated in place) remembers what the first pages said, keyed by a hash
    of name, time and size; a non-match is remembered as nothing."""
    out = []
    if not inbox.is_dir():
        return out
    since = now - dt.timedelta(days=WINDOW_DAYS)
    for p in inbox_pdfs(inbox):
        st = p.stat()
        got = dt.datetime.fromtimestamp(st.st_mtime)
        if got < since:
            continue
        key = _name_key(p, st)
        if key in cache:
            hit = cache[key]
        else:
            hit = None
            for c in courses:
                if names_course(p.stem, c):
                    hit = {"tag": c["tag"], "how": "name"}
                    break
            if hit is None:
                pages = first_pages(p)
                c = next((c for c in courses if names_course(pages, c)), None)
                if c:
                    hit = {"tag": c["tag"], "how": "contents"}
            cache[key] = hit
        why = ""
        course = None
        if hit:
            course = next((c for c in courses if c["tag"] == hit["tag"]), None)
            if course:
                why = (f"its name says {course['name']}" if hit["how"] == "name"
                       else f"its first page names {course['name']}")
        if course is None:
            at = class_at(got, events, courses, matches) if matches else None
            if at:
                course, e = at
                why = f"downloaded during {course['name']} on {e['start']:%a %d %b}" if got <= e["end"] \
                    else f"downloaded just after {course['name']} on {e['start']:%a %d %b}"
        if course is None:
            continue
        out.append({"src": str(p), "tag": course["tag"], "course": course["name"], "why": why,
                    "got": got.isoformat(timespec="minutes")})
    return out


def docs_dir(vault: Path, projects_dir: str, tag: str) -> Path:
    return vault / projects_dir / tag / "docs"


def proposals(found: list[dict], ledger_items: list[dict], vault: Path, projects_dir: str) -> list[dict]:
    """What is new to propose: one per document (by its contents), none for
    one already filed, declined, or waiting."""
    known = {x.get("doc") for x in ledger_items if x.get("kind") == "file"
             and x.get("status") in ("open", "declined", "accepted")}
    out, seen = [], set()
    # Of two copies of one download, the original rather than "… (1)".
    copy = re.compile(r"[ _]?\(\d+\)$|_\d+$")
    for f in sorted(found, key=lambda f: (bool(copy.search(Path(f["src"]).stem)), f["src"])):
        p = Path(f["src"])
        try:
            doc = content_hash(p)
        except OSError:
            continue
        if doc in known or doc in seen:
            continue
        folder = docs_dir(vault, projects_dir, f["tag"])
        if folder.is_dir() and any(content_hash(q) == doc for q in folder.glob("*.pdf")):
            continue
        seen.add(doc)
        info = pdf_info(p)
        name = f"{f['got'][:10]} {title_of(p, info)}.pdf"
        out.append({"kind": "file", "key": "", "doc": doc, "src": f["src"], "name": name,
                    "project": f["tag"], "title": f["course"], "why": f["why"]})
    return out


def file_one(item: dict, vault: Path, projects_dir: str, guard) -> str:
    """Moves the document into its course's folder under the proposed name
    (never over another file). Returns where it went."""
    src = Path(item["src"])
    if not src.is_file():
        raise FileNotFoundError(f"{src.name} is no longer in the inbox")
    folder = docs_dir(vault, projects_dir, item["project"])
    dest = folder / item["name"]
    n = 2
    while dest.exists():
        dest = folder / f"{Path(item['name']).stem} ({n}).pdf"
        n += 1
    guard(dest)
    folder.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dest))
    return str(dest)


def index(vault: Path, projects_dir: str, tag: str, cache: dict | None = None) -> list[dict]:
    """A course's documents: name, pages, date — what the sidebar lists and
    the agent's index line says."""
    folder = docs_dir(vault, projects_dir, tag)
    out = []
    for p in sorted(folder.glob("*.pdf")) if folder.is_dir() else []:
        st = p.stat()
        key = f"{p}\0{st.st_mtime_ns}\0{st.st_size}"
        pages = (cache or {}).get(key)
        if pages is None:
            try:
                pages = int(pdf_info(p).get("Pages") or 0)
            except ValueError:
                pages = 0
            if cache is not None:
                cache[key] = pages
        out.append({"name": p.stem, "file": p.name, "path": str(p), "pages": pages})
    return out


def load_cache(path: Path) -> dict:
    try:
        d = json.loads(path.read_text())
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_cache(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False))
    os.replace(tmp, path)


# ------------------------------------------------------------------ reading
#
# Tiers 2 and 3 (2026-10-18): the agent asks, in its reply, for a document
# of the index whole or for words in it; local code reads the PDF here —
# converted once, kept in the state folder, never in the vault — and
# carries what it found into the agent's next run. Plain text and keyword
# search: no embeddings, and an answer can say which page it came from.

WHOLE_MAX = 60_000          # characters a document may carry whole
PASSAGES = 8                # passages a search carries
PASSAGE_CHARS = 700
MAX_READS = 3               # requests honoured per run


def pages(pdf: Path, cache_dir: Path) -> list[str]:
    """The document's text, page by page (pdftotext's form feeds), converted
    once and kept by its contents' hash."""
    doc = content_hash(pdf)
    cached = cache_dir / f"{doc}.json"
    try:
        return json.loads(cached.read_text())["pages"]
    except (OSError, ValueError, KeyError):
        pass
    try:
        r = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], capture_output=True, text=True, timeout=120)
        text = r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        text = ""
    out = [re.sub(r"[ \t]+\n", "\n", p).strip() for p in text.split("\f")]
    while out and not out[-1]:
        out.pop()
    cache_dir.mkdir(parents=True, exist_ok=True)
    tmp = cached.with_name(cached.name + ".tmp")
    tmp.write_text(json.dumps({"name": pdf.name, "pages": out}, ensure_ascii=False))
    os.replace(tmp, cached)
    return out


def whole(pgs: list[str]) -> tuple[str, bool]:
    """The pages with their numbers, as far as WHOLE_MAX allows; False when
    the document did not fit."""
    out, size = [], 0
    for n, p in enumerate(pgs, 1):
        chunk = f"[p. {n}]\n{p}\n"
        if size + len(chunk) > WHOLE_MAX:
            return "\n".join(out), False
        out.append(chunk)
        size += len(chunk)
    return "\n".join(out), True


def search(pgs: list[str], words: str) -> list[tuple[int, str]]:
    """The passages (paragraphs) that hold the most of the words asked for,
    best first, each with its page."""
    # A plural finds its singular too ("myths" → "myth"); nothing cleverer.
    terms = [t[:-1] if len(t) > 4 and t.endswith("s") else t
             for t in re.findall(r"\w[\w'-]*", words.casefold()) if len(t) > 2]
    if not terms:
        return []
    found = []
    for n, p in enumerate(pgs, 1):
        for para in re.split(r"\n\s*\n", p):
            low = para.casefold()
            hits = sum(1 for t in set(terms) if t in low)
            if hits:
                found.append((hits, sum(low.count(t) for t in terms), n, re.sub(r"\s+", " ", para).strip()))
    found.sort(key=lambda x: (-x[0], -x[1], x[2]))
    return [(n, para[:PASSAGE_CHARS] + ("…" if len(para) > PASSAGE_CHARS else "")) for _, _, n, para in found[:PASSAGES]]


def fulfil(requests: list[dict], docs: list[dict], cache_dir: Path) -> tuple[list[str], list[dict]]:
    """What the agent asked for, from the documents it was shown (and no
    others), as payload sections; and a record of each request."""
    by = {d["name"].casefold(): d for d in docs}
    parts, done = [], []
    for r in requests[:MAX_READS]:
        name = str(r.get("document") or "").strip()
        name = re.sub(r"\.pdf$", "", name, flags=re.I)
        d = by.get(name.casefold())
        words = str(r.get("words") or "").strip()[:200]
        if d is None:
            done.append({"document": name, "words": words, "found": False})
            parts += [f"## {name}", "", "(not one of the documents in the index — nothing was read)", ""]
            continue
        # A document that brings its own pages (Longhand's manual), or a PDF.
        pgs = d["text"] if "text" in d else pages(Path(d["path"]), cache_dir)
        if not any(pgs):
            done.append({"document": d["name"], "words": words, "found": False})
            parts += [f"## {d['name']}", "", "(this PDF has no text layer — it is scanned; nothing could be read)", ""]
            continue
        if words:
            hits = search(pgs, words)
            done.append({"document": d["name"], "words": words, "found": bool(hits), "pages": sorted({n for n, _ in hits})})
            parts += [f"## {d['name']} — passages with “{words}” ({len(pgs)} pages)", ""]
            parts += [f"- p. {n}: {t}" for n, t in hits] or ["(none of those words is in it)"]
            parts.append("")
        else:
            text, complete = whole(pgs)
            done.append({"document": d["name"], "words": "", "found": True, "whole": complete})
            head = f"## {d['name']} — whole ({len(pgs)} pages)" if complete else \
                f"## {d['name']} — the beginning only ({len(pgs)} pages, too long to carry whole: ask for words in it)"
            parts += [head, "", text, ""]
    return parts, done
