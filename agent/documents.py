"""Course documents: the Downloads inbox, filing, and the index the agent
consults (docs/agent.md, slice 4, 2026-10-18).

The inbox is the Downloads folder (and the folders directly in it, such as
an unpacked export), which also holds invoices and an ID certificate. So matching is local and quiet: a PDF belongs to a course when
its file name or its first two pages name the course (its code or its
title), or when it was downloaded during one of the course's classes or in
the two hours after — and never when it is a personal document (`personal`:
identity, money, health, contracts, secrets, by its name or by what its
first pages carry). A PDF that matches nothing is never listed, named,
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
import unicodedata
from pathlib import Path

WINDOW_DAYS = 60                         # older downloads are not the semester's
AFTER_CLASS = dt.timedelta(hours=2)
BEFORE_CLASS = dt.timedelta(minutes=15)

# A personal document is never a course's, whenever it was downloaded
# (2026-11-18: a SEPA direct-debit mandate, downloaded just after a class,
# was proposed for filing in that course). By name, English and German —
# search.py keeps the same documents out of what the agent may read — and
# by what the first pages carry: an IBAN, a mandate's or a creditor's
# reference, an invoice's or a customer's number, a tax or social-security
# number, an identity document's number.
NAMES = re.compile(
    r"pass(port)?\b|reisepass|ausweis|\bid[ _-]|identity|meldezettel|meldebest|visa\b|aufenthalt|residence|birth|geburt"
    r"|invoice|rechnung|\bbank|iban|kontoauszug|statement|payslip|lohn|gehalt|salary|steuer|\btax|finanz|kredit|loan"
    r"|receipt|quittung|beleg|sepa|lastschrift|mandat|[uü]e?berweisung|zahlung|payment|\bbill\b"
    r"|medical|befund|arzt|doctor|health|gesundheit|insurance|versicherung|e-?card"
    r"|contract|vertrag|\bnda\b|\bdpa\b|agreement|vereinbarung|signed|unterschrieben"
    r"|\.env|secret|password|passwort|token|credential|api[_-]?key|private[_-]?key|id_rsa|\.pem\b|\.key\b",
    re.I)
IBAN = re.compile(r"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b")
PERSONAL_TEXT = re.compile(
    r"mandatsreferenz|mandate reference|gl[aä]e?ubiger-?(?:identifikations|id\b)|creditor identifier"
    r"|rechnungsnummer|rechnungs-?nr|invoice (?:no\b|number)|kundennummer|kunden-?nr|customer (?:no\b|number)"
    r"|steuernummer|steuer-?id|steuer-?identifikations|tax (?:id|number)|sozialversicherungsnummer|social security number"
    r"|passport (?:no\b|number)|reisepassnummer|ausweisnummer|personalausweis",
    re.I)


def personal(name: str, text: str = "") -> bool:
    """Whether a document is personal (see NAMES): by its name, or by its
    first pages. An IBAN counts only with the digits one has, so a run of
    capitals on a slide is not taken for one."""
    if NAMES.search(name) or PERSONAL_TEXT.search(text):
        return True
    return any(sum(ch.isdigit() for ch in m.group(0)) >= 10 for m in IBAN.finditer(text))


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


FOLDERID_DOWNLOADS = (0x374DE290, 0x123F, 0x4565, (0x91, 0x64, 0x39, 0xC4, 0x92, 0x5E, 0x46, 0x7B))
FOLDERID_PROFILE = (0x5E6C858F, 0x0E22, 0x4760, (0x9A, 0xFE, 0xEA, 0x33, 0x17, 0xB6, 0x71, 0x73))


def _known_folder(fid: tuple) -> Path | None:
    """A folder as Windows knows it (SHGetKnownFolderPath), wherever the
    person has moved it; None elsewhere or when Windows cannot say."""
    if os.name != "nt":
        return None
    import ctypes

    class GUID(ctypes.Structure):
        _fields_ = [("Data1", ctypes.c_ulong), ("Data2", ctypes.c_ushort), ("Data3", ctypes.c_ushort),
                    ("Data4", ctypes.c_ubyte * 8)]

    guid = GUID(fid[0], fid[1], fid[2], (ctypes.c_ubyte * 8)(*fid[3]))
    got = ctypes.c_wchar_p()
    shell32, ole32 = ctypes.windll.shell32, ctypes.windll.ole32
    shell32.SHGetKnownFolderPath.restype = ctypes.c_long
    shell32.SHGetKnownFolderPath.argtypes = (ctypes.POINTER(GUID), ctypes.c_ulong, ctypes.c_void_p,
                                             ctypes.POINTER(ctypes.c_wchar_p))
    try:
        hr = shell32.SHGetKnownFolderPath(ctypes.byref(guid), 0, None, ctypes.byref(got))
        return Path(got.value) if hr == 0 and got.value else None
    except OSError:
        return None
    finally:
        if got:
            ole32.CoTaskMemFree(got)


def downloads() -> Path:
    """This machine's Downloads folder. On Windows the one Windows knows, which
    a person may have moved (to OneDrive, to another drive: Properties →
    Location), where `~/Downloads` would name an empty or missing folder.
    Only while `~` is the profile Windows knows: a home set elsewhere (a
    test's, a sandbox's) keeps its own Downloads, never the person's."""
    home = Path.home()
    profile = _known_folder(FOLDERID_PROFILE)
    if profile is not None and os.path.normcase(str(profile)) == os.path.normcase(str(home)):
        known = _known_folder(FOLDERID_DOWNLOADS)
        if known is not None:
            return known
    return home / "Downloads"


