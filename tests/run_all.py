#!/usr/bin/env python3
"""Every test, one command: each tests/test_*.py, the QML tests offscreen,
and — asked for, since it opens a window — the page itself, live.

Run: python3 tests/run_all.py                # the offscreen tests (under a minute)
     python3 tests/run_all.py --page         # and the page, live, in the window shape
     python3 tests/run_all.py --page --overlay   # and the overlay too: it takes the screen for a few seconds

A summary at the end: what failed, by file, and the exit code is how many.
"""
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
QMLTEST = "/usr/lib/qt6/bin/qmltestrunner"


def run(name: str, cmd: list[str], env: dict | None = None, timeout: int = 600) -> bool:
    start = time.time()
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=env, timeout=timeout)
        out, ok = r.stdout + r.stderr, r.returncode == 0
    except subprocess.TimeoutExpired:
        out, ok = f"timed out after {timeout}s", False
    print(f"{'ok  ' if ok else 'FAIL'} {name} ({time.time() - start:.1f}s)", flush=True)
    if not ok:
        lines = [l for l in out.splitlines() if l.startswith(("FAIL", "MISMATCH", "Traceback", "  File", "AssertionError"))]
        for l in (lines or out.splitlines())[-15:]:
            print(f"       {l[:240]}")
    return ok


def main() -> int:
    failed = []
    for f in sorted(TESTS.glob("test_*.py")):
        if not run(f.name, [sys.executable, str(f)]):
            failed.append(f.name)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    if not run("tst_*.qml", [QMLTEST, "-input", str(TESTS)], env=env):
        failed.append("tst_*.qml")
    if "--page" in sys.argv:
        args = ["--overlay"] if "--overlay" in sys.argv else []
        if not run("page/run.py " + " ".join(args), [sys.executable, str(TESTS / "page" / "run.py"), *args], timeout=900):
            failed.append("page/run.py")
    else:
        print("skip page/run.py (it opens a window): --page")
    print("PASS" if not failed else f"{len(failed)} FAILED: {', '.join(failed)}")
    return len(failed)


if __name__ == "__main__":
    sys.exit(main())
