#!/usr/bin/env python3
"""Cross-platform page_fs.py helpers: directory listing, vault indexing,
image header sizing (PNG, GIF, BMP, JPEG, WebP, SVG, AVIF), usage append,
dependency checks, and preflight — with zero POSIX shell or `find`/`file` deps.

Run: python3 tests/test_page_fs.py
"""
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HELPER = ROOT / "plugin-page" / "page_fs.py"
sys.path.insert(0, str(ROOT / "plugin-page"))
import page_fs  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def run(*args, env=None):
    return subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, text=True,
                          encoding="utf-8", env=env, timeout=20)


def make_png(w: int, h: int) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I4sII", 13, b"IHDR", w, h) + b"\x08\x02\x00\x00\x00"


def make_gif(w: int, h: int) -> bytes:
    return b"GIF89a" + struct.pack("<HH", w, h) + b"\x00\x00\x00"


def make_bmp(w: int, h: int) -> bytes:
    return b"BM" + struct.pack("<IHHI", 54, 0, 0, 54) + struct.pack("<Iii", 40, w, -h) + b"\x00" * 28


def make_jpeg(w: int, h: int) -> bytes:
    # SOI + APP0 (16 bytes) + SOF0 with (h, w) + EOI
    app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00\x01\x01\x01\x00\x48\x00\x48\x00\x00"
    sof0 = b"\xff\xc0" + struct.pack(">HBHH", 11, 8, h, w) + b"\x01\x01\x11\x00"
    return b"\xff\xd8" + app0 + sof0 + b"\xff\xd9"


def make_webp_vp8x(w: int, h: int) -> bytes:
    body = b"WEBP" + b"VP8X" + struct.pack("<I", 10) + b"\x00\x00\x00\x00"
    body += (w - 1).to_bytes(3, "little") + (h - 1).to_bytes(3, "little")
    return b"RIFF" + struct.pack("<I", len(body)) + body


