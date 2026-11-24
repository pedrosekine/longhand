#!/usr/bin/env python3
"""Cross-platform filesystem and tool helpers for plugin-page/.

Replaces the POSIX-only `find`, `file`, and `sh -c` calls that Page.qml,
FilesPane.qml, and Service.qml used to make — so the page works identically
on Linux, Windows (without Git Bash's usr/bin tools), and macOS.

Subcommands:
    list <dir>                              single-level entries as "<type>\\t<name>"
    walk <root> [root2 ...]                 recursive .md / .pdf paths (POSIX slashes)
    index <vault>                           vault notes & images, skipping dot-entries
    sizes <file1> [file2 ...]               one line per file: "<w>x<h>" or empty
    append <path> <text>                    append text + "\\n" to path (creating dirs)
    which <cmd1> [cmd2 ...]                 missing commands joined with " and "
    preflight <vault> <runner> <read> [customRunner] [customRead]
"""
from __future__ import annotations

import os
import re
import shutil
import struct
import sys
from pathlib import Path

WALK_EXTS = (".md", ".pdf")
INDEX_EXTS = (".md", ".pdf", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".avif")
SVG_TAG = re.compile(r"<svg\b([^>]*)>", re.IGNORECASE | re.DOTALL)
SVG_ATTR = re.compile(r"""\b(width|height|viewBox)\s*=\s*(?:"([^"]*)"|'([^']*)')""", re.IGNORECASE)
SVG_NUM = re.compile(r"^\s*([0-9]+(?:\.[0-9]+)?)\s*(?:px)?\s*$", re.IGNORECASE)


def _posix_join(prefix: str, rel: str) -> str:
    prefix = prefix.replace("\\", "/").rstrip("/")
    rel = rel.replace("\\", "/").lstrip("/")
    return f"{prefix}/{rel}" if rel else prefix


def cmd_list(args: list[str]) -> int:
    if not args:
        return 0
    folder = args[0]
    try:
        with os.scandir(folder) as it:
            for e in it:
                try:
                    if e.is_symlink():
                        kind = "l"
                    elif e.is_dir(follow_symlinks=False):
                        kind = "d"
                    else:
                        kind = "f"
                except OSError:
                    continue
                print(f"{kind}\t{e.name}")
    except OSError:
        pass
    return 0


def cmd_walk(args: list[str]) -> int:
    for root in args:
        if not os.path.isdir(root):
            continue
        base = os.path.normpath(root)
        prefix = root.replace("\\", "/").rstrip("/")
        for dirpath, _dirs, files in os.walk(base):
            rel_dir = os.path.relpath(dirpath, base)
            rel_dir = "" if rel_dir == "." else rel_dir.replace("\\", "/")
            for name in files:
                if name.lower().endswith(WALK_EXTS):
                    rel = f"{rel_dir}/{name}" if rel_dir else name
                    print(_posix_join(prefix, rel))
    return 0


def cmd_index(args: list[str]) -> int:
    if not args or not os.path.isdir(args[0]):
        return 0
    root = args[0]
    base = os.path.normpath(root)
    prefix = root.replace("\\", "/").rstrip("/")
    for dirpath, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        rel_dir = os.path.relpath(dirpath, base)
        rel_dir = "" if rel_dir == "." else rel_dir.replace("\\", "/")
        for name in files:
            if name.startswith(".") or not name.lower().endswith(INDEX_EXTS):
                continue
            rel = f"{rel_dir}/{name}" if rel_dir else name
            print(_posix_join(prefix, rel))
    return 0


def _jpeg_size(f) -> tuple[int, int] | None:
    f.seek(2)
    while True:
        b = f.read(1)
        if not b:
            return None
        while b != b"\xff":
            b = f.read(1)
            if not b:
                return None
        while b == b"\xff":
            b = f.read(1)
            if not b:
                return None
        marker = b[0]
        if marker in (0xD8, 0xD9, 0x01) or (0xD0 <= marker <= 0xD7):
            continue
        length_bytes = f.read(2)
        if len(length_bytes) < 2:
            return None
        length = struct.unpack(">H", length_bytes)[0]
        if length < 2:
            return None
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            sof = f.read(5)
            if len(sof) < 5:
                return None
            h, w = struct.unpack(">HH", sof[1:5])
            return (w, h) if w > 0 and h > 0 else None
        f.seek(length - 2, os.SEEK_CUR)


def _webp_size(hdr: bytes) -> tuple[int, int] | None:
    if len(hdr) < 30 or hdr[:4] != b"RIFF" or hdr[8:12] != b"WEBP":
        return None
    chunk = hdr[12:16]
    if chunk == b"VP8 " and hdr[23:26] == b"\x9d\x01\x2a":
        w, h = struct.unpack("<HH", hdr[26:30])
        return (w & 0x3FFF, h & 0x3FFF)
    if chunk == b"VP8L" and hdr[20] == 0x2F:
        bits = struct.unpack("<I", hdr[21:25])[0]
        return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
    if chunk == b"VP8X":
        w = int.from_bytes(hdr[24:27], "little") + 1
        h = int.from_bytes(hdr[27:30], "little") + 1
        return (w, h)
    return None


