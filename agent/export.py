"""A note's blocks as a PDF to hand in (2026-11-04, the first diary).

The person picks the blocks; nothing here writes words of its own. A
section is chosen by a line in it — from its upmost heading down to the
next heading as high — and each block starts in or out: Longhand's agent
link, checkboxes and private blocks out, everything else in. What is kept
loses the layer's marks (tags, task dates, block ids, wikilink brackets)
and keeps its words. Two looks: minimal (a white page, black headings)
and omarchy (the current theme's colours, read when it is made: on
Windows, which has no theme file, Windows' own light or dark and accent).
pandoc and xelatex make the PDF, only when asked; nothing stays resident.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path

import blocks as blocklib

LOOKS = ("minimal", "omarchy")
# The page's own faces, in its order (Page.qml's proseChoices): the PDF
# reads as the note does. Adwaita Sans first, from the page's own static
# cuts (plugin-page/fonts), so it is there on every machine: xelatex takes
# no variable font's named instance, and GNOME installs Adwaita Sans as
# one. Then the faces a machine may have, the static Segoe UI on Windows.
OWN_FACE = "Adwaita Sans"
OWN_CUTS = Path(__file__).resolve().parent.parent / "plugin-page" / "fonts"
FONTS = ("Inter", "Noto Sans", "iA Writer Quattro S", "iA Writer Duo S") + (("Segoe UI",) if os.name == "nt" else ())
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
CALLOUT = re.compile(r"^(>\s*)\[!([\w-]+)\][+-]?\s*(.*)$")
WORD = re.compile(r"[^\W_][\w’'.-]*")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
CODE_SPAN = re.compile(r"(`+)(?!`).*?(?<!`)\1(?!`)")
# The arrows the note draws (Emph.js arrowsIn: longest first, none in code
# or a link), written as drawn: xelatex would set "-\textgreater{}".
ARROW = re.compile(r"<->|->|<-")
ARROW_GLYPH = {"<->": "↔", "->": "→", "<-": "←"}
LINK = re.compile(r"!?\[([^\]\n]*)\]\([^)\n]*\)")
EMPHASIS = re.compile(r"(\*\*|__|==|~~|(?<![\w*])\*(?=\S)|(?<=\S)\*(?![\w*]))")


def split(text: str) -> list[dict]:
    """The note's blocks (blocks.py, the page's twin), with a fenced code
    block kept whole as one "code" block: a `# comment` in it is no
    heading, a `- x` no item, and nothing in it is cleaned. The blocks
    around a fence are blocks.py's own, with its hashes."""
    lines = text.split("\n")
    out: list[dict] = []
    start, i, n = 0, 0, len(lines)

    def plain(a: int, b: int) -> None:
        if b <= a:
            return
        for blk in blocklib.split("\n".join(lines[a:b])):
            out.append(dict(blk, start=blk["start"] + a, end=blk["end"] + a))

    head = blocklib.split(text)
    if head and head[0]["kind"] == "frontmatter":
        out.append(head[0])
        start = i = head[0]["end"]
    while i < n:
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        mark = m.group(1)
        j = i + 1
        while j < n and not re.match(r"^ {0,3}" + re.escape(mark[0]) + "{%d,}\\s*$" % len(mark), lines[j]):
            j += 1
        end = min(j + 1, n)                            # a fence never closed runs to the note's end
        plain(start, i)
        body = "\n".join(lines[i:end])
        out.append({"kind": "code", "start": i, "end": end, "text": body, "hash": blocklib.fnv1a(body), "private": False})
        start = i = end
    plain(start, n)
    return out


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


def arrowed(text: str) -> str:
    """`->`, `<-`, `<->` as the note draws them, outside a link."""
    out, at = [], 0
    for m in LINK.finditer(text):
        out.append(ARROW.sub(lambda a: ARROW_GLYPH[a.group(0)], text[at:m.start()]))
        out.append(m.group(0))
        at = m.end()
    out.append(ARROW.sub(lambda a: ARROW_GLYPH[a.group(0)], text[at:]))
    return "".join(out)


def clean_line(line: str, arrows: bool = False) -> str:
    """One line without the layer's marks: tags, task dates and
    priorities, block ids, wikilink brackets (the words stay). Inline code
    is left as written: `#include` and `a[[0]]` are code, not a tag or a
    link. `arrows`: `->` written as the note draws it, →."""
    parts, at = [], 0
    for m in CODE_SPAN.finditer(line):
        parts.append((False, line[at:m.start()]))
        parts.append((True, m.group(0)))
        at = m.end()
    parts.append((False, line[at:]))
    out = []
    for code, text in parts:
        if not code:
            text = TASK_DATE.sub("", text)
            text = PRIORITY.sub("", text)
            text = BLOCK_ID.sub("", text)
            text = WIKILINK.sub(lambda m: m.group(3) or (Path(m.group(1)).stem if m.group(1) else m.group(2) or ""), text)
            text = TAG.sub("", text)
            if arrows:
                text = arrowed(text)
        out.append(text)
    line = "".join(out)
    return re.sub(r"[ \t]+$", "", re.sub(r"(?<=\S)[ \t]{2,}", " ", line))


