"""A note's blocks as a PDF to hand in (2026-11-04, the first diary).

The person picks the blocks; nothing here writes words of its own. A
section is chosen by a line in it — from its upmost heading down to the
next heading as high — and each block starts in or out: Longhand's agent
link, checkboxes and private blocks out, everything else in. What is kept
loses the layer's marks (tags, task dates, block ids, wikilink brackets)
and keeps its words. Two looks: minimal (a white page, black headings)
and omarchy (the current theme's colours, read when it is made). pandoc
and xelatex make the PDF, only when asked; nothing stays resident.
"""
from __future__ import annotations

import datetime as dt
import json
import re
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path

import blocks as blocklib

LOOKS = ("minimal", "omarchy")
FONTS = ("iA Writer Quattro S", "iA Writer Duo S")      # the page's own, in its order
COLORS = Path.home() / ".local" / "state" / "omarchy" / "current" / "theme" / "colors.toml"

LINK_LINE = re.compile(r"^\[\[[^\]\n]*\|agent\]\]$")
BOX = re.compile(r"^\s*[-*+] \[.\]")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
TAG = re.compile(r"(?<![\w&/#])#[A-Za-z][\w/-]*")
TASK_DATE = re.compile(r"\s*[📅⏳✅➕🛫❌]️?\s*\d{4}-\d{2}-\d{2}(?:[ T]\d{1,2}:\d{2})?")
PRIORITY = re.compile(r"\s*[⏫🔼🔽⏬🔺]️?")
BLOCK_ID = re.compile(r"\s+\^[A-Za-z0-9-]+\s*$")
EMBED = re.compile(r"!\[\[([^\]|#\n]+)(?:#[^\]|\n]*)?(?:\|([^\]\n]*))?\]\]")
WIKILINK = re.compile(r"\[\[([^\]|#\n]*)(?:#([^\]|\n]*))?(?:\|([^\]\n]*))?\]\]")
CALLOUT = re.compile(r"^(>\s*)\[![\w-]+\][+-]?\s*(.*)$")
WORD = re.compile(r"[^\W_][\w’'.-]*")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf")


def level(block: dict) -> int:
    m = HEADING.match(block["text"]) if block["kind"] == "heading" else None
    return len(m.group(1)) if m else 0


def section(bl: list[dict], line: int | None) -> tuple[int, int, int | None]:
    """(first, end, title) as indices into `bl`, end exclusive: the section
    `line` is in, from its upmost heading to the next heading as high.
    `title` is that heading's index, or None. No line, or no heading above
    it: the whole note, titled by its first heading."""
    heads = [i for i, b in enumerate(bl) if level(b)]
    if line is None or not heads:
        return 0, len(bl), heads[0] if heads else None
    above = [i for i in heads if bl[i]["start"] <= line]
    if not above:
        return 0, len(bl), heads[0]
    top = min(level(bl[i]) for i in above)
    first = max(i for i in above if level(bl[i]) == top)
    end = next((i for i in heads if i > first and level(bl[i]) <= top), len(bl))
    return first, end, first


def starts_in(block: dict) -> tuple[bool, str]:
    """Whether a block is ticked when the sheet opens, and why not."""
    if block["kind"] == "frontmatter":
        return False, "the note's properties"
    if LINK_LINE.match(block["text"].strip()):
        return False, "Longhand's link to the agent"
    if block["private"]:
        return False, "private"
    if block["kind"] == "item" and BOX.match(block["text"]):
        return False, "a checkbox"
    return True, ""


def clean_line(line: str) -> str:
    """One line without the layer's marks: tags, task dates and
    priorities, block ids, wikilink brackets (the words stay)."""
    line = TASK_DATE.sub("", line)
    line = PRIORITY.sub("", line)
    line = BLOCK_ID.sub("", line)
    line = WIKILINK.sub(lambda m: m.group(3) or (Path(m.group(1)).stem if m.group(1) else m.group(2) or ""), line)
    line = TAG.sub("", line)
    return re.sub(r"[ \t]+$", "", re.sub(r"(?<=\S)[ \t]{2,}", " ", line))


def title_of(text: str) -> str:
    m = HEADING.match(text.splitlines()[0]) if text else None
    words = clean_line(m.group(2) if m else text.splitlines()[0] if text else "")
    return re.sub(r"\s+", " ", words).strip()


