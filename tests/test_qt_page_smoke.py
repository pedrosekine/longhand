#!/usr/bin/env python3
"""Smoke test for running tests/page/run.py over the standalone PySide6 IPC host
(tests/page/qt_host.py): loads tests/page/harness.qml + Page.qml offscreen,
verifies theme switching, palette heading ramp, and the weekly check-in flow.

Skips cleanly where PySide6 is not installed (e.g. Arch CI container without it).

Run: python3 tests/run_all.py qt_page_smoke
"""
import importlib.util
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    if importlib.util.find_spec("PySide6") is None:
        print("skip: PySide6 not installed")
        return 0
    r = subprocess.run(
        [sys.executable, str(ROOT / "tests" / "page" / "run.py"), "--host", "qt", "--smoke"],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        timeout=120,
    )
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
