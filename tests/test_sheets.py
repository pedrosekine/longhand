"""The page's own files (2026-10-18, after the split of Page.qml): a file
that does not declare `id: root` must not name `root` — it would not be the
page there, and a Connections aimed at it would silently hear nothing (the
dashboard's reschedule field, the keys sheet's and the sidebar's scrolling
to the picked row, until this check).

Run: python3 tests/test_sheets.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = 0
for f in sorted((ROOT / "plugin-page").glob("*.qml")):
    text = f.read_text()
    if re.search(r"^\s*id:\s*root\s*$", text, re.M):
        continue
    for n, line in enumerate(text.split("\n"), 1):
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line.split("//")[0])
        if re.search(r"(?<![\w.])root\b", code):
            print(f"FAIL {f.name}:{n}: names `root`, which is not the page here: {line.strip()}")
            failures += 1
print("PASS" if failures == 0 else f"{failures} FAILED")
sys.exit(1 if failures else 0)
