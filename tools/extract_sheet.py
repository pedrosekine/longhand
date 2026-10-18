#!/usr/bin/env python3
"""Move one of Page.qml's visual blocks into a file of its own (2026-10-18,
the split of Page.qml), without changing what it does.

The block becomes `<Name>.qml`, a component whose root keeps the block's id
and takes the page as `page`; inside it, `root.` becomes `page.`, and the
page's own objects it used (the palette, the content area, the editor…)
arrive as read-only properties of the same names, so its body is otherwise
unchanged (`root` itself, as a Connections target, becomes `page`
too). The inner items the page's logic reaches for are exposed as
aliases named `<id>Ref`, and the page's references to them are rewritten.

Run: python3 tools/extract_sheet.py <block id> <Name> "<one-line comment>"
     [outerId=pageProperty ...]
"""
import re
import sys
from pathlib import Path

PAGE = Path(__file__).resolve().parent.parent / "plugin-page" / "Page.qml"

block_id, name, comment = sys.argv[1], sys.argv[2], sys.argv[3]
provide = dict(a.split("=", 1) for a in sys.argv[4:])   # outer id -> page property

src = PAGE.read_text().split("\n")
ids = {m.group(1): n for n, l in enumerate(src) for m in [re.search(r"\bid: (\w+)", l)] if m}

i = next(n for n, l in enumerate(src) if re.match(r"^\s+id: " + block_id + r"\s*$", l))
start = i - 1
while not src[start].rstrip().endswith("{"):
    start -= 1
depth = 0
for end in range(start, len(src)):
    depth += src[end].count("{") - src[end].count("}")
    if depth == 0:
        break
indent = len(src[start]) - len(src[start].lstrip())
opener = src[start].strip()                   # e.g. "BorderSurface {"
body = src[start + 1:end]                      # between the braces
inner = {k for k, n in ids.items() if start <= n <= end}
text_body = "\n".join(body)
rest = "\n".join(src[:start] + src[end + 1:])

code_body = "\n".join(re.sub(r"//.*$", "", l) for l in body)          # comments are not uses
outer = sorted({k for k in ids if k not in inner and k != "root" and re.search(r"\b" + k + r"\b\.", code_body)})
missing = [k for k in outer if k not in provide]
if missing:
    sys.exit(f"the block uses page objects with no page property given: {missing} (pass id=property)")
# What the page's code (not its comments or strings) reaches into the block
# for: `<id>.something` — names inside a delegate are the delegate's own.
def code_only(t):
    t = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', t)
    return "\n".join(re.sub(r"//.*$", "", l) for l in t.split("\n"))
code_rest = code_only(rest)
exposed = sorted({k for k in inner if k != block_id and re.search(r"(?<![\w.])" + k + r"\s*\.", code_rest)})

# The body, re-indented to the new file's two spaces, `root.` -> `page.`.
def dedent(l):
    return l[indent:] if l.startswith(" " * indent) else l.lstrip()
lines = [dedent(l) for l in body]
# `root.x` and a bare `root` (a Connections target, an argument) alike.
lines = [re.sub(r"(?<![\w.])root\b", "page", l) for l in lines]
lines = [l for l in lines if not re.match(r"^  id: " + block_id + r"\s*$", l)]

imports = [l for l in src[:40] if l.startswith("import ")]
out = imports + ["", f"// {comment}", "// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is", "// the page itself.", opener,
                 f"  id: {block_id}", "  required property Item page"]
for k in outer:
    out.append(f"  readonly property var {k}: page.{provide[k]}")
for k in exposed:
    out.append(f"  property alias {k}Ref: {k}")
out.append("")
out += lines
out.append("}")
(PAGE.parent / f"{name}.qml").write_text("\n".join(out) + "\n")

# The page: the block replaced by its component; its inner items reached
# through the aliases.
pad = " " * indent
new = src[:start] + [f"{pad}// {comment} ({name}.qml)", f"{pad}{name} {{ id: {block_id}; page: root }}"] + src[end + 1:]
text = "\n".join(new)
def in_code(line, at):
    before = line[:at]
    return "//" not in before and before.count('"') % 2 == 0
out_lines = []
for line in text.split("\n"):
    for k in exposed:
        pos = 0
        res = ""
        for m in re.finditer(r"(?<![\w.])" + k + r"(?=\s*\.)", line):
            res += line[pos:m.start()] + (f"{block_id}.{k}Ref" if in_code(line, m.start()) else m.group(0))
            pos = m.end()
        line = res + line[pos:]
    out_lines.append(line)
text = "\n".join(out_lines)
PAGE.write_text(text)
print(f"{block_id}: {end - start + 1} lines → {name}.qml · uses {outer} · exposes {exposed}")