def _avif_ispe(data: bytes, start: int, end: int) -> tuple[int, int] | None:
    pos = start
    while pos + 8 <= end:
        size, kind = struct.unpack_from(">I4s", data, pos)
        hdr = 8
        if size == 1:
            if pos + 16 > end:
                return None
            size = struct.unpack_from(">Q", data, pos + 8)[0]
            hdr = 16
        elif size == 0:
            size = end - pos
        if size < hdr or pos + size > end:
            return None
        body = pos + hdr
        stop = pos + size
        if kind == b"ispe" and body + 12 <= stop:
            w, h = struct.unpack_from(">II", data, body + 4)
            return (w, h) if w > 0 and h > 0 else None
        if kind == b"meta" and body + 4 <= stop:
            found = _avif_ispe(data, body + 4, stop)
            if found:
                return found
        elif kind in (b"iprp", b"ipco"):
            found = _avif_ispe(data, body, stop)
            if found:
                return found
        pos = stop
    return None


def _svg_size(raw: bytes) -> tuple[int, int] | None:
    text = raw.decode("utf-8", "ignore")
    m = SVG_TAG.search(text)
    if not m:
        return None
    attrs: dict[str, str] = {}
    for k, v1, v2 in SVG_ATTR.findall(m.group(1)):
        attrs[k.lower()] = v1 if v1 != "" else v2
    mw = SVG_NUM.match(attrs.get("width", ""))
    mh = SVG_NUM.match(attrs.get("height", ""))
    if mw and mh:
        w, h = round(float(mw.group(1))), round(float(mh.group(1)))
        if w > 0 and h > 0:
            return (w, h)
    vb = attrs.get("viewbox", "").replace(",", " ").split()
    if len(vb) == 4:
        try:
            w, h = round(float(vb[2])), round(float(vb[3]))
            if w > 0 and h > 0:
                return (w, h)
        except ValueError:
            pass
    return None


def image_size(path: str) -> tuple[int, int] | None:
    try:
        with open(path, "rb") as f:
            hdr = f.read(64)
            if len(hdr) >= 24 and hdr[:8] == b"\x89PNG\r\n\x1a\n":
                w, h = struct.unpack(">II", hdr[16:24])
                return (w, h) if w > 0 and h > 0 else None
            if len(hdr) >= 10 and hdr[:6] in (b"GIF87a", b"GIF89a"):
                w, h = struct.unpack("<HH", hdr[6:10])
                return (w, h) if w > 0 and h > 0 else None
            if len(hdr) >= 26 and hdr[:2] == b"BM":
                dib = struct.unpack("<I", hdr[14:18])[0]
                if dib == 12:
                    w, h = struct.unpack("<HH", hdr[18:22])
                else:
                    w, h = struct.unpack("<ii", hdr[18:26])
                    h = abs(h)
                return (w, h) if w > 0 and h > 0 else None
            if len(hdr) >= 30 and hdr[:4] == b"RIFF" and hdr[8:12] == b"WEBP":
                return _webp_size(hdr)
            if len(hdr) >= 2 and hdr[:2] == b"\xff\xd8":
                return _jpeg_size(f)
            if len(hdr) >= 12 and hdr[4:8] == b"ftyp":
                f.seek(0)
                buf = f.read(262144)
                return _avif_ispe(buf, 0, len(buf))
            if b"<svg" in hdr.lower() or path.lower().endswith(".svg"):
                f.seek(0)
                return _svg_size(f.read(65536))
    except OSError:
        return None
    return None


def cmd_sizes(args: list[str]) -> int:
    for path in args:
        sz = image_size(path)
        print(f"{sz[0]}x{sz[1]}" if sz else "")
    return 0


def cmd_append(args: list[str]) -> int:
    if len(args) < 2:
        return 2
    target = Path(args[0])
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "a", encoding="utf-8", newline="\n") as f:
        f.write(args[1] + "\n")
    return 0


def cmd_which(args: list[str]) -> int:
    missing = [name for name in args if not shutil.which(name)]
    if missing:
        print(" and ".join(missing), end="")
    return 0


def _is_exec(path: Path) -> bool:
    return path.is_file() and (os.name == "nt" or os.access(path, os.X_OK))


def _has_tool(configured: str, default_name: str, is_custom: bool) -> bool:
    if configured and (_is_exec(Path(configured)) or shutil.which(configured)):
        return True
    if not is_custom:
        if shutil.which(default_name):
            return True
        if _is_exec(Path.home() / ".local" / "bin" / default_name):
            return True
    return False


def cmd_preflight(args: list[str]) -> int:
    if len(args) < 3:
        return 2
    vault, runner, read_bin = args[0], args[1], args[2]
    custom_runner = len(args) > 3 and bool(args[3])
    custom_read = len(args) > 4 and bool(args[4])
    if not os.path.isdir(vault):
        print(f"vault:{vault}")
        return 0
    miss: list[str] = []
    if not _has_tool(runner, "longhand-agent", custom_runner):
        miss.append("longhand-agent")
    if not _has_tool("", "pomo", False):
        miss.append("pomo")
    if not _has_tool(read_bin, "longhand-read", custom_read):
        miss.append("longhand-read")
    if miss:
        print("missing: " + " ".join(miss))
    return 0


COMMANDS = {
    "list": cmd_list,
    "walk": cmd_walk,
    "index": cmd_index,
    "sizes": cmd_sizes,
    "append": cmd_append,
    "which": cmd_which,
    "preflight": cmd_preflight,
}


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in COMMANDS:
        return 2
    return COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