def clean(block: dict, shift: int, image) -> str:
    """A kept block as pandoc reads it: marks gone, a heading moved up by
    `shift` levels (a section titled by a ## heading keeps its ### as ##),
    a callout's [!kind] said as its title, an embedded picture by its
    path (`image(name)`, or dropped when it is not found)."""
    out = []
    for line in block["text"].split("\n"):
        line = EMBED.sub(lambda m: embed(m, image), line)
        m = HEADING.match(line) if block["kind"] == "heading" else None
        if m:
            n = max(1, len(m.group(1)) - shift)
            line = "#" * n + " " + clean_line(m.group(2))
        else:
            c = CALLOUT.match(line)
            if c:
                line = (c.group(1) + "**" + clean_line(c.group(2)) + "**") if c.group(2).strip() else None
            else:
                line = clean_line(line)
        if line is not None:
            out.append(line)
    return "\n".join(out).strip("\n")


def embed(m: re.Match, image) -> str:
    name = m.group(1).strip()
    if not name.lower().endswith(IMAGE_EXT):
        return ""                                     # an embedded note: not drawn in slice 1
    path = image(name)
    return f"![](<{path}>)" if path else ""


def assemble(kept: list[dict], shift: int, image) -> str:
    """The body: kept blocks in the note's order. List items that were
    next to each other stay one list; anything else is a paragraph apart."""
    out, prev = [], None
    for b in kept:
        text = clean(b, shift, image)
        if not text.strip():
            prev = None
            continue
        tight = prev is not None and prev["kind"] == "item" and b["kind"] == "item" and prev["end"] == b["start"]
        out.append(("\n" if tight else "\n\n") if out else "")
        out.append(text)
        prev = b
    return "".join(out) + "\n"


def words(body: str) -> int:
    """The words of the prose, headings left out (a 300-word entry counts
    what is written under them)."""
    return sum(len(WORD.findall(l)) for l in body.splitlines() if not HEADING.match(l))


def course_of(bl: list[dict], first: int, end: int, title: int | None, projects: list[dict]) -> str:
    """The project's name for the section: the title's tag, else the tag
    its blocks use most."""
    names = {p["tag"]: p["name"] for p in projects if p.get("tag")}
    if title is not None:
        for t in TAG.findall(bl[title]["text"]):
            if t[1:] in names:
                return names[t[1:]]
    counts: dict[str, int] = {}
    for b in bl[first:end]:
        for t in TAG.findall(b["text"]):
            if t[1:] in names:
                counts[t[1:]] = counts.get(t[1:], 0) + 1
    return names[max(counts, key=counts.get)] if counts else ""


def finder(note: Path, vault: Path, notes: Path):
    """Obsidian's rule for `![[name]]`, as the page draws pictures: beside
    the note, then the vault's attachment folder, then anywhere under the
    notes (shortest path first)."""
    cache: dict[str, Path | None] = {}
    try:
        attach = json.loads((vault / ".obsidian" / "app.json").read_text()).get("attachmentFolderPath", "")
    except (OSError, ValueError):
        attach = ""

    def find(name: str) -> Path | None:
        if name in cache:
            return cache[name]
        hit = None
        for p in (note.parent / name, vault / attach / name if attach else None, vault / name):
            if p and p.is_file():
                hit = p
                break
        if hit is None and notes.is_dir():
            base = Path(name).name.lower()
            hits = sorted((p for p in notes.rglob("*") if p.name.lower() == base and p.is_file()),
                          key=lambda p: len(str(p)))
            hit = hits[0] if hits else None
        cache[name] = hit
        return hit
    return find


def theme_colors(path: Path = COLORS) -> dict:
    try:
        raw = tomllib.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return {k: v.lstrip("#") for k, v in raw.items() if isinstance(v, str) and re.fullmatch(r"#?[0-9A-Fa-f]{6}", v)}