def folder(path: str) -> Path:
    """A folder named in the config or Settings (`inbox`, `export.dir`), `~`
    expanded. `~/Downloads` means this machine's Downloads (`downloads`):
    the config travels with the vault between machines, and the folder is
    each one's own."""
    raw = str(path).strip()
    norm = raw.replace("\\", "/").rstrip("/")
    if norm == "~/Downloads" or norm.startswith("~/Downloads/"):
        return downloads().joinpath(*[p for p in norm[len("~/Downloads"):].split("/") if p])
    return Path(raw).expanduser()


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
    seen = set()
    for p in inbox_pdfs(inbox):
        st = p.stat()
        got = dt.datetime.fromtimestamp(st.st_mtime)
        if got < since:
            continue
        if personal(p.stem):
            continue                       # by its name: nothing read, nothing kept
        key = _name_key(p, st)
        seen.add(key)
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
        # A match, read for what makes it personal, once (by name it was
        # looked at above): only what would be proposed is read.
        seen.add("p:" + key)
        if "p:" + key not in cache:
            cache["p:" + key] = personal("", first_pages(p))
        if cache["p:" + key]:
            continue
        out.append({"src": str(p), "tag": course["tag"], "course": course["name"], "why": why,
                    "got": got.isoformat(timespec="minutes")})
    for key in [k for k in cache if k not in seen and not k.startswith("paper:")]:
        del cache[key]                     # a file gone, renamed, or past the window
    return out


# A project may name its own documents folder, a vault path on a `Docs:`
# line of its file (2026-11-19: #thesis filed into a new projects/thesis/docs
# while its papers live in projects/thesis_itu/literature/pdf). Set by the
# runner from the project files (`set_folders`); tag -> folder under the vault.
FOLDERS: dict[str, str] = {}
DOCS_LINE = re.compile(r"^\s*-?\s*Docs:\s*`?([^`\n]+?)`?\s*$", re.M)


def set_folders(projects: list[tuple[str, str]], vault: Path) -> None:
    """(tag, project file text) -> FOLDERS: each `Docs:` line that names a
    folder inside the vault."""
    FOLDERS.clear()
    root = vault.resolve()
    for tag, text in projects:
        m = DOCS_LINE.search(text or "")
        if not tag or not m:
            continue
        rel = m.group(1).strip().strip("/")
        f = (root / rel).resolve()
        if rel and root in f.parents:
            FOLDERS[tag] = f.relative_to(root).as_posix()


def docs_dir(vault: Path, projects_dir: str, tag: str) -> Path:
    if tag in FOLDERS:
        return vault / FOLDERS[tag]
    return vault / projects_dir / tag / "docs"