def title_of(text: str) -> str:
    m = HEADING.match(text.splitlines()[0]) if text else None
    words = clean_line(m.group(2) if m else text.splitlines()[0] if text else "")
    return re.sub(r"\s+", " ", words).strip()


def clean(block: dict, shift: int, image, arrows: bool = False) -> str:
    """A kept block as pandoc reads it: marks gone, a heading moved up by
    `shift` levels (a section titled by a ## heading keeps its ### as ##),
    a callout's title in bold (its kind when it has none: "Warning"), an
    embedded picture by its path (`image(name)`, or dropped when it is not
    found). Fenced code goes as written."""
    if block["kind"] == "code":
        return block["text"].strip("\n")
    out = []
    for line in block["text"].split("\n"):
        line = EMBED.sub(lambda m: embed(m, image), line)
        m = HEADING.match(line) if block["kind"] == "heading" else None
        if m:
            n = max(1, len(m.group(1)) - shift)
            line = "#" * n + " " + clean_line(m.group(2), arrows)
        else:
            c = CALLOUT.match(line) if block["kind"] == "callout" else None
            if c:
                said = clean_line(c.group(3), arrows).strip() or c.group(2).replace("-", " ").capitalize()
                line = c.group(1) + "**" + said + "**"
            else:
                line = clean_line(line, arrows)
        out.append(line)
    return "\n".join(out).strip("\n")


def shown(block: dict, shift: int = 0) -> str:
    """A block as the sheet lists it: the words that go, without the
    layer's marks or markdown's ("**chapter**" is "chapter", a link its
    label, a quote without its >). A checkbox keeps its box."""
    if block["kind"] == "code":
        return block["text"]
    out = []
    for line in clean(block, shift, lambda name: None, True).split("\n"):
        if block["kind"] == "heading":
            line = HEADING.sub(lambda m: m.group(2), line)
        line = re.sub(r"^>\s?", "", line)
        line = LINK.sub(lambda m: m.group(1), line)
        line = EMPHASIS.sub("", line)
        out.append(line)
    return "\n".join(out).strip()


def lost(block: dict, image) -> list[str]:
    """What a block embeds that the PDF will not have: a picture not
    found, a note (embedded notes are not drawn)."""
    if block["kind"] == "code":
        return []
    out = []
    for m in EMBED.finditer(block["text"]):
        name = m.group(1).strip()
        if not name.lower().endswith(IMAGE_EXT) or not image(name):
            out.append(name)
    return out


def embed(m: re.Match, image) -> str:
    name = m.group(1).strip()
    if not name.lower().endswith(IMAGE_EXT):
        return ""                                     # an embedded note: not drawn in slice 1
    path = image(name)
    return f"![](<{path}>)" if path else ""


def assemble(kept: list[dict], shift: int, image, arrows: bool = False) -> str:
    """The body: kept blocks in the note's order. List items that were
    next to each other stay one list; anything else is a paragraph apart."""
    out, prev = [], None
    for b in kept:
        text = clean(b, shift, image, arrows)
        if not text.strip():
            prev = None
            continue
        tight = prev is not None and prev["kind"] == "item" and b["kind"] == "item" and prev["end"] == b["start"]
        out.append(("\n" if tight else "\n\n") if out else "")
        out.append(text)
        prev = b
    return "".join(out) + "\n"


def words(body: str) -> int:
    """The words of the prose, headings and fenced code left out (a
    300-word entry counts what is written under them): a link counts its
    label, not its address, and a list's mark and box are no word."""
    n, fence = 0, ""
    for l in body.splitlines():
        m = FENCE.match(l)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not l[m.end():].strip():
                fence = ""
            continue
        if m:
            fence = m.group(1)
            continue
        if HEADING.match(l):
            continue
        l = LINK.sub(lambda x: x.group(1), l)
        l = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[.\]\s+)?", "", l)
        n += len(WORD.findall(l))
    return n


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
        return windows_colors() if os.name == "nt" and path == COLORS else {}
    return {k: v.lstrip("#") for k, v in raw.items() if isinstance(v, str) and re.fullmatch(r"#?[0-9A-Fa-f]{6}", v)}