def make_avif(w: int, h: int) -> bytes:
    def box(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I4s", 8 + len(payload), kind) + payload
    ftyp = box(b"ftyp", b"avif\x00\x00\x00\x00avif")
    ispe = box(b"ispe", b"\x00\x00\x00\x00" + struct.pack(">II", w, h))
    ipco = box(b"ipco", ispe)
    iprp = box(b"iprp", ipco)
    meta = box(b"meta", b"\x00\x00\x00\x00" + iprp)
    return ftyp + meta


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="page-fs-test-"))
    try:
        vault = tmp / "My Vault"
        (vault / "human" / "Courses").mkdir(parents=True)
        (vault / "human" / "Courses" / "note.md").write_text("# hi\n", encoding="utf-8")
        (vault / "human" / "Courses" / "paper.PDF").write_bytes(b"%PDF-1.4\n")
        (vault / "human" / "Courses" / "ignore.txt").write_text("x", encoding="utf-8")
        (vault / ".obsidian").mkdir()
        (vault / ".obsidian" / "hidden.md").write_text("nope", encoding="utf-8")
        (vault / "human" / ".dot.md").write_text("nope", encoding="utf-8")
        (vault / "agents" / "longhand").mkdir(parents=True)
        (vault / "agents" / "longhand" / "reply.md").write_text("ok", encoding="utf-8")

        # 1. list
        r = run("list", str(vault / "human"))
        lines = set(r.stdout.splitlines())
        check(r.returncode == 0 and "d\tCourses" in lines and "f\t.dot.md" in lines,
              f"list emits <kind>\\t<name> one level deep ({lines})")
        check(run("list", str(tmp / "no-such-dir")).stdout == "", "list on missing dir is empty and exits 0")
        # A link is what it points at; one pointing nowhere is left out
        # (2026-11-28: a folder linked into the vault was never listed).
        if hasattr(os, "symlink"):
            try:
                os.symlink(vault / "human" / "Courses", vault / "human" / "Linked")
                os.symlink(vault / "human" / "Courses" / "note.md", vault / "human" / "linked.md")
                os.symlink(tmp / "gone", vault / "human" / "broken.md")
            except (OSError, NotImplementedError):
                pass
            else:
                lines = set(run("list", str(vault / "human")).stdout.splitlines())
                check("d\tLinked" in lines and "f\tlinked.md" in lines and not any(l.endswith("\tbroken.md") for l in lines),
                      f"links listed as what they point at, broken ones left out ({lines})")
                for n in ("Linked", "linked.md", "broken.md"):
                    (vault / "human" / n).unlink()

        # 2. walk
        r = run("walk", (vault / "human").as_posix(), (vault / "agents").as_posix())
        cut = len(vault.as_posix()) + 1
        walked = sorted(l[cut:] for l in r.stdout.splitlines() if l)
        check(walked == ["agents/longhand/reply.md", "human/.dot.md", "human/Courses/note.md", "human/Courses/paper.PDF"],
              f"walk finds .md and .pdf with POSIX slashes ({walked})")

        # 3. index
        img = vault / "human" / "Courses" / "shot.png"
        img.write_bytes(make_png(640, 480))
        r = run("index", vault.as_posix())
        indexed = sorted(l[cut:] for l in r.stdout.splitlines() if l)
        check(indexed == ["agents/longhand/reply.md", "human/Courses/note.md", "human/Courses/paper.PDF", "human/Courses/shot.png"],
              f"index prunes dot-dirs and dot-files and keeps notes + images ({indexed})")
        # A linked folder is indexed and walked as what it points at, and a
        # link back up is not followed round (2026-11-28, the switcher pass).
        if hasattr(os, "symlink"):
            try:
                (tmp / "outside").mkdir(exist_ok=True)
                (tmp / "outside" / "ext.md").write_text("x\n")
                os.symlink(tmp / "outside", vault / "human" / "Linked")
                os.symlink(vault / "human", vault / "human" / "Courses" / "up")
            except OSError:
                pass
            else:
                indexed = sorted(l[cut:] for l in run("index", vault.as_posix()).stdout.splitlines() if l)
                check("human/Linked/ext.md" in indexed, f"a linked folder is indexed ({indexed})")
                check(len(indexed) < 20, f"…a link back up is walked once ({len(indexed)} paths)")
                walked = sorted(l[cut:] for l in run("walk", (vault / "human").as_posix()).stdout.splitlines() if l)
                check(len(walked) < 20 and "human/Linked/ext.md" in walked, f"…and walked ({walked})")
                (vault / "human" / "Linked").unlink()
                (vault / "human" / "Courses" / "up").unlink()

        # 4. sizes
        gif = tmp / "a.gif"
        bmp = tmp / "b.bmp"
        jpg = tmp / "c.jpg"
        webp = tmp / "d.webp"
        svg = tmp / "e.svg"
        svg_vb = tmp / "f.svg"
        avif = tmp / "g.avif"
        bad = tmp / "bad.png"
        gif.write_bytes(make_gif(320, 200))
        bmp.write_bytes(make_bmp(120, 90))
        jpg.write_bytes(make_jpeg(800, 600))
        webp.write_bytes(make_webp_vp8x(1024, 768))
        svg.write_text('<svg width="400px" height="250"></svg>', encoding="utf-8")
        svg_vb.write_text('<svg viewBox="0 0 512 256"></svg>', encoding="utf-8")
        avif.write_bytes(make_avif(1920, 1080))
        bad.write_bytes(b"not an image")
        r = run("sizes", str(img), str(gif), str(bmp), str(jpg), str(webp), str(svg), str(svg_vb), str(avif),
                str(bad), str(tmp / "missing.png"))
        got = r.stdout.splitlines()
        want = ["640x480", "320x200", "120x90", "800x600", "1024x768", "400x250", "512x256", "1920x1080", "", ""]
        check(got == want, f"sizes reads PNG/GIF/BMP/JPEG/WebP/SVG/AVIF headers and blanks bad/missing ({got})")

        # 5. append
        usage = tmp / "nested" / "state" / "usage.tsv"
        check(run("append", str(usage), "100\topen\twindow").returncode == 0
              and run("append", str(usage), "200\tclose\t10").returncode == 0, "append creates parent dirs and writes")
        raw = usage.read_bytes()
        check(raw == b"100\topen\twindow\n200\tclose\t10\n", f"append writes LF-only UTF-8 lines ({raw!r})")

        # 6. which
        r = run("which", "no_such_longhand_tool_a", "no_such_longhand_tool_b")
        check(r.stdout.strip() == "no_such_longhand_tool_a and no_such_longhand_tool_b",
              f"which reports missing tools joined by 'and' ({r.stdout!r})")
        r = run("which", pathlib.Path(sys.executable).name)
        check(r.stdout.strip() == "" or shutil.which(pathlib.Path(sys.executable).name) is None,
              "which prints nothing when found")

        # 7. preflight
        r = run("preflight", str(tmp / "missing-vault"), str(ROOT / "agent" / "longhand-agent"), str(ROOT / "cli" / "longhand-read"))
        check(r.stdout.strip().startswith("vault:"), f"preflight reports missing vault ({r.stdout.strip()!r})")
        fake_bin = tmp / "bin"
        fake_bin.mkdir()
        ext = ".exe" if os.name == "nt" else ""
        for name in ("longhand-agent", "pomo", "longhand-read"):
            p = fake_bin / (name + ext)
            p.write_text("#!/bin/sh\n", encoding="utf-8")
            p.chmod(0o755)
        env = dict(os.environ, PATH=str(fake_bin))
        r = run("preflight", str(vault), str(tmp / "nonexistent" / "longhand-agent"), str(tmp / "nonexistent" / "longhand-read"), "", "", env=env)
        check(r.stdout.strip() == "", f"preflight finds default tools on PATH ({r.stdout.strip()!r})")
        r = run("preflight", str(vault), str(tmp / "broken-runner"), str(tmp / "nonexistent" / "longhand-read"), "1", "", env=env)
        check(r.stdout.strip() == "missing: longhand-agent",
              f"preflight flags broken explicit custom runner ({r.stdout.strip()!r})")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
