"""`pomo`, `longhand-agent`, `longhand-check` and `longhand-read` as commands
Windows can start by name.

On Omarchy `tools/install` links the scripts into ~/.local/bin and their
shebangs do the rest. Windows starts only an .exe by name, so the agent's
`subprocess.run(["pomo", …])` and longhand-check's found nothing. Installing
this folder (`pip install -e windows`) makes one .exe for each, beside
python.exe; each comes here, and from here the script itself is run, as it
is in the repo.

Two things the scripts take for granted on Linux are seen to on the way:

- UTF-8 everywhere. The agent and the check read notes and pipes without
  naming an encoding, which on Windows would be the ANSI code page: a note's
  "→" or "📅" misread, or a crash. Python's UTF-8 mode can only be chosen
  before it starts, so a script that needs it is started again with it on
  (once: the host already starts its children that way).
- `fcntl`, which the scripts lock with: pyshim/ has a stand-in.
- "\\n" as the line ending of what is written: pyshim/longhand_lf.py.
"""
from __future__ import annotations

import os
import runpy
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
PYSHIM = HERE / "pyshim"


def surroundings() -> None:
    """What every script started from here, and whatever it starts, finds:
    the stand-ins on Python's path, the launchers on PATH, UTF-8."""
    old = os.environ.get("PYTHONPATH", "")
    if str(PYSHIM) not in old.split(os.pathsep):
        os.environ["PYTHONPATH"] = str(PYSHIM) + (os.pathsep + old if old else "")
    scripts = str(Path(sys.executable).parent)
    if scripts.lower() not in (p.lower() for p in os.environ.get("PATH", "").split(os.pathsep)):
        os.environ["PATH"] = scripts + os.pathsep + os.environ.get("PATH", "")
    os.environ["PYTHONUTF8"] = "1"
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")


def run(relative: str, utf8: bool = True) -> int:
    script = REPO / relative
    surroundings()
    if utf8 and not sys.flags.utf8_mode:
        # Again, with UTF-8 mode on from the start.
        try:
            return subprocess.call([sys.executable, "-X", "utf8", str(script), *sys.argv[1:]])
        except KeyboardInterrupt:
            return 130
    if str(PYSHIM) not in sys.path:
        sys.path.insert(0, str(PYSHIM))
    import longhand_lf  # noqa: F401 — "\n" as the line ending, if Python did not load it at start
    # As `python script` would: the script's own folder first, its name in argv.
    sys.path.insert(0, str(script.parent))
    sys.argv[0] = str(script)
    try:
        runpy.run_path(str(script), run_name="__main__")
    except SystemExit as e:
        if e.code is None:
            return 0
        if isinstance(e.code, int):
            return e.code
        print(e.code, file=sys.stderr)
        return 1
    return 0


def pomo() -> int:
    # Names every encoding itself: no second start.
    return run("cli/pomo.py", utf8=False)


def agent() -> int:
    return run("agent/longhand-agent")


def check() -> int:
    return run("cli/longhand-check")


def read() -> int:
    return run("cli/longhand-read")


def doctor() -> int:
    return run("tools/doctor")
