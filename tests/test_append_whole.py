"""A line appended to a file is appended whole, however many append at once.

Longhand's logs grow a line at a time (the ledger, feedback, each
machine's conversation, deadlines and proposals, the check-ins, the page's
usage), and runs side by side append to the same file at once. On Linux a
file opened for appending puts every write at the end. On Windows Python's
`open(..., "a")` is a seek and a write, and one process's line landed over
another's (2026-11-25). The stand-in windows/pyshim/longhand_append.py,
loaded at the start of every Python Longhand starts, opens such a file for
appending only, which Windows appends to whole. Here: processes started as
the host starts its children append at once and every line is there,
whole; and a file opened so behaves as `open` would otherwise.

On Linux nothing is stood in for, and the same steps pass as they are.

Run: python3 tests/run_all.py append_whole
"""
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
WINDOWS = os.name == "nt"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


WRITERS, LINES = 6, 300
# One writer: appends its lines one open at a time, as the agent does.
WRITER = """
import sys
path, tag, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
for i in range(n):
    with open(path, "a") as f:
        f.write(f"{tag}\\t{i}\\t" + "x" * 80 + "\\n")
"""

with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    # As the host starts its children: only windows/pyshim on the path,
    # whose sitecustomize Python loads by itself.
    env = dict(os.environ, PYTHONPATH=str(ROOT / "windows" / "pyshim"))

    log = d / "ledger.tsv"
    writers = [subprocess.Popen([sys.executable, "-c", WRITER, str(log), str(t), str(LINES)], env=env)
               for t in range(WRITERS)]
    codes = [w.wait() for w in writers]
    check(codes == [0] * WRITERS, f"{WRITERS} processes append to one file at once ({codes})")
    raw = log.read_bytes()
    lines = raw.decode("utf-8").split("\n")[:-1]
    whole = [ln for ln in lines if ln.count("\t") == 2 and ln.endswith("x" * 80)]
    check(len(lines) == WRITERS * LINES, f"every line is there ({len(lines)} of {WRITERS * LINES})")
    check(len(whole) == len(lines), f"and every one whole ({len(lines) - len(whole)} cut into another)")
    seen = {tuple(ln.split("\t")[:2]) for ln in whole}
    check(len(seen) == WRITERS * LINES, "and each once")
    check(b"\r\n" not in raw, "lines end with \\n, as before")

    # A file opened so is what `open` gives otherwise.
    probe = r"""
import io, os, sys
d = sys.argv[1]
out = []
p = os.path.join(d, "notes.txt")
with open(p, "w") as f:
    f.write("one\n")
with open(p, "a") as f:
    out.append(f"tell {f.tell()}")       # at the end, as Linux says
    f.write("two\n")
with open(p, "ab") as f:
    f.write(b"three\n")
with open(p, "a", encoding="utf-8") as f:
    f.write("fünf\n")
out.append("text " + repr(open(p, "rb").read()))
new = os.path.join(d, "new.jsonl")
with open(new, "a") as f:                    # made when it is not there
    f.write("{}\n")
out.append("made " + repr(open(new, "rb").read()))
with open(p, "a") as w, open(p) as r:       # read while another appends
    w.write("six\n")
    w.flush()
    out.append("read " + repr(r.read().splitlines()[-1]))
for bad in (os.path.join(d, "no", "such", "x.txt"), d):
    try:
        open(bad, "a")
        out.append("opened")
    except OSError as e:
        out.append(type(e).__name__)
print(getattr(io.open, "_longhand_append", False))
print("\n".join(out))
"""
    got = subprocess.run([sys.executable, "-c", probe, str(d)], env=env, capture_output=True, text=True)
    out = got.stdout.splitlines()
    if got.returncode != 0:
        print(got.stderr)
    if WINDOWS:
        check(out[:1] == ["True"], "a child of the host has the stand-in")
    else:
        check(out[:1] == ["False"], "on Linux open is left as it is")
    rest = out[1:]
    check("tell 4" in rest, "a file opened to append is at its end")
    check("text b'one\\ntwo\\nthree\\nf\\xc3\\xbcnf\\n'" in rest, "text, bytes and an encoding append as written")
    check("made b'{}\\n'" in rest, "a file not there yet is made")
    check("read 'six'" in rest, "another reads the file while it is appended to")
    check(rest[-2:] == ["FileNotFoundError", "IsADirectoryError" if not WINDOWS else "PermissionError"],
          f"a missing folder and a folder fail as open fails ({rest[-2:]})")

    # The launchers and the tests load it too.
    for name, path in (("the launcher", ROOT / "windows" / "longhand_launch.py"),
                       ("the tests' sitecustomize", ROOT / "tests" / "windows" / "sitecustomize.py"),
                       ("the host's sitecustomize", ROOT / "windows" / "pyshim" / "sitecustomize.py")):
        check("longhand_append.install()" in path.read_text(encoding="utf-8"), f"{name} installs it")

print("\nall ok" if not failures else f"\n{failures} failed")
sys.exit(1 if failures else 0)
