"""Searching the vault for the day's conversation (docs/agent.md, "The day
conversation", slice 2, 2026-10-21).

The agent asks — words to search for, or a file to read whole — and local
code answers, from the folders the student switched on in Settings and
never from what must not be shared. Four layers, applied here before
anything reaches the model:

1. **By place:** a note marked private (`agent: false`) and every
   `[!private]` block; anything under `_Secrets`; folders switched off.
2. **By type:** only `.md`, `.txt`, and `.pdf` with a text layer.
3. **By name**, English and German: identity, money, health, contract and
   secret documents (the inbox's rule, widened).
4. **By content:** every passage and every file is put through gitleaks
   before it is sent; what it flags is withheld. IBAN- and card-shaped
   strings are masked.

What was withheld is counted, never named, so the payload log shows that
the rules work without showing what they kept back. Plain files and
keyword search: an answer can say which file and line it came from.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

import blocks as blocklib
import documents as doclib

# Folders on unless the student switched them off; every other folder is
# off unless switched on. `_Secrets` is never listed at all.
DEFAULT_ON = {"human/Daily", "human/Studies", "projects", "human/Reference", "human/Career", "human/Archive"}
NEVER_DIRS = {"_Secrets", ".obsidian", ".git", ".stversions", ".stfolder", ".trash"}
TYPES = {".md", ".txt", ".pdf"}
NAMES = re.compile(
    r"pass(port)?\b|reisepass|ausweis|\bid[ _-]|identity|meldezettel|meldebest|visa\b|aufenthalt|residence|birth|geburt"
    r"|invoice|rechnung|\bbank|iban|kontoauszug|statement|payslip|lohn|gehalt|salary|steuer|\btax|finanz|kredit|loan"
    r"|receipt|quittung|beleg"
    r"|medical|befund|arzt|doctor|health|gesundheit|insurance|versicherung|e-?card"
    r"|contract|vertrag|\bnda\b|\bdpa\b|agreement|vereinbarung|signed|unterschrieben"
    r"|\.env|secret|password|passwort|token|credential|api[_-]?key|private[_-]?key|id_rsa|\.pem\b|\.key\b",
    re.I)
IBAN = re.compile(r"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b")
CARD = re.compile(r"\b(?:\d[ -]?){13,19}\b")
PASSAGES = 8
PASSAGE_CHARS = 600
WHOLE_MAX = 30_000
PDF_BUDGET = 8.0          # seconds a search may spend reading PDFs not read before


# ------------------------------------------------------------------ places

def folders(vault: Path) -> list[str]:
    """The folders a student can switch on or off: `human/<x>` and every
    other top-level folder, never `_Secrets`."""
    out = []
    for top in sorted(p for p in vault.iterdir() if p.is_dir() and not p.name.startswith(".")):
        if top.name in NEVER_DIRS:
            continue
        if top.name == "human":
            out += [f"human/{p.name}" for p in sorted(top.iterdir())
                    if p.is_dir() and not p.name.startswith(".") and p.name not in NEVER_DIRS]
        else:
            out.append(top.name)
    return out


def switched(vault: Path, settings: dict | None) -> dict[str, bool]:
    """Each folder, on or off: the student's choice in settings.json
    (`searchFolders`), else the default — the daily notes' own folder (the
    config's `daily.dir`) always among those on."""
    chosen = (settings or {}).get("searchFolders") or {}
    daily = str(((settings or {}).get("daily") or {}).get("dir") or "").strip("/")
    on = DEFAULT_ON | ({daily} if daily else set())
    return {f: bool(chosen[f]) if f in chosen else f in on for f in folders(vault)}


def _never(rel: str) -> str:
    """Why a path is never shared, or ""."""
    parts = rel.split("/")
    if any(p in NEVER_DIRS for p in parts):
        return "place"
    if Path(rel).suffix.lower() not in TYPES:
        return "type"
    if NAMES.search(Path(rel).name):
        return "name"
    return ""


