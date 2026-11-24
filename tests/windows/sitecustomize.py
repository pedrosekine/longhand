"""Windows only: a script starts by its shebang, as it does on Linux.

The tests start Longhand's scripts by their path (`cli/longhand-check`),
write stand-ins of their own with a `#!` line (an `opencode`, a `hyprctl`)
and put them first on PATH. Linux reads the shebang; Windows starts only an
.exe, and looks on PATH only for one. tests/run_all.py puts this folder on
PYTHONPATH when it runs on Windows, Python loads a `sitecustomize` it finds
there by itself, and so every test — and every Python it starts — gets a
`subprocess` that:

- starts a file with a `#!` line through what the line names: this Python
  for a Python script, Git for Windows' bash for a shell script;
- finds a name with no extension on PATH (the stand-ins);
- sends `cli/pomo`, the bash, to `cli/pomo.py`, its twin (the bash one has
  no `flock` under Git's bash and cannot write);

a `shutil.which` that finds such a stand-in too, and an `os.kill(pid, 0)`
that asks whether a process is there (on Windows it would send Ctrl+C to
the whole console). On Linux this file does nothing.
"""
import os
import sys

if os.name == "nt":
    import shutil
    import subprocess
    from pathlib import Path

    ROOT = Path(__file__).resolve().parents[2]
    TWINS = {str(ROOT / "cli" / "pomo").lower(): ROOT / "cli" / "pomo.py"}
    _which = shutil.which

    def git_bin():
        git = _which("git")
        if git:
            root = Path(git).resolve().parent.parent
            for cand in (root / "usr" / "bin", root.parent / "usr" / "bin"):
                if (cand / "bash.exe").is_file():
                    return cand
        return None

    GIT_BIN = git_bin()

    def on_path(name, path=None):
        """The first file of that name in PATH's own order: one named exactly
        so (a test's stand-in, no extension) or a program (.exe, .cmd…).

        The order is the point. A test puts its `opencode` first on PATH and
        Linux runs that one; Windows' own search looks only for an .exe, and
        on a machine that has the real opencode installed found it further
        along and ran it in the stand-in's place."""
        exts = [e for e in os.environ.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(os.pathsep) if e]
        for folder in (path if path is not None else os.environ.get("PATH", "")).split(os.pathsep):
            if not folder:
                continue
            for cand in [Path(folder) / name] + [Path(folder) / (name + e) for e in exts]:
                if cand.is_file():
                    return cand
        return None

    def which(cmd, mode=os.F_OK | os.X_OK, path=None):
        if os.sep in str(cmd) or "/" in str(cmd):
            return _which(cmd, mode, path)
        found = on_path(str(cmd), path)
        return str(found) if found else None

    def by_shebang(args, env):
        """The command Windows can start for one written for Linux."""
        if isinstance(args, (str, bytes)) or not args:
            return args
        try:
            argv = [os.fspath(a) for a in args]
        except TypeError:
            return args
        head = argv[0]
        if isinstance(head, bytes):
            return args
        if os.sep in head or "/" in head:
            script = Path(head)
        else:
            search = (env or os.environ).get("PATH", "")
            script = on_path(head, search)
            if script is None:
                if GIT_BIN and (GIT_BIN / (head + ".exe")).is_file():
                    return [str(GIT_BIN / (head + ".exe")), *argv[1:]]      # sh, bash, sed…
                return args
            if script.suffix.lower() in (".exe", ".com", ".bat", ".cmd"):
                return [str(script), *argv[1:]]         # the one PATH's order names, by its whole path
        script = TWINS.get(str(script).lower(), script)
        if not script.is_file() or script.suffix.lower() in (".exe", ".com", ".bat", ".cmd"):
            return args
        try:
            with open(script, "rb") as f:
                first = f.readline(256).decode("utf-8", "replace").strip()
        except OSError:
            return args
        if script.suffix.lower() == ".py" or (first.startswith("#!") and "python" in first):
            return [sys.executable, str(script), *argv[1:]]
        if first.startswith("#!") and GIT_BIN and any(first.endswith(s) or (s + " ") in first for s in ("/sh", "/bash", " sh", " bash")):
            return [str(GIT_BIN / "bash.exe"), str(script), *argv[1:]]
        if first.startswith("#!"):
            words = first[2:].split()
            program = words[1] if words and words[0].endswith("env") and len(words) > 1 else (words[0] if words else "")
            found = _which(Path(program).name) if program else None
            if found:
                return [found, str(script), *argv[1:]]
        return args

    def winproc():
        """agent/winproc.py: how a runner is asked to stop on Windows."""
        import importlib.util
        spec = importlib.util.spec_from_file_location("longhand_winproc", ROOT / "agent" / "winproc.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    import signal
    _winproc = None

    class Popen(subprocess.Popen):
        """Started by its shebang; and SIGTERM sent to it asks a runner to
        stop, as the page's host does (agent/winproc.py), where Windows'
        own `terminate` would end it before it could say it was stopped."""

        def __init__(self, args, *rest, **kw):
            global _winproc
            self._stop_name, self._stop_handle = "", 0
            if not kw.get("shell"):
                args = by_shebang(args, kw.get("env"))
                try:
                    _winproc = _winproc or winproc()
                    self._stop_name, self._stop_handle = _winproc.new_stop()
                    kw["env"] = dict(kw["env"] if kw.get("env") is not None else os.environ)
                    kw["env"][_winproc.STOP_ENV] = self._stop_name
                except Exception:       # noqa: BLE001 — a test's process starts all the same
                    self._stop_name = ""
            super().__init__(args, *rest, **kw)

        def send_signal(self, sig):
            if sig == signal.SIGTERM and self._stop_name and self.poll() is None and _winproc.listening(self._stop_name):
                _winproc.ask_stop(self._stop_name)
                return
            super().send_signal(sig)

        def __del__(self, *a, **kw):
            if self._stop_handle and _winproc:
                _winproc.close(self._stop_handle)
                self._stop_handle = 0
            super().__del__(*a, **kw)

    _kill = os.kill

    def kill(pid, sig):
        """`os.kill(pid, 0)` asks whether a process is there. On Windows 0 is
        Ctrl+C, sent to everything on the console — the test, the runner and
        the terminal with them. Asked of the system instead. And SIGTERM sent
        to oneself runs the handler set for it, as on Linux, where Windows
        would end the process there and then."""
        if sig == signal.SIGTERM and pid == os.getpid():
            handler = signal.getsignal(signal.SIGTERM)
            if callable(handler):
                handler(signal.SIGTERM, None)
                return
        if sig != 0:
            return _kill(pid, sig)
        import ctypes
        k32 = ctypes.windll.kernel32
        k32.OpenProcess.restype = ctypes.c_void_p
        handle = k32.OpenProcess(0x1000, False, int(pid))       # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            raise ProcessLookupError(3, "No such process")
        try:
            code = ctypes.c_ulong()
            alive = k32.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code)) and code.value == 259
        finally:
            k32.CloseHandle(ctypes.c_void_p(handle))
        if not alive:
            raise ProcessLookupError(3, "No such process")

    subprocess.Popen = Popen
    shutil.which = which
    os.kill = kill
