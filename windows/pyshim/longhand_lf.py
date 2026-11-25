"""Windows only: what Longhand's Python writes ends its lines as Linux does.

The agent, the planner and the checks write text without naming a line
ending, and send a model its payload through a pipe opened as text. On
Linux that is "\\n" and nothing more is said. On Windows, Python turns every
"\\n" written that way into "\\r\\n", and so (found 2026-11-24, the first day
on a real vault):

- every file the agent wrote into the vault carried "\\r\\n", and the vault
  is shared with machines that write "\\n";
- an installed prompt had another fingerprint than the same prompt on Linux
  (`prompt_version` reads its bytes), so the same prompt read as changed;
- Codex was given its instructions and the student's words with "\\r\\n",
  kept them so in its session file, and `codex_check`, which holds what
  Codex carried against what Longhand sent, found neither the same and
  dropped every run: Codex had done nothing wrong.

Imported once at start (pyshim/sitecustomize.py, which Python loads by
itself when pyshim/ is on PYTHONPATH; the launchers and the tests name it
too), this makes "\\n" the line ending of every file opened for writing as
text with none named, and of every child's stdin opened as text. Reading
is left as it is: "\\r\\n" in a file from elsewhere is still read as "\\n".
"""
import os

if os.name == "nt":
    import builtins
    import io
    import subprocess

    _open = io.open

    def lf_open(file, mode="r", buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None):
        if newline is None and "b" not in mode and any(c in mode for c in "wax+"):
            newline = "\n"
        return _open(file, mode, buffering, encoding, errors, newline, closefd, opener)

    lf_open.__doc__ = _open.__doc__

    class Popen(subprocess.Popen):
        """A child whose stdin, opened as text, is sent "\\n" as written."""

        def __init__(self, *args, **kw):
            super().__init__(*args, **kw)
            if isinstance(self.stdin, io.TextIOWrapper):
                self.stdin.reconfigure(newline="\n")

    if getattr(io.open, "__name__", "") != "lf_open":       # once, however often it is imported
        builtins.open = io.open = lf_open
        subprocess.Popen = Popen