def files(vault: Path, on: dict[str, bool], withheld: dict) -> list[Path]:
    out = []
    for folder, yes in on.items():
        if not yes:
            continue
        for p in sorted((vault / folder).rglob("*")):
            if not p.is_file():
                continue
            why = _never(str(p.relative_to(vault)))
            if why:
                if why != "type" or p.suffix.lower() in (".docx", ".pptx", ".xlsx", ".odt", ".json", ".env", ".pem", ".key"):
                    withheld[why] = withheld.get(why, 0) + 1
                continue
            out.append(p)
    return out


# ------------------------------------------------------------------ text

def _md_paragraphs(text: str) -> list[tuple[int, str]] | None:
    """A note's visible paragraphs with their first line (1-based); None
    for a note marked private."""
    blks = blocklib.split(text)
    if blks and blks[0].get("kind") == "frontmatter" and re.search(r"^agent:\s*false\s*$", blks[0]["text"], re.M):
        return None
    out = []
    for b in blks:
        if b.get("private") or b.get("kind") == "frontmatter":
            continue
        out.append((b["start"] + 1, b["text"]))
    return out


def _pdf_pages(p: Path, cache: Path, budget: dict) -> list[str] | None:
    st = p.stat()
    key = hashlib.sha1(f"{p}\0{st.st_mtime_ns}\0{st.st_size}".encode()).hexdigest()
    f = cache / f"{key}.json"
    try:
        return json.loads(f.read_text())["pages"]
    except (OSError, ValueError, KeyError):
        pass
    if time.monotonic() > budget["until"]:
        budget["skipped"] = budget.get("skipped", 0) + 1
        return None
    try:
        r = subprocess.run(["pdftotext", "-layout", str(p), "-"], capture_output=True, text=True, timeout=60)
        pages = [re.sub(r"[ \t]+\n", "\n", x).strip() for x in (r.stdout if r.returncode == 0 else "").split("\f")]
    except (OSError, subprocess.TimeoutExpired):
        pages = []
    while pages and not pages[-1]:
        pages.pop()
    cache.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps({"pages": pages}))
    return pages


def paragraphs(p: Path, cache: Path, budget: dict, withheld: dict) -> list[tuple[str, str]]:
    """(where, text) for each paragraph: "line 14" or "p. 3"."""
    if p.suffix.lower() == ".pdf":
        pages = _pdf_pages(p, cache, budget)
        if not pages or not any(pages):
            return []
        return [(f"p. {n}", para) for n, page in enumerate(pages, 1) for para in re.split(r"\n\s*\n", page) if para.strip()]
    try:
        text = p.read_text(errors="replace")
    except OSError:
        return []
    if p.suffix.lower() == ".txt":
        out, line = [], 1
        for para in re.split(r"(\n\s*\n)", text):
            if para.strip() and not re.fullmatch(r"\n\s*\n", para):
                out.append((f"line {line}", para))
            line += para.count("\n")
        return out
    paras = _md_paragraphs(text)
    if paras is None:
        withheld["private"] = withheld.get("private", 0) + 1
        return []
    return [(f"line {n}", t) for n, t in paras]


def mask(text: str) -> str:
    text = IBAN.sub("[IBAN masked]", text)
    return CARD.sub(lambda m: "[number masked]" if len(re.sub(r"\D", "", m.group(0))) >= 13 else m.group(0), text)


def leaks(texts: list[str]) -> set[int]:
    """Which of the texts gitleaks flags (their indices). Each text is one
    or more lines; they are sent together, one gitleaks run."""
    if not texts:
        return set()
    lines, owner = [], []
    for i, t in enumerate(texts):
        for l in t.split("\n"):
            lines.append(l)
            owner.append(i)
    try:
        r = subprocess.run(["gitleaks", "stdin", "--no-banner", "--redact", "--report-format", "json",
                            "--report-path", "/dev/stdout"], input="\n".join(lines), capture_output=True, text=True, timeout=30)
        found = json.loads(r.stdout or "[]")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return set(range(len(texts)))               # cannot check: share nothing
    return {owner[x["StartLine"] - 1] for x in found if 0 < x.get("StartLine", 0) <= len(owner)}