def windows_colors() -> dict:
    """Windows' light or dark and accent under a theme's names, as the page
    draws with them there (windows/palette.py says them for both)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "longhand_palette", Path(__file__).resolve().parent.parent / "windows" / "palette.py")
    try:
        palette = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(palette)
        got = palette.theme()
    except (OSError, ImportError, AttributeError):
        return {}
    return {k: v.lstrip("#") for k, v in got.items()}


def look_tex(look: str, colors: dict) -> str:
    """The LaTeX each look adds. Both left-align: the page's faces are
    near-monospaced, and justifying them opens holes between words."""
    # The PDF's text is the text written: without this, a face whose one
    # hyphen glyph serves both "-" and U+2010 (Segoe UI, Calibri) gives
    # "kick‐off" to a copy or a search, not "kick-off".
    tex = [r"\XeTeXgenerateactualtext=1", r"\raggedright", r"\usepackage{xcolor}"]
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
                r"\AtBeginDocument{\hypersetup{colorlinks=true,urlcolor=lhlink,linkcolor=lhlink}}",
                # ==marked== on the theme's ground: the accent sunk into it,
                # under the theme's text (soul's yellow under light text
                # could not be read).
                r"\colorlet{lhmark}{lhac!35!lhbg}\AtBeginDocument{\ifdefined\sethlcolor\sethlcolor{lhmark}\fi}"]
    else:
        tex += [r"\AtBeginDocument{\hypersetup{colorlinks=true,urlcolor=black,linkcolor=black}}"]
    return "\n".join(tex) + "\n"


def _win_fonts() -> set[str]:
    """Installed font family names from the Windows Fonts registry keys."""
    if os.name != "nt":
        return set()
    import winreg
    out: set[str] = set()
    style = re.compile(r"\s+(?:Regular|Bold|Italic|Oblique|Light|Semilight|Semibold|Medium|Black|Thin|Heavy|ExtraLight|ExtraBold)$", re.I)
    for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
        try:
            with winreg.OpenKey(hive, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts") as key:
                i = 0
                while True:
                    try:
                        name, _, _ = winreg.EnumValue(key, i)
                    except OSError:
                        break
                    i += 1
                    clean = re.sub(r"\s*\([^)]*\)\s*$", "", str(name)).strip()
                    for part in clean.split("&"):
                        base = part.strip()
                        if not base:
                            continue
                        out.add(base)
                        cur = base
                        while True:
                            nxt = style.sub("", cur).strip()
                            if nxt == cur or not nxt:
                                break
                            cur = nxt
                            out.add(cur)
        except OSError:
            pass
    return out


def installed_fonts() -> set[str]:
    """Font families installed on this machine: fc-list where available,
    falling back to the Windows Fonts registry when fc-list is absent."""
    try:
        have = {f.strip() for f in subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True,
                                                  timeout=10).stdout.replace(",", "\n").splitlines() if f.strip()}
    except (OSError, subprocess.SubprocessError):
        have = set()
    return have or _win_fonts()


def own_cuts() -> bool:
    return all((OWN_CUTS / f"AdwaitaSans-{c}.ttf").is_file() for c in ("Regular", "Bold", "Italic", "BoldItalic"))


def font(*wanted: str) -> str:
    """The face to set it in: the first asked for that is installed (the
    export's `font`, then the page's), else the page's own Adwaita Sans
    (from its cuts), else the page's others; "" leaves pandoc's own."""
    have = None
    for f in (w for w in wanted if w):
        have = installed_fonts() if have is None else have
        if f in have and f != OWN_FACE:
            return f
        if f == OWN_FACE and own_cuts():
            return f
    if own_cuts():
        return OWN_FACE
    have = installed_fonts() if have is None else have
    for f in FONTS:
        if f in have:
            return f
    return ""


def face_options(face: str) -> list[str]:
    """pandoc's -V for the face: the page's own by its files, so its bold
    and italic are its own cuts, never a variable font's guess."""
    if face == OWN_FACE and own_cuts():
        return ["-V", "mainfont=AdwaitaSans", "-V",
                f"mainfontoptions=Path={OWN_CUTS.as_posix()}/,Extension=.ttf,UprightFont=*-Regular,"
                "BoldFont=*-Bold,ItalicFont=*-Italic,BoldItalicFont=*-BoldItalic"]
    return ["-V", f"mainfont={face}"] if face else []


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
        cmd += face_options(face)
        if look == "omarchy" and colors.get("background") and colors.get("foreground"):
            # pandoc's colours for code are dark ink for a white page: on the
            # theme's ground, code is drawn in the theme's text instead.
            cmd += ["--syntax-highlighting=none"]
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


NAME_WORD = re.compile(r"[^\W\d_]{3,}")


def name_words(text: str) -> set[str]:
    """What a name is about: its words of three letters or more, without
    tags, numbers or dates ("Reflective Research Diary 2" and "Reflective
    Research Diary - 2026.11.02 #studio" share three)."""
    return {w.lower() for w in NAME_WORD.findall(TAG.sub(" ", text))}


def candidates(sections: list[dict], title: str, due: dt.date | None, fmt: str) -> list[dict]:
    """The sections a deadline's work may be in, likeliest first: its
    course's headed sections written by its day, those whose heading
    shares the most words with its name first, then the newest; then
    those written after it (late, or given more time), the nearest its
    day first, each marked `late`. Every one stays a step away (← →): a
    heading sharing no word is never dropped, only put after."""
    want = name_words(title)
    out = []
    for sec in sections:
        if not sec.get("level"):
            continue                                   # a day's stray boxes, no heading
        try:
            day = dt.datetime.strptime(sec["date"], fmt).date()
        except ValueError:
            continue
        late = bool(due and day > due)
        out.append(dict(sec, day=day, late=late, score=len(want & name_words(sec.get("heading", "")))))
    out.sort(key=lambda c: (c["late"], -c["score"], c["day"].toordinal() if c["late"] else -c["day"].toordinal(), c["line"]))
    return out


def day_words(date: dt.date) -> str:
    return f"{date.day} {date:%B %Y}"
