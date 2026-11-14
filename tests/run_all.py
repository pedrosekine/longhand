#!/usr/bin/env python3
"""Every test, one command: each tests/test_*.py and each tests/tst_*.qml
(offscreen), side by side, and — asked for, since it takes minutes — the
page itself, live, after them and alone.

Run: python3 tests/run_all.py                    # every offscreen test, in parallel (about 12s)
     python3 tests/run_all.py plan agent         # only these: test_plan.py, test_agent.py
     python3 tests/run_all.py 'day*' editor      # a glob, and a QML file (tst_editor.qml)
     python3 tests/run_all.py --failed           # only what failed last time
     python3 tests/run_all.py -j 1               # one at a time, as before
     python3 tests/run_all.py --list             # the names it knows
     python3 tests/run_all.py --page             # and the page, live, in the window shape
     python3 tests/run_all.py --page --overlay   # and the overlay too

A name is a file's own without test_/tst_ and the extension; a QML file and
a Python file may share one (threads), and then both run. `page` names the
live page test, the same as --page.

Every test file runs beside the others, so each must keep to itself: its
own folders from tempfile, its own XDG_STATE_HOME and XDG_CONFIG_HOME for
anything it starts, Hyprland played by fake_hyprctl.py, nothing written
into the repo or the home folder (README → Tests; test_parallel.py checks
what can be checked). A file that truly cannot goes in SERIAL with why, and
runs alone after the rest.

A summary at the end: what failed, by file, and the exit code is how many.
What failed is kept in tests/.last-failed for --failed.
"""
import argparse
import fnmatch
import os
import pathlib
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
QMLTEST = "/usr/lib/qt6/bin/qmltestrunner"
LAST_FAILED = TESTS / ".last-failed"

# Files that cannot run beside the others, each with the reason. Empty is
# the goal: fix the test before adding to it.
SERIAL: dict[str, str] = {}


def short(path: pathlib.Path) -> str:
    stem = path.stem
    for prefix in ("test_", "tst_"):
        if stem.startswith(prefix):
            return stem[len(prefix):]
    return stem


def jobs() -> list[tuple[str, list[str], dict | None, int]]:
    """Every test the runner knows: (file, command, env, timeout)."""
    out = [(f.name, [sys.executable, str(f)], None, 600) for f in sorted(TESTS.glob("test_*.py"))]
    qml_env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    out += [(f.name, [QMLTEST, "-input", str(f)], qml_env, 600) for f in sorted(TESTS.glob("tst_*.qml"))]
    return out


def page_job(overlay: bool) -> tuple[str, list[str], dict | None, int]:
    args = ["--overlay"] if overlay else []
    return ("page/run.py", [sys.executable, str(TESTS / "page" / "run.py"), *args], None, 900)


def run(job) -> tuple[str, bool, float, str]:
    name, cmd, env, timeout = job
    start = time.time()
    try:
        # No test reads the terminal: side by side they would share it, and a
        # stub that waits for input would wait on the keyboard.
        r = subprocess.run(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env,
                           timeout=timeout)
        out, ok = r.stdout + r.stderr, r.returncode == 0
    except subprocess.TimeoutExpired:
        out, ok = f"timed out after {timeout}s", False
    return name, ok, time.time() - start, out


def report(name: str, ok: bool, took: float, out: str) -> None:
    lines = [f"{'ok  ' if ok else 'FAIL'} {name} ({took:.1f}s)"]
    if not ok:
        picked = [l for l in out.splitlines() if l.startswith(("FAIL", "MISMATCH", "Traceback", "  File", "AssertionError"))]
        lines += [f"       {l[:240]}" for l in (picked or out.splitlines())[-15:]]
    print("\n".join(lines), flush=True)


def read_failed() -> list[str]:
    try:
        return [l for l in LAST_FAILED.read_text().split() if l]
    except OSError:
        return []


def write_failed(ran: set[str], failed: set[str]) -> None:
    """What failed stays failed until it runs again, so a run of a few
    files does not forget the others."""
    keep = (set(read_failed()) - ran) | failed
    if keep:
        LAST_FAILED.write_text("".join(f"{n}\n" for n in sorted(keep)))
    else:
        LAST_FAILED.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser(description="Run longhand's tests, side by side.")
    ap.add_argument("names", nargs="*", help="tests to run: plan, 'day*', editor, page (default: every offscreen test)")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4, help="how many at once (default: one per core)")
    ap.add_argument("--failed", action="store_true", help="only what failed last time")
    ap.add_argument("--list", action="store_true", help="the names, and stop")
    ap.add_argument("--page", action="store_true", help="also the page, live, in a private Hyprland (minutes)")
    ap.add_argument("--overlay", action="store_true", help="with the page: the overlay too")
    a = ap.parse_args()

    known = jobs()
    if a.list:
        for name, *_ in known:
            print(f"{short(pathlib.Path(name)):<14} {name}")
        print(f"{'page':<14} page/run.py (the page, live: minutes)")
        return 0

    wanted = list(a.names)
    if a.failed:
        last = read_failed()
        if not last and not wanted:
            print("nothing failed last time")
            return 0
        wanted += [n for n in last if n != "page/run.py"]
        if "page/run.py" in last:
            wanted.append("page")
    if "page" in wanted:
        wanted = [w for w in wanted if w != "page"]
        a.page = True
        if not wanted:
            known = []

    if wanted:
        picked, unknown = [], []
        for w in wanted:
            hits = [j for j in known if fnmatch.fnmatch(short(pathlib.Path(j[0])), w) or j[0] == w]
            (picked.extend(hits) if hits else unknown.append(w))
        if unknown:
            print(f"no test named {', '.join(unknown)} (python3 tests/run_all.py --list)", file=sys.stderr)
            return 2
        seen = set()
        known = [j for j in picked if not (j[0] in seen or seen.add(j[0]))]

    together = [j for j in known if j[0] not in SERIAL]
    alone = [j for j in known if j[0] in SERIAL]
    if a.page:
        alone.append(page_job(a.overlay))

    start = time.time()
    results = []
    with ThreadPoolExecutor(max(1, a.jobs)) as pool:
        for fut in as_completed([pool.submit(run, j) for j in together]):
            results.append(fut.result())
            report(*results[-1])
    for j in alone:
        if j[0] in SERIAL:
            print(f"     {j[0]} runs alone: {SERIAL[j[0]]}", flush=True)
        results.append(run(j))
        report(*results[-1])
    if not a.page and not a.names and not a.failed:
        print("skip page/run.py (the page, live: minutes): --page")

    failed = sorted(name for name, ok, _, _ in results if not ok)
    write_failed({name for name, *_ in results}, set(failed))
    took = f"{len(results)} file{'' if len(results) == 1 else 's'} in {time.time() - start:.1f}s"
    print(f"PASS ({took})" if not failed else f"{len(failed)} FAILED ({took}): {', '.join(failed)}")
    return len(failed)


if __name__ == "__main__":
    sys.exit(main())