# ------------------------------------------------------------------ search

def terms(words: str) -> list[str]:
    out = []
    for t in re.findall(r"\w[\w'-]*", words.casefold()):
        if len(t) > 2:
            out.append(t[:-1] if len(t) > 4 and t.endswith("s") else t)
    return out


def search(vault: Path, on: dict[str, bool], words: str, cache: Path, folder: str = "") -> dict:
    """The passages that hold the most of the words, best first — newest
    note first among equals — each with its file and where in it; and what
    was withheld (counts)."""
    withheld: dict = {}
    want = terms(words)
    if not want:
        return {"hits": [], "withheld": withheld}
    scope = {f: y for f, y in on.items() if not folder or f == folder or f.startswith(folder + "/")}
    budget = {"until": time.monotonic() + PDF_BUDGET}
    found = []
    for p in files(vault, scope, withheld):
        rel = str(p.relative_to(vault))
        for where, para in paragraphs(p, cache, budget, withheld):
            low = para.casefold()
            hits = sum(1 for t in set(want) if t in low)
            if hits:
                found.append((hits, sum(low.count(t) for t in want), rel, where, para))
    found.sort(key=lambda x: (-x[0], -x[1], [-ord(c) for c in x[2]]))
    top = found[:PASSAGES * 2]
    texts = [mask(re.sub(r"\s+\n", "\n", x[4]).strip())[:PASSAGE_CHARS] for x in top]
    bad = leaks(texts)
    if bad:
        withheld["secret"] = withheld.get("secret", 0) + len(bad)
    hits = [{"path": x[2], "where": x[3], "text": t + ("…" if len(x[4]) > PASSAGE_CHARS else "")}
            for i, (x, t) in enumerate(zip(top, texts)) if i not in bad][:PASSAGES]
    if budget.get("skipped"):
        withheld["unread_pdfs"] = budget["skipped"]
    return {"hits": hits, "withheld": withheld}


def read(vault: Path, on: dict[str, bool], rel: str, cache: Path) -> dict:
    """A file whole, under the same rules: its visible paragraphs with
    their lines (or its pages), up to WHOLE_MAX characters."""
    rel = rel.strip().lstrip("/")
    p = (vault / rel).resolve()
    if vault.resolve() not in p.parents or not p.is_file():
        return {"error": "not a file in the vault"}
    rel = str(p.relative_to(vault.resolve()))
    if _never(rel):
        return {"error": "never shared"}
    if not any(y and (rel == f or rel.startswith(f + "/")) for f, y in on.items()):
        return {"error": "in a folder that is switched off"}
    withheld: dict = {}
    paras = paragraphs(p, cache, {"until": time.monotonic() + 30}, withheld)
    if not paras:
        return {"error": "private" if withheld.get("private") else "no text in it"}
    chunks = [f"[{where}]\n{mask(text.strip())}" for where, text in paras]
    bad = leaks(chunks)
    chunks = ["[withheld: looked like a secret]" if i in bad else c for i, c in enumerate(chunks)]
    text, complete = "", True
    for c in chunks:
        if len(text) + len(c) > WHOLE_MAX:
            complete = False
            break
        text += c + "\n\n"
    return {"path": rel, "text": text.rstrip(), "complete": complete, "withheld": {"secret": len(bad)} if bad else {}}


def say_withheld(w: dict) -> str:
    names = {"private": "private notes", "name": "files by name", "type": "files by type", "place": "files by place",
             "secret": "passages that looked like secrets", "unread_pdfs": "PDFs not read yet"}
    return ", ".join(f"{n} {names.get(k, k)}" for k, n in sorted(w.items()) if n)
