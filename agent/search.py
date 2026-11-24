"""Searching the vault for the day's conversation (docs/agent.md, "The day
conversation", slice 2, 2026-10-21).

The agent asks — words to search for, or a file to read whole — and local
code answers, from the folders the student switched on in Settings and
never from what must not be shared. Four layers, applied here before
anything reaches the model:

1. **By place:** a note marked private (`agent: false`) and every
   `[!private]` block; a daily note from before the agent's horizon
   (docs/files.md, 2026-10-26); anything under `_Secrets`; folders
   switched off.
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
NAMES = doclib.NAMES          # the inbox's rule (documents.py `personal`), by name
IBAN = doclib.IBAN
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


def files(vault: Path, on: dict[str, bool], withheld: dict, hide=None) -> list[Path]:
    """`hide(rel)` is true for a file kept back by a rule of the runner's
    (a day before the horizon); counted as `horizon`."""
    out = []
    for folder, yes in on.items():
        if not yes:
            continue
        for p in sorted((vault / folder).rglob("*")):
            if not p.is_file():
                continue
            why = _never(p.relative_to(vault).as_posix())
            if why:
                if why != "type" or p.suffix.lower() in (".docx", ".pptx", ".xlsx", ".odt", ".json", ".env", ".pem", ".key"):
                    withheld[why] = withheld.get(why, 0) + 1
                continue
            if hide and hide(p.relative_to(vault).as_posix()):
                withheld["horizon"] = withheld.get("horizon", 0) + 1
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
    # The report on gitleaks' own stdout, which it names "-". It was asked
    # for at "/dev/stdout", a file gitleaks has to open; where it cannot (a
    # container, a service whose stdout is a socket) it found the secret,
    # ended with 1 and wrote nothing, which read as "nothing found": the
    # passage was sent whole (2026-11-24, the suite's first run on GitHub).
    # A run that ends badly and reports nothing has checked nothing.
    try:
        r = subprocess.run(["gitleaks", "stdin", "--no-banner", "--redact", "--report-format", "json",
                            "--report-path", "-"], input="\n".join(lines), capture_output=True, text=True, timeout=30)
        if r.returncode != 0 and not r.stdout.strip():
            return set(range(len(texts)))           # unchecked: share nothing
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


def search(vault: Path, on: dict[str, bool], words: str, cache: Path, folder: str = "", hide=None) -> dict:
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
    for p in files(vault, scope, withheld, hide):
        rel = p.relative_to(vault).as_posix()
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


def read(vault: Path, on: dict[str, bool], rel: str, cache: Path, hide=None, limit: int = 0) -> dict:
    """A file whole, under the same rules: its visible paragraphs with
    their lines (or its pages), up to WHOLE_MAX characters."""
    rel = rel.strip().lstrip("/")
    p = (vault / rel).resolve()
    if vault.resolve() not in p.parents or not p.is_file():
        return {"error": "not a file in the vault"}
    rel = p.relative_to(vault.resolve()).as_posix()
    if _never(rel):
        return {"error": "never shared"}
    if not any(y and (rel == f or rel.startswith(f + "/")) for f, y in on.items()):
        return {"error": "in a folder that is switched off"}
    if hide and hide(rel):
        return {"error": "a day before the agent's horizon"}
    withheld: dict = {}
    paras = paragraphs(p, cache, {"until": time.monotonic() + 30}, withheld)
    if not paras:
        return {"error": "private" if withheld.get("private") else "no text in it"}
    chunks = [f"[{where}]\n{mask(text.strip())}" for where, text in paras]
    bad = leaks(chunks)
    chunks = ["[withheld: looked like a secret]" if i in bad else c for i, c in enumerate(chunks)]
    text, complete = "", True
    for c in chunks:
        if len(text) + len(c) > (limit or WHOLE_MAX):
            complete = False
            break
        text += c + "\n\n"
    return {"path": rel, "text": text.rstrip(), "complete": complete, "withheld": {"secret": len(bad)} if bad else {}}


def say_withheld(w: dict) -> str:
    names = {"private": "private notes", "name": "files by name", "type": "files by type", "place": "files by place",
             "secret": "passages that looked like secrets", "unread_pdfs": "PDFs not read yet",
             "horizon": "days before the horizon"}
    return ", ".join(f"{n} {names.get(k, k)}" for k, n in sorted(w.items()) if n)


def find_mine(vault: Path, words: str, daily_dir: str = "", agent_dir: str = "agents/longhand", limit: int = 12) -> list[dict]:
    """Full-text search across the student's own vault notes — local only,
    never sent to a model, so private notes, private callouts and days before
    the horizon are all included. Skips dot-folders and the agent's own dir."""
    want = [t for t in re.findall(r"\S+", words.casefold()) if t]
    if not want:
        return []
    phrase = " ".join(want)
    daily_norm = daily_dir.strip("/")
    agent_norm = agent_dir.strip("/")
    found = []
    for root_dir, dirnames, filenames in os.walk(vault):
        rel_dir = Path(root_dir).relative_to(vault)
        rel_dir_s = "" if rel_dir == Path(".") else rel_dir.as_posix()
        dirnames[:] = sorted(
            d for d in dirnames
            if not d.startswith(".")
            and d not in {".obsidian", ".git", ".stversions", ".stfolder", ".trash"}
            and (not agent_norm or (f"{rel_dir_s}/{d}".strip("/") != agent_norm))
        )
        for name in sorted(filenames):
            if not name.lower().endswith((".md", ".txt")):
                continue
            p = Path(root_dir) / name
            rel = p.relative_to(vault).as_posix()
            if agent_norm and (rel == agent_norm or rel.startswith(agent_norm + "/")):
                continue
            try:
                text = p.read_text(errors="replace")
            except OSError:
                continue
            lines = text.splitlines()
            heading = ""
            in_fm = bool(lines and lines[0].strip() == "---")
            body_start = 0
            if in_fm:
                for k in range(1, len(lines)):
                    if lines[k].strip() == "---":
                        body_start = k + 1
                        break
            if body_start < len(lines) and re.match(r"^\[\[[^\]\n]*\|agent\]\]\s*$", lines[body_start]):
                body_start += 1
            best_file_hits = 0
            for idx, raw in enumerate(lines, 1):
                if in_fm:
                    if idx > 1 and raw.strip() == "---":
                        in_fm = False
                    continue
                if raw.startswith("#"):
                    heading = re.sub(r"^#+\s*", "", raw).strip()
                low = raw.casefold()
                matched = sum(1 for t in set(want) if t in low)
                if matched < len(set(want)):
                    continue
                exact = 1 if phrase in low else 0
                is_daily = bool(daily_norm and rel.startswith(daily_norm + "/") and "/" not in rel[len(daily_norm) + 1:] and rel.endswith(".md"))
                stamp = rel[len(daily_norm) + 1:-3] if is_daily else ""
                snippet = re.sub(r"\s+", " ", raw).strip()
                if len(snippet) > 160:
                    pos = low.find(want[0])
                    start = max(0, pos - 40)
                    snippet = ("…" if start > 0 else "") + snippet[start:start + 150].strip() + "…"
                found.append((exact, matched, 1 if is_daily else 0, [-ord(c) for c in rel], -idx,
                              {"path": rel, "line": idx, "body_line": max(1, idx - body_start), "date": stamp, "heading": heading, "text": snippet}))
                best_file_hits += 1
                if best_file_hits >= 3:
                    break
    found.sort(key=lambda x: (-x[0], -x[1], -x[2], x[3], -x[4]))
    return [x[5] for x in found[:max(1, limit)]]
