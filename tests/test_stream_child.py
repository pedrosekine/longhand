#!/usr/bin/env python3
"""run_child reading a model's output line by line (2026-11-22: the
thinking's headings shown while the student waits):

- each line reaches the callback as it is printed, before the process ends;
- a payload larger than a pipe holds is written without stalling, and
  stderr is kept;
- past the timeout the whole group is killed and TimeoutExpired raised;
- a stop (SIGTERM to the runner) ends the child at once;
- a callback that fails never fails the run.
"""
import importlib.machinery
import importlib.util
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"

tmp = Path(tempfile.mkdtemp(prefix="longhand-stream-"))
os.environ["XDG_STATE_HOME"] = str(tmp / "state")
os.environ["XDG_CONFIG_HOME"] = str(tmp / "config")
os.environ["LONGHAND_CONFIG"] = str(tmp / "config" / "longhand" / "config.json")
loader = importlib.machinery.SourceFileLoader("longhand_agent_stream", str(AGENT))
la = importlib.util.module_from_spec(importlib.util.spec_from_loader("longhand_agent_stream", loader))
loader.exec_module(la)

fails = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        fails.append(msg)


PY = sys.executable
cwd = str(tmp)

# Lines as they come: the first is seen while the child still sleeps.
seen = []
script = "import sys,time\nprint('one', flush=True)\ntime.sleep(1.5)\nprint('two', flush=True)\n"
t0 = time.time()
r = la.run_child([PY, "-c", script], "", 30, cwd, None, on_line=lambda l: seen.append((l.strip(), time.time() - t0)))
check([s for s, _ in seen] == ["one", "two"] and r.stdout == "one\ntwo\n" and r.returncode == 0,
      "every line reaches the callback, and the output is kept whole")
check(seen and seen[0][1] < 1.2, f"the first line arrives before the process ends ({seen[0][1]:.2f}s)")

# A payload far larger than a pipe: read whole, echoed back, stderr kept.
big = "x" * 400_000 + "\n"
script = "import sys\nd=sys.stdin.read()\nsys.stderr.write('e'*200000)\nprint(len(d))\n"
r = la.run_child([PY, "-c", script], big, 30, cwd, None, on_line=lambda l: None)
check(r.stdout.strip() == str(len(big)) and len(r.stderr) == 200000, "a large payload goes in whole, stderr comes back whole")

# A failing callback is ignored.
r = la.run_child([PY, "-c", "print('a'); print('b')"], "", 30, cwd, None, on_line=lambda l: 1 / 0)
check(r.returncode == 0 and r.stdout == "a\nb\n", "a callback that fails does not fail the run")

# Past the timeout: the group is killed, TimeoutExpired raised.
script = "import subprocess,sys,time\np=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'])\nprint(p.pid, flush=True)\ntime.sleep(60)\n"
pids = []
t0 = time.time()
try:
    la.run_child([PY, "-c", script], "", 1, cwd, None, on_line=lambda l: pids.append(int(l)))
    check(False, "a run past its timeout raises")
except subprocess.TimeoutExpired:
    took = time.time() - t0
    time.sleep(0.2)
    alive = False
    try:
        os.kill(pids[0], 0)
        alive = subprocess.run(["ps", "-o", "stat=", "-p", str(pids[0])], capture_output=True, text=True).stdout.strip()[:1] not in ("Z", "")
    except (OSError, IndexError):
        pass
    check(took < 10 and not alive, f"a run past its timeout raises, its whole group killed ({took:.1f}s)")

# A stop: SIGTERM handled as the runner does, the child ends at once.
signal.signal(signal.SIGTERM, la._on_stop)
threading.Timer(0.5, lambda: os.kill(os.getpid(), signal.SIGTERM)).start()
t0 = time.time()
r = la.run_child([PY, "-c", "import time\nprint('x', flush=True)\ntime.sleep(60)\n"], "", 30, cwd, None, on_line=lambda l: None)
check(time.time() - t0 < 5 and r.returncode != 0, f"a stop ends the child at once ({time.time() - t0:.1f}s)")
la._STOP["asked"] = False

# The heading: the last bold one, lower-cased, an acronym kept, short.
h = la.thinking_heading
check(h("**Constructing chore rotations**\n**Defining chore categories**") == "defining chore categories", "the last heading")
check(h("**DORO deadline check**") == "DORO deadline check", "an acronym keeps its capitals")
check(h("Plain first line\nmore") == "plain first line", "no heading: the first line")
check(len(h("**" + "word " * 40 + "**")) <= 60, "a long heading is cut short")

shutil.rmtree(tmp, ignore_errors=True)
print("PASS" if not fails else f"FAIL ({len(fails)})")
sys.exit(1 if fails else 0)