def in_vault(src: Path, vault: Path) -> Path | None:
    """A PDF in the vault with the same bytes as `src`, wherever it is
    (2026-11-19: four papers filed for #thesis were already in its
    literature folder, and the check looked only in the course's own).
    By size first, so only a file of the same size is read."""
    try:
        size = src.stat().st_size
    except OSError:
        return None
    doc = None
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            if not f.lower().endswith(".pdf"):
                continue
            q = Path(root) / f
            try:
                if q.stat().st_size != size or q.resolve() == src.resolve():
                    continue
                doc = doc or content_hash(src)
                if content_hash(q) == doc:
                    return q
            except OSError:
                continue
    return None


# A paper's name: "Moser 2026 Identifying environmental stress factors….pdf"
# (2026-11-19, the student: the author in front, the date of the download
# not the most important thing). Read on this machine from the PDF's own
# fields and its first page; a document whose author is not found keeps
# the dated name a course handout has.
PAPER = re.compile(r"\bdoi\b|doi\.org/|\b10\.\d{4,9}/|arxiv|\bissn\b|\babstract\b|\bet al\.", re.I)
# What makes a download a paper the agent may be shown: a DOI or an arXiv id
# on its first page (a handout's reference list, on its second, is not).
PAPER_ID = re.compile(r"\bdoi\b|doi\.org/|\b10\.\d{4,9}/\S|arxiv", re.I)


def page_one(text: str) -> str:
    return text.split("\f", 1)[0]
NOT_NAMES = re.compile(
    r"\b(univ|universit|institut|department|faculty|school|cent(er|re)|journal|article|research|access|open|"
    r"report|brief|special|issue|international|science|review|paper|abstract|vol|data|sensor|analysis|"
    r"health|psychology|urban|informatics|planning|transport|homepage|proceedings|conference|chapter|"
    r"introduction|keywords|online|press|elsevier|springer|wiley|ieee|mdpi|corresponding|author|thesis|topic|"
    r"proposal|master|project|information|summary|method|survey|description|course|lecture|seminar|board)",
    re.I)
NAME_WORD = re.compile(r"(?:[A-ZÀ-Þ][\wÀ-ÿ'’-]*\.?|[A-ZÀ-Þ]\.)$")
TITLE_MAX = 90


def _piece_is_name(piece: str) -> bool:
    words = piece.split()
    return 2 <= len(words) <= 5 and all(NAME_WORD.match(w) for w in words) \
        and not NOT_NAMES.search(piece) and any(len(w.rstrip(".")) >= 2 for w in words)


def _pieces(line: str) -> list[str]:
    """A line read as a list of people: superscripts, marks and affiliation
    letters gone, parted at commas, "and", "&", "und"."""
    # An ORCID mark or another drawn sign is no part of a name.
    t = "".join(ch for ch in line if not (unicodedata.category(ch)[0] == "C" or unicodedata.category(ch) == "So"))
    t = re.sub(r"\([^)]{0,3}\)", " ", t)                        # Ye(&): Springer's mark for the contact
    t = re.sub(r"(?<=[^\W\d_])\d+(,\d+)*", "", t)             # Zeile1 → Zeile, Resch2,3 → Resch
    t = re.sub(r"(?<!\w)(?:[a-z](?:,[a-z])*,?\*?|\d+(?:,\d+)*|[*†‡§])(?!\w)", " ", t)
    return [p.strip(" .") for p in re.split(r",|\band\b|&|\bund\b", t) if p.strip(" .")]


def _surname(piece: str) -> str:
    w = piece.split()[-1].rstrip(".")
    if w.isupper() and len(w) <= 3:
        return ""                          # "AI", "IT": an acronym, not a name
    return w.capitalize() if w.isupper() else w