def look_tex(look: str, colors: dict) -> str:
    """The LaTeX each look adds. Both left-align: the page's faces are
    near-monospaced, and justifying them opens holes between words."""
    tex = [r"\raggedright", r"\usepackage{xcolor}"]
    if look == "omarchy" and colors.get("background") and colors.get("foreground"):
        bg, fg = colors["background"], colors["foreground"]
        ac = colors.get("accent", fg)
        dim = colors.get("light_foreground", colors.get("muted", fg))
        link = colors.get("blue", ac)
        tex += [rf"\definecolor{{lhbg}}{{HTML}}{{{bg}}}", rf"\definecolor{{lhfg}}{{HTML}}{{{fg}}}",
                rf"\definecolor{{lhac}}{{HTML}}{{{ac}}}", rf"\definecolor{{lhdim}}{{HTML}}{{{dim}}}",
                rf"\definecolor{{lhlink}}{{HTML}}{{{link}}}",
                r"\pagecolor{lhbg}\color{lhfg}",
                r"\usepackage{sectsty}\allsectionsfont{\color{lhac}}",
                r"\usepackage{etoolbox}\AtBeginEnvironment{quote}{\color{lhdim}}",
                r"\AtBeginDocument{\hypersetup{colorlinks=true,urlcolor=lhlink,linkcolor=lhlink}}"]
    else:
        tex += [r"\AtBeginDocument{\hypersetup{colorlinks=true,urlcolor=black,linkcolor=black}}"]
    return "\n".join(tex) + "\n"


def font(wanted: str = "") -> str:
    """The face to set it in: the one asked for, else the page's, when
    installed; "" leaves pandoc's own."""
    try:
        have = set(subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True,
                                  timeout=10).stdout.replace(",", "\n").splitlines())
    except (OSError, subprocess.SubprocessError):
        have = set()
    for f in ((wanted,) if wanted else ()) + FONTS:
        if f in have:
            return f
    return ""


def file_name(title: str) -> str:
    name = re.sub(r"[/\\:*?\"<>|\x00-\x1f]+", " ", title).strip(" .")
    return (re.sub(r"\s+", " ", name)[:120] or "Export") + ".pdf"


def place(folder: Path, title: str, ours: set[str]) -> Path:
    """Where the PDF goes: its title's name, replaced when an earlier export
    made it, never over a file it did not make ("… (2)" instead)."""
    base = folder / file_name(title)
    p, n = base, 1
    while p.exists() and str(p) not in ours:
        n += 1
        p = base.with_name(f"{base.stem} ({n}).pdf")
    return p


def render(body: str, meta: dict, look: str, colors: dict, face: str, out: Path, beside: Path) -> None:
    """pandoc → xelatex in a throwaway folder; the PDF moved into place
    whole, so the Downloads scan never sees half of one."""
    if not shutil.which("pandoc"):
        raise RuntimeError("pandoc is not installed")
    if not shutil.which("xelatex"):
        raise RuntimeError("xelatex is not installed (texlive)")
    with tempfile.TemporaryDirectory(prefix="longhand-export-") as tmp:
        t = Path(tmp)
        (t / "look.tex").write_text(look_tex(look, colors))
        cmd = ["pandoc", "-f", "markdown+mark-tex_math_dollars-raw_tex-raw_attribute-yaml_metadata_block-implicit_figures",
               "-o", str(t / "out.pdf"), "--pdf-engine=xelatex", "-H", str(t / "look.tex"),
               "-V", "papersize=a4", "-V", "geometry:margin=2.6cm", "-V", "fontsize=11pt", "-V", "linestretch=1.3",
               "--resource-path", str(beside)]           # a ![](picture.png) beside the note
        if face:
            cmd += ["-V", f"mainfont={face}"]
        for k, v in meta.items():
            if v:
                cmd += ["-M", f"{k}={v}"]
        r = subprocess.run(cmd, input=body, capture_output=True, text=True, cwd=tmp, timeout=120)
        if r.returncode != 0 or not (t / "out.pdf").is_file():
            err = [l for l in (r.stderr or "").splitlines() if l.startswith("!") or "Error" in l]
            raise RuntimeError("pandoc failed: " + ("; ".join(err[:3]) or (r.stderr or "").strip()[-300:]))
        out.parent.mkdir(parents=True, exist_ok=True)
        part = out.with_name("." + out.name + ".part")
        shutil.copyfile(t / "out.pdf", part)
        part.replace(out)


def day_words(date: dt.date) -> str:
    return f"{date.day} {date:%B %Y}"
