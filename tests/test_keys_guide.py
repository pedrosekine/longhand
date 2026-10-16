"""docs/keys.md is the keys as they are in Shortcuts.js and hyprkeys.py.

A key added or moved without running tools/keys_guide.py fails here.

Run: python3 tests/test_keys_guide.py   (needs node on PATH)
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

r = subprocess.run([sys.executable, str(ROOT / "tools" / "keys_guide.py"), "--check"], capture_output=True, text=True)
if r.returncode != 0:
    print(r.stderr.strip() or r.stdout.strip())
    print("FAIL")
    sys.exit(1)
print("PASS")