def page_people(text: str) -> tuple[str, int]:
    """The first author's surname on a first page, and the line it was
    found on (-1 when it came from a running header): "Moser et al." in the
    first lines, else the first line that lists two people, else two lines
    of one person each."""
    lines = [l.strip() for l in text.splitlines() if l.strip()][:30]
    for l in lines[:5]:
        m = re.match(r"([A-ZÀ-Þ][\wÀ-ÿ'’-]+) et al\.", l)
        if m and not NOT_NAMES.search(m.group(1)):
            return m.group(1), -1
    for i, l in enumerate(lines):
        ps = _pieces(l)
        if len(ps) >= 2 and _piece_is_name(ps[0]) and _piece_is_name(ps[1]) and _surname(ps[0]):
            return _surname(ps[0]), i
    for i, l in enumerate(lines[:-1]):
        a, b = _pieces(l), _pieces(lines[i + 1])
        if len(a) == 1 and len(b) >= 1 and _piece_is_name(a[0]) and _piece_is_name(b[0]) and _surname(a[0]):
            return _surname(a[0]), i
    return "", -1


def meta_author(info: dict, text: str) -> str:
    """The first author from the PDF's own Author field, kept only when the
    first page names them too (a typesetter's name is not an author)."""
    first = re.split(r";|,|\band\b|&", html.unescape(info.get("Author") or ""))[0].strip()
    if not _piece_is_name(first):
        return ""
    sur = _surname(first)
    return sur if re.search(r"(?<!\w)" + re.escape(sur) + r"(?![^\W\d_])", text, re.I) else ""


def paper_year(info: dict, text: str, today: dt.date | None = None) -> str:
    """The year in the first page's header (the journal line: "2011, Vol.",
    "(2026) 5:6", "1 OCTOBER 2023"), else the year the PDF was made."""
    top = (today or dt.date.today()).year + 1
    for l in [l for l in text.splitlines() if l.strip()][:12]:
        for m in re.finditer(r"(?<![\d/.-])(19[5-9]\d|20\d\d)(?![\d/-])", l):
            if int(m.group(1)) <= top:
                return m.group(1)
    m = re.search(r"\b(19[5-9]\d|20\d\d)\b", info.get("CreationDate") or "")
    return m.group(1) if m else ""


def stem_year(stem: str, today: dt.date | None = None) -> str:
    """A year the download's own name gives ("CORP2021_72")."""
    top = (today or dt.date.today()).year + 1
    m = re.search(r"(?<!\d)(19[5-9]\d|20\d\d)(?!\d)", stem)
    return m.group(1) if m and int(m.group(1)) <= top else ""


def page_title(text: str, at: int) -> str:
    """The lines just above the author line, read as the title: up to five,
    stopping at a header line (numbers, a link, an address) or a short one."""
    lines = [l.strip() for l in text.splitlines() if l.strip()][:40]
    got = []
    for l in reversed(lines[:at] if at > 0 else []):
        if len(got) >= 5 or re.search(r"\d|@|https?:|www\.|©", l) or (got and len(l.split()) < 3):
            break
        got.insert(0, l)
    return " ".join(got)


def _short(title: str) -> str:
    t = re.sub(r"[\\/:*?\"“”<>|]+", " ", title)
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) <= TITLE_MAX:
        return t
    return t[:TITLE_MAX].rsplit(" ", 1)[0].rstrip(" ,;–-") + "…"


def paper_name(p: Path, info: dict, text: str) -> str:
    """"Surname Year Title.pdf" for a paper whose first author can be read;
    "" for anything else. From its first page only."""
    text = page_one(text)
    if not PAPER.search(text):
        return ""
    sur, at = page_people(text)
    sur = meta_author(info, text) or sur
    if not sur:
        return ""
    t = html.unescape(info.get("Title") or "").strip()
    if not (4 <= len(t) <= 300) or re.search(r"\.(docx?|pptx?|pdf|tex)$|^untitled|^microsoft|^\d+$|^pii\b", t, re.I) \
            or sum(c.isdigit() for c in t) > sum(c.isalpha() for c in t):
        t = page_title(text, at) or title_of(p, {})
    year = paper_year(info, text) or stem_year(p.stem)
    return f"{sur} {year} {_short(t)}.pdf" if year else f"{sur} {_short(t)}.pdf"


def file_name(p: Path, got: dt.datetime, info: dict | None = None, text: str | None = None) -> str:
    """The name a document is filed under: a paper's by its author and
    year, anything else by the day it was downloaded and its title."""
    info = pdf_info(p) if info is None else info
    text = first_pages(p) if text is None else text
    return paper_name(p, info, text) or f"{got:%Y-%m-%d} {title_of(p, info)}.pdf"


