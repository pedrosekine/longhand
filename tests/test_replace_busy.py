"""A file is replaced even while another process is reading it.

Longhand writes every file whole and moves it over the old one with
`os.replace`. On Windows that move fails while someone else has the old
file open (the page rereading it, `longhand-check`, Syncthing, a virus
scanner), and the write was lost: pomo's tick on 2026-11-24. The stand-in
windows/pyshim/longhand_replace.py, loaded at the start of every Python
Longhand starts, tries again for about three seconds. Here: a reader holds
the file for a moment and the write still lands; a reader that never lets
go still fails, by name, rather than hanging; and a Python started the way
the host starts its children has the stand-in.

On Linux the move never fails for a reader, so the same steps simply pass.

Run: python3 tests/run_all.py replace_busy
"""
import os
import pathlib
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WINDOWS = os.name == "nt"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# A reader in another process: opens the file, says so, holds it for the
# seconds it is given, lets go.
HOLDER = """
import sys, time
f = open(sys.argv[1], "rb")
f.read()
print("held", flush=True)
time.sleep(float(sys.argv[2]))
f.close()
"""


def hold(path: pathlib.Path, seconds: float) -> subprocess.Popen:
    p = subprocess.Popen([sys.executable, "-c", HOLDER, str(path), str(seconds)],
                         stdout=subprocess.PIPE, text=True)
    assert p.stdout.readline().strip() == "held"
    return p


with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    target = d / "ledger.json"
    target.write_text("old\n")

    # A reader that lets go after a moment: the write waits for it, and lands.
    reader = hold(target, 0.5)
    tmp = d / "ledger.json.tmp"
    tmp.write_text("new\n")
    start = time.monotonic()
    try:
        os.replace(tmp, target)
        replaced = True
    except OSError as e:
        replaced = False
        print(f"     {e!r}")
    took = time.monotonic() - start
    reader.wait()
    check(replaced, "a file is replaced while another process reads it for a moment")
    check(target.read_text() == "new\n", "and it holds what was written")
    check(not tmp.exists(), "and the temporary file is gone")
    check(took < 3.5, f"and the write waited no longer than it had to ({took:.2f}s)")

    # Path.replace goes the same way (pathlib calls os.replace).
    reader = hold(target, 0.3)
    tmp.write_text("newer\n")
    try:
        tmp.replace(target)
        replaced = True
    except OSError:
        replaced = False
    reader.wait()
    check(replaced and target.read_text() == "newer\n", "Path.replace too")

    # A reader that never lets go: the write fails, as it should, in seconds.
    if WINDOWS:
        reader = hold(target, 10)
        tmp.write_text("never\n")
        start = time.monotonic()
        try:
            os.replace(tmp, target)
            err = None
        except PermissionError as e:
            err = e
        took = time.monotonic() - start
        # The host, which draws the page, waits only briefly.
        sys.path.insert(0, str(ROOT / "windows"))
        from pyshim.longhand_replace import BRIEF, replace
        start = time.monotonic()
        try:
            replace(tmp, target, BRIEF)
            brief_err = None
        except PermissionError as e:
            brief_err = e
        brief_took = time.monotonic() - start
        reader.kill()
        reader.wait()
        check(err is not None, "a file held open throughout is not replaced: PermissionError, as before")
        check(took < 6, f"and the write gives up within seconds ({took:.2f}s)")
        check(target.read_text() == "newer\n", "and the file is as it was")
        check(brief_err is not None and brief_took < 1, f"the host's brief try gives up at once ({brief_took:.2f}s)")

    # A Python started as the host starts its children (only windows/pyshim
    # on its path) has the stand-in; so does one through longhand_launch.
    env = dict(os.environ, PYTHONPATH=str(ROOT / "windows" / "pyshim"))
    out = subprocess.run([sys.executable, "-c", "import os; print(os.replace.__module__)"],
                         env=env, capture_output=True, text=True).stdout.strip()
    if WINDOWS:
        check(out == "longhand_replace", f"a child of the host has the stand-in ({out})")
    else:
        check(out in ("posix", "nt", "os"), f"on Linux os.replace is left as it is ({out})")

print("\nall ok" if not failures else f"\n{failures} failed")
sys.exit(1 if failures else 0)
