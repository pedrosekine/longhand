"""The seal the page draws (plugin-page/LogoMark.qml) is the master's
(launcher/longhand-mark.svg, docs/brand/README.md): same path, so the page
can never carry a logo of its own.

Run: python3 tests/test_brand.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
master = (ROOT / "launcher" / "longhand-mark.svg").read_text()
page = (ROOT / "plugin-page" / "LogoMark.qml").read_text()

d = re.search(r'<path[^>]*\sd="([^"]+)"', master)
q = re.search(r'PathSvg \{ path: "([^"]+)" \}', page)
ok = bool(d and q and d.group(1) == q.group(1))
print(("ok   " if ok else "FAIL ") + "the page's seal is the master's path")
print("PASS" if ok else "1 FAILED")
sys.exit(0 if ok else 1)