def papers(inbox: Path, cache: dict, now: dt.datetime, vault: Path) -> list[dict]:
    """The PDFs in the inbox that read as papers (a DOI, an arXiv id, an
    ISSN or an abstract on the first page), downloaded in the last
    WINDOW_DAYS, never a personal one, and not already in the vault
    (2026-11-19, the student's call: the agent could not see the five
    papers they had just downloaded). Each with the name it would be filed
    under. The cache keeps only whether a file is one, by a hash of its
    name, as `scan`'s does."""
    out = []
    if not inbox.is_dir():
        return out
    since = now - dt.timedelta(days=WINDOW_DAYS)
    seen = set()
    for p in inbox_pdfs(inbox):
        try:
            st = p.stat()
        except OSError:
            continue
        got = dt.datetime.fromtimestamp(st.st_mtime)
        if got < since or personal(p.stem):
            continue
        key = "paper:" + _name_key(p, st)
        seen.add(key)
        if key not in cache:
            text = first_pages(p)
            # A paper's name is kept, to say it again cheaply; anything else
            # only as "not one".
            ok = bool(PAPER_ID.search(page_one(text))) and not personal("", text)
            cache[key] = {"name": file_name(p, got, text=text), "size": st.st_size} if ok else False
        hit = cache[key]
        if not hit or in_vault(p, vault):
            continue
        # Two copies of one download ("… (1)"): the first, once.
        try:
            doc = content_hash(p) if any(x["size"] == st.st_size for x in out) else ""
        except OSError:
            continue
        if doc and any(x["size"] == st.st_size and x["doc"] == doc for x in out):
            continue
        out.append({"document": p.stem, "name": hit["name"], "got": got.isoformat(timespec="minutes"),
                    "size": st.st_size, "doc": doc or content_hash(p)})
    for key in [k for k in cache if k.startswith("paper:") and k not in seen]:
        del cache[key]
    return [{k: x[k] for k in ("document", "name", "got")} for x in out]


def proposals(found: list[dict], ledger_items: list[dict], vault: Path, projects_dir: str,
              skip: set[str] = frozenset()) -> list[dict]:
    """What is new to propose: one per document (by its contents), none for
    one already filed, declined, waiting, left unanswered until it
    expired, or filed and put back (undone), nor for one of the person's
    own exports (`skip`, their contents' hashes).""" 
    known = {x.get("doc") for x in ledger_items if x.get("kind") == "file"
             and x.get("status") in ("open", "declined", "accepted", "expired", "undone")}
    out, seen = [], set()
    # Of two copies of one download, the original rather than "… (1)".
    copy = re.compile(r"[ _]?\(\d+\)$|_\d+$")
    for f in sorted(found, key=lambda f: (bool(copy.search(Path(f["src"]).stem)), f["src"])):
        p = Path(f["src"])
        try:
            doc = content_hash(p)
        except OSError:
            continue
        if doc in known or doc in seen or doc in skip:
            continue
        if in_vault(p, vault):
            continue                       # already kept somewhere in the vault, under any name
        seen.add(doc)
        name = file_name(p, dt.datetime.fromisoformat(f["got"]))
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
        # Forward slashes: the page finds the vault in the path by its
        # config's spelling, and builds file:// links from it (on Windows,
        # str() would give backslashes; on Linux the two are the same).
        out.append({"name": p.stem, "file": p.name, "path": p.as_posix(), "pages": pages})
    return out


def load_cache(path: Path) -> dict:
    try:
        d = json.loads(path.read_text())
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_cache(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    _replace_with(path, json.dumps(data, ensure_ascii=False))


def _replace_with(path: Path, text: str) -> None:
    """`path` holds `text`, written whole beside it and renamed over it.
    The copy is this process's own: `projects` and `proposals` (and the
    page's other listings) run side by side and each saves the caches; with
    one shared `.tmp` the second rename found it gone and that listing
    failed (2026-11-25, lifespan.py's clock the same)."""
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(text)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


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
    _replace_with(cached, json.dumps({"name": pdf.name, "pages": out}, ensure_ascii=False))
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
