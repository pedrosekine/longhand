"""Quickshell.Io, as the page uses it, for a host that is not Quickshell.

Process, StdioCollector, SplitParser, FileView and FileViewError under the
names and the behaviour plugin-page/ expects, on QProcess and plain files.
Spike: enough to load the page on Windows unmodified, not a full port of
Quickshell's module.
"""
from __future__ import annotations

import os
import shutil
import sys
import time
from collections import deque
from enum import IntEnum
from pathlib import Path

from PySide6.QtCore import (Property, QEnum, QFileSystemWatcher, QMetaObject, QObject, QProcess,
                            QProcessEnvironment, Qt, QTimer, QUrl, Signal, Slot)
from PySide6.QtQml import QmlElement, QmlSingleton

sys.path.insert(0, str(Path(__file__).resolve().parent))
import palette  # noqa: E402
from pyshim.longhand_replace import BRIEF, replace  # noqa: E402

QML_IMPORT_NAME = "Quickshell.Io"
QML_IMPORT_MAJOR_VERSION = 1

REPO = Path(__file__).resolve().parent.parent

# What `tools/install` links into ~/.local/bin on Linux: here, by name.
SCRIPTS = {
    # The timer and the deadline store: bash on Omarchy, its Python twin here.
    "pomo": REPO / "cli" / ("pomo.py" if os.name == "nt" else "pomo"),
    "longhand-agent": REPO / "agent" / "longhand-agent",
    "longhand-check": REPO / "cli" / "longhand-check",
    "longhand-read": REPO / "cli" / "longhand-read",
}
# Names Windows has too, meaning something else (find.exe), or not at all.
POSIX = {"sh", "bash", "find", "file", "sed", "grep", "date", "test", "cat", "ls", "head", "tail", "sort", "xargs"}

LOG = []  # what could not be started, for the spike's report

# Commands the host answers itself, without a process: name -> a function
# of the arguments giving (exit code, stdout, stderr). On Windows, `hyprctl`
# (compositor.py), set by the host.
INSIDE: dict = {}
# Whether `hyprkeys.py` calls are redirected to `winkeys.py` on Windows.
# True for the real Windows host; tests/page/qt_host.py clears it so the
# Hyprland-focused live page suite can still exercise hyprkeys.py.
REWRITE_HYPRKEYS: bool = True


def _winproc():
    """agent/winproc.py: how a runner is asked to stop on Windows."""
    if os.name != "nt":
        return None
    import importlib.util
    spec = importlib.util.spec_from_file_location("longhand_winproc", REPO / "agent" / "winproc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


WINPROC = _winproc()
_T0 = time.monotonic()


def trace(what: str, command: list) -> None:
    """LONGHAND_HOST_TRACE=1: every process the page starts, and how it ends,
    on stderr with the second it happened."""
    if os.environ.get("LONGHAND_HOST_TRACE"):
        words = [os.path.basename(str(c)) if i == 0 else str(c)[:40] for i, c in enumerate(command[:7])]
        print(f"longhand-host {time.monotonic() - _T0:7.2f}s {what}: {' '.join(words)}", file=sys.stderr, flush=True)


def git_usr_bin() -> Path | None:
    git = shutil.which("git")
    if not git:
        return None
    root = Path(git).resolve().parent.parent
    for cand in (root / "usr" / "bin", root.parent / "usr" / "bin"):
        if (cand / "sh.exe").is_file():
            return cand
    return None


GIT_BIN = git_usr_bin() if os.name == "nt" else None


def python() -> str:
    """This Python, as a console program.

    Started by its launcher (`longhand.exe`) the host is pythonw.exe, which
    has no console. A script it started with pythonw had none either, and
    Windows then gives every console program *that* starts — Claude Code,
    Codex, gitleaks, pomo — a console window of its own, on screen: a black
    window for as long as a model thinks, and a run ended with it when the
    window is closed (found 2026-11-24, the first day opened from the
    launcher: the plan's run, "Claude Code exited 129"). Qt starts a console
    program from a window-less host with a console that has no window, and
    what that program starts shares it."""
    exe = Path(sys.executable)
    console = exe.with_name("python.exe")
    if exe.name.lower() == "pythonw.exe" and console.is_file():
        return str(console)
    return sys.executable


def resolve(argv: list[str]) -> tuple[str, list[str]]:
    """The program Windows can start for a command written for Linux."""
    head, rest = argv[0], argv[1:]
    if os.name != "nt":
        return head, rest
    if head in ("python3", "python"):
        if REWRITE_HYPRKEYS and rest and rest[0].replace("\\", "/").endswith("/plugin-page/hyprkeys.py"):
            # The keys sheet's six keys from anywhere: Windows keeps them
            # here, not Hyprland (winkeys.py answers in hyprkeys.py's words).
            return python(), [str(Path(__file__).resolve().parent / "winkeys.py"), *rest[1:]]
        return python(), rest
    if head == "sh" and len(rest) >= 3 and rest[0] == "-c" and "pw-play" in rest[1] and "paplay" in rest[1]:
        # A sound, as the page and the deadlines' popup play one (a tick):
        # a line of shell that asks PipeWire or PulseAudio, the file after it.
        # Windows plays it itself (play_sound.py), at the line's volume, and
        # not while Windows has notifications silenced (Do Not Disturb), as
        # the line asks the shell first.
        return python(), [str(Path(__file__).resolve().parent / "play_sound.py"), rest[2]]
    if head in SCRIPTS:
        head = str(SCRIPTS[head])
    if head in POSIX and GIT_BIN and (GIT_BIN / f"{head}.exe").is_file():
        return str(GIT_BIN / f"{head}.exe"), rest
    path = Path(head)
    if not path.is_file() and path.name in SCRIPTS and path.parent.name == "bin":
        # ~/.local/bin/<name>, where tools/install would have linked it.
        path = SCRIPTS[path.name]
    if not path.is_file():
        found = shutil.which(head)
        if not found:
            return head, rest
        path = Path(found)
    suffix = path.suffix.lower()
    if suffix in (".exe", ".com"):
        return str(path), rest
    if suffix in (".bat", ".cmd"):
        return str(path), rest          # through cmd.exe, as `prepare` writes its line
    try:
        with open(path, "rb") as f:
            first = f.readline(200).decode("utf-8", "replace")
    except OSError:
        first = ""
    if first.startswith("#!") and "python" in first or suffix == ".py":
        return python(), [str(path), *rest]
    if first.startswith("#!") and GIT_BIN:
        return str(GIT_BIN / "bash.exe"), [str(path), *rest]
    return str(path), rest


def _batch_word(word: str) -> str:
    """One word of a batch file's command line, as cmd.exe reads it back.

    cmd.exe reads `&|<>()^` as its own outside quotes, and `%NAME%` as a
    variable even inside them; the program the batch file hands its `%*` to
    reads `\\"` and `""` as a quote. So: in quotes, a quote doubled, the
    backslashes before a quote (and before the closing one) doubled, and `%`
    written as `%%cd:~,%`, which cmd.exe turns back into one `%` (Rust's
    standard library quotes for batch files the same way)."""
    if word and not any(c in word for c in ' \t"&|<>()^%!,;='):
        return word
    out, slashes = ['"'], 0
    for c in word:
        if c == "\\":
            slashes += 1
            continue
        if c == '"':
            out.append("\\" * (slashes * 2) + '""')
        else:
            out.append("\\" * slashes + ("%%cd:~,%" if c == "%" else c))
        slashes = 0
    out.append("\\" * (slashes * 2) + '"')
    return "".join(out)


def batch_line(program: str, args: list[str]) -> str:
    """cmd.exe's arguments for running a batch file (.bat, .cmd) with
    `args`, each arriving whole. Starting `cmd.exe /c path args` as separate
    arguments did not: the quotes Qt put around a path with a space in it
    were taken off by cmd.exe again, and `&` in an argument began a second
    command. A line break cannot reach a batch file at all (cmd.exe ends the
    command there and drops the rest): ValueError, rather than half of it."""
    for a in args:
        if any(c in a for c in "\r\n\0"):
            raise ValueError(f"{Path(program).name} is a batch file, and cmd.exe cannot hand it an argument "
                             "with a line break; point the config at the program it starts instead")
    words = " ".join(_batch_word(w) for w in [program, *args])
    return f'/e:ON /v:OFF /d /s /c "{words}"'


def prepare(p: QProcess, program: str, args: list[str]) -> str:
    """`program` and `args` (as `resolve` gives them) set on `p`, to be
    started; a batch file through cmd.exe, with its line written here
    (`batch_line`). Returns why it cannot start, or ""."""
    if os.name == "nt" and Path(program).suffix.lower() in (".bat", ".cmd"):
        try:
            line = batch_line(program, args)
        except ValueError as e:
            return str(e)
        p.setProgram(os.environ.get("COMSPEC") or "cmd.exe")
        p.setArguments([])
        p.setNativeArguments(line)
        return ""
    p.setProgram(program)
    p.setArguments(args)
    return ""


def start_detached(argv: list[str]) -> bool:
    """A command started and let go of, as `resolve` and `prepare` start it."""
    program, args = resolve(argv)
    p = QProcess()
    why = prepare(p, program, args)
    if why:
        print("longhand-host: could not start", argv[:4], why, file=sys.stderr)
        return False
    got = p.startDetached()
    return bool(got[0] if isinstance(got, tuple) else got)


def child_environment(extra: dict | None = None) -> QProcessEnvironment:
    env = QProcessEnvironment.systemEnvironment()
    if os.name == "nt":
        # Python children write UTF-8, whatever the console's code page.
        env.insert("PYTHONUTF8", "1")
        env.insert("PYTHONIOENCODING", "utf-8")
        shim = Path(__file__).resolve().parent / "pyshim"
        old = env.value("PYTHONPATH", "")
        have = {os.path.normcase(os.path.normpath(p)) for p in old.split(os.pathsep) if p}
        # Already on the path, it stays where it is: the tests put their own
        # sitecustomize (tests/windows/, which loads this one's halves and
        # starts their `#!` stand-ins) before it, and Python loads only the
        # first it finds.
        if shim.is_dir() and os.path.normcase(os.path.normpath(str(shim))) not in have:
            env.insert("PYTHONPATH", str(shim) + (os.pathsep + old if old else ""))
        front = [str(Path(sys.executable).parent), str(REPO / "cli"), str(REPO / "agent")]
        if GIT_BIN:
            front.append(str(GIT_BIN))
        env.insert("PATH", os.pathsep.join(front) + os.pathsep + env.value("PATH", ""))
    for k, v in (extra or {}).items():
        if v is None:
            env.remove(str(k))
        else:
            env.insert(str(k), str(v))
    return env


class _Parser(QObject):
    def begin(self) -> None: ...
    def feed(self, data: bytes) -> None: ...
    def finish(self) -> None: ...


@QmlElement
class StdioCollector(_Parser):
    textChanged = Signal()
    waitForEndChanged = Signal()
    streamFinished = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._buf = bytearray()
        self._text = ""
        self._wait = True

    def begin(self):
        self._buf.clear()

    def feed(self, data):
        self._buf += data
        if not self._wait:
            self._publish()

    def finish(self):
        self._publish()
        self.streamFinished.emit()

    def _publish(self):
        # Children here write text; a Windows child ends its lines \r\n.
        t = bytes(self._buf).decode("utf-8", "replace").replace("\r\n", "\n")
        if t != self._text:
            self._text = t
            self.textChanged.emit()

    def _get_text(self):
        return self._text

    def _get_wait(self):
        return self._wait

    def _set_wait(self, v):
        if v != self._wait:
            self._wait = bool(v)
            self.waitForEndChanged.emit()

    text = Property(str, _get_text, notify=textChanged)
    data = Property(str, _get_text, notify=textChanged)
    waitForEnd = Property(bool, _get_wait, _set_wait, notify=waitForEndChanged)


@QmlElement
class SplitParser(_Parser):
    splitMarkerChanged = Signal()
    read = Signal(str, arguments=["data"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._buf = bytearray()
        self._marker = "\n"

    def begin(self):
        self._buf.clear()

    def feed(self, data):
        self._buf += data
        marker = self._marker.encode("utf-8")
        if not marker:
            self.read.emit(bytes(self._buf).decode("utf-8", "replace"))
            self._buf.clear()
            return
        while True:
            i = self._buf.find(marker)
            if i < 0:
                break
            chunk = bytes(self._buf[:i])
            del self._buf[: i + len(marker)]
            if marker == b"\n" and chunk.endswith(b"\r"):
                chunk = chunk[:-1]
            self.read.emit(chunk.decode("utf-8", "replace"))

    def finish(self):
        if self._buf:
            self.read.emit(bytes(self._buf).decode("utf-8", "replace"))
            self._buf.clear()

    def _get_marker(self):
        return self._marker

    def _set_marker(self, v):
        if v != self._marker:
            self._marker = v
            self.splitMarkerChanged.emit()

    splitMarker = Property(str, _get_marker, _set_marker, notify=splitMarkerChanged)


@QmlElement
class Process(QObject):
    commandChanged = Signal()
    runningChanged = Signal()
    stdoutChanged = Signal()
    stderrChanged = Signal()
    stdinEnabledChanged = Signal()
    environmentChanged = Signal()
    workingDirectoryChanged = Signal()
    clearEnvironmentChanged = Signal()
    processIdChanged = Signal()
    started = Signal()
    exited = Signal(int, int, arguments=["exitCode", "exitStatus"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._command = []
        self._wanted = False     # what `running` was last set to
        self._proc = None
        self._stopping = False   # `running = false` asked, the process not ended yet
        self._stdout = None
        self._stderr = None
        self._stdin = False
        self._env = {}
        self._cwd = ""
        self._clear = False
        self._stop_name, self._stop_handle, self._started_at = "", 0, 0.0

    # --- properties
    def _get_command(self):
        return self._command

    def _set_command(self, v):
        v = [str(x) for x in (v or [])]
        if v != self._command:
            self._command = v
            self.commandChanged.emit()

    def _get_running(self):
        return self._wanted or self._proc is not None

    def _set_running(self, v):
        v = bool(v)
        if v:
            if self._proc is not None and self._stopping:
                # As Quickshell (asked on Omarchy, 2026-11-24): `running =
                # false` then `true` while the old process is still ending
                # starts the command (a new one, maybe) once it has ended.
                # The page leaves Hyprland's submap that way (hyprListen),
                # and the host dropped it, leaving the submap on.
                self._wanted = True
            elif self._proc is None and not self._wanted:
                self._wanted = True
                # A tick later: a `running: true` written before `command:`
                # in the same object must not start an empty command.
                #
                # Posted to a declared slot, not a timer connected to
                # `self._launch`: on a Process the page gives a property of
                # its own (`runner`, with `said`) such a connection never
                # fired — QML's object stands where PySide hung the bound
                # method, as far as could be told — and the agent's run was
                # never started, the page waiting on it for good.
                QMetaObject.invokeMethod(self, "_launch", Qt.ConnectionType.QueuedConnection)
                self.runningChanged.emit()
        else:
            was = self._get_running()
            self._wanted = False
            if self._proc is not None:
                self._stopping = True
                self._end_tree(self._proc)
            elif was:
                self.runningChanged.emit()

    def _get_stdout(self):
        return self._stdout

    def _set_stdout(self, v):
        self._stdout = v
        self.stdoutChanged.emit()

    def _get_stderr(self):
        return self._stderr

    def _set_stderr(self, v):
        self._stderr = v
        self.stderrChanged.emit()

    def _get_stdin(self):
        return self._stdin

    def _set_stdin(self, v):
        self._stdin = bool(v)
        self.stdinEnabledChanged.emit()
        if not self._stdin and self._proc is not None:
            self._proc.closeWriteChannel()

    def _get_env(self):
        return self._env

    def _set_env(self, v):
        self._env = dict(v or {})
        self.environmentChanged.emit()

    def _get_cwd(self):
        return self._cwd

    def _set_cwd(self, v):
        self._cwd = str(v or "")
        self.workingDirectoryChanged.emit()

    def _get_clear(self):
        return self._clear

    def _set_clear(self, v):
        self._clear = bool(v)
        self.clearEnvironmentChanged.emit()

    def _get_pid(self):
        return int(self._proc.processId()) if self._proc is not None else 0

    command = Property("QVariantList", _get_command, _set_command, notify=commandChanged)
    running = Property(bool, _get_running, _set_running, notify=runningChanged)
    stdout = Property(QObject, _get_stdout, _set_stdout, notify=stdoutChanged)
    stderr = Property(QObject, _get_stderr, _set_stderr, notify=stderrChanged)
    stdinEnabled = Property(bool, _get_stdin, _set_stdin, notify=stdinEnabledChanged)
    environment = Property("QVariantMap", _get_env, _set_env, notify=environmentChanged)
    workingDirectory = Property(str, _get_cwd, _set_cwd, notify=workingDirectoryChanged)
    clearEnvironment = Property(bool, _get_clear, _set_clear, notify=clearEnvironmentChanged)
    processId = Property(int, _get_pid, notify=processIdChanged)

    # --- running one
    @Slot()
    def _launch(self):
        if not self._wanted or self._proc is not None:
            return
        self._wanted = False
        if not self._command:
            self.runningChanged.emit()
            return
        if os.name == "nt" and self._command[0] in INSIDE:
            self._answer(INSIDE[self._command[0]])
            return
        program, args = resolve(self._command)
        p = QProcess(self)
        extra = dict(self._env)
        if WINPROC:
            # The event `signal` sets to ask a runner to stop (agent/winproc.py).
            self._close_stop()
            self._stop_name, self._stop_handle = WINPROC.new_stop()
            self._started_at = time.monotonic()
            extra[WINPROC.STOP_ENV] = self._stop_name
        p.setProcessEnvironment(child_environment(extra))
        if self._cwd:
            p.setWorkingDirectory(self._cwd)
        for parser in (self._stdout, self._stderr):
            if isinstance(parser, _Parser):
                parser.begin()
        p.readyReadStandardOutput.connect(lambda: self._drain(p))
        p.readyReadStandardError.connect(lambda: self._drain(p))
        p.started.connect(lambda: self._on_started(p))
        p.finished.connect(lambda code, status: self._on_finished(p, code, status))
        p.errorOccurred.connect(lambda err: self._on_error(p, err))
        self._proc = p
        trace("start", self._command)
        why = prepare(p, program, args)
        if why:
            LOG.append("could not start: " + why)
            QTimer.singleShot(0, lambda: self._on_error(p, QProcess.ProcessError.FailedToStart))
            return
        p.start()

    def _answer(self, inside):
        """A command the host answers itself: started, said, ended, as a
        process would be, with nothing started."""
        trace("inside", self._command)
        try:
            code, out, err = inside(self._command[1:])
        except Exception as e:  # noqa: BLE001 — a fault here is the command's failure, not the host's
            code, out, err = 1, "", f"{self._command[0]}: {e}\n"
        for parser in (self._stdout, self._stderr):
            if isinstance(parser, _Parser):
                parser.begin()
        self.started.emit()
        if out and isinstance(self._stdout, _Parser):
            self._stdout.feed(out.encode("utf-8"))
        if err and isinstance(self._stderr, _Parser):
            self._stderr.feed(err.encode("utf-8"))
        for parser in (self._stdout, self._stderr):
            if isinstance(parser, _Parser):
                parser.finish()
        trace(f"exit {code}", self._command)
        self.exited.emit(code, 0)
        self.runningChanged.emit()

    def _on_started(self, p):
        if p is not self._proc:
            return
        if not self._stdin:
            p.closeWriteChannel()
        self.started.emit()
        self.processIdChanged.emit()

    def _drain(self, p):
        if p is not self._proc:
            return
        try:
            out = bytes(p.readAllStandardOutput())
            err = bytes(p.readAllStandardError())
        except RuntimeError:
            return      # the host is closing: Qt has the process back already
        if out and isinstance(self._stdout, _Parser):
            self._stdout.feed(out)
        if err and isinstance(self._stderr, _Parser):
            self._stderr.feed(err)

    def _end(self, p, code, status):
        self._drain(p)
        # As Quickshell: by the time `streamFinished` and `exited` are heard,
        # `running` reads false, and `running = true` there starts the
        # process again (seen on Omarchy, 2026-11-24). The page asks for its
        # next check from the last one's streamFinished (`checkDone`); with
        # the process still counted as running, that start was dropped and
        # the page waited eight seconds for a check that never ran.
        trace(f"exit {code}", self._command)
        again = self._stopping       # stopped, and maybe started again before it ended
        self._proc = None
        self._stopping = False
        self._close_stop()
        for parser in (self._stdout, self._stderr):
            if isinstance(parser, _Parser):
                parser.finish()
        self.exited.emit(code, status)
        self.runningChanged.emit()
        self.processIdChanged.emit()
        p.deleteLater()
        if again and self._wanted:        # started again while it was ending (`_set_running`)
            QMetaObject.invokeMethod(self, "_launch", Qt.ConnectionType.QueuedConnection)

    def _on_finished(self, p, code, status):
        if p is self._proc:
            try:
                self._end(p, int(code), 0 if status == QProcess.ExitStatus.NormalExit else 1)
            except RuntimeError:
                pass    # the host is closing and Qt has taken the process back already

    def _on_error(self, p, err):
        if p is self._proc and err == QProcess.ProcessError.FailedToStart:
            LOG.append("could not start: " + " ".join(self._command[:4]))
            print("longhand-host: could not start", self._command[:4], file=sys.stderr)
            self._end(p, 127, 1)

    def _close_stop(self):
        if WINPROC and self._stop_handle:
            WINPROC.close(self._stop_handle)
        self._stop_name, self._stop_handle = "", 0

    def _end_tree(self, p):
        """The process and what it started, outright."""
        if p is not self._proc:
            return
        pid = int(p.processId())
        if os.name == "nt" and pid:
            kill = QProcess()
            kill.setProgram("taskkill")
            kill.setArguments(["/T", "/F", "/PID", str(pid)])
            kill.setStandardOutputFile(QProcess.nullDevice())
            kill.setStandardErrorFile(QProcess.nullDevice())
            kill.startDetached()
        else:
            p.kill()

    @Slot(int)
    def signal(self, signum):
        """SIGTERM, as the page sends it to stop a run. On Windows no process
        can take a signal and go on, so a runner is asked through its event
        and ends the model itself, as it does on SIGTERM (agent/winproc.py).
        What is not a runner — it never says it listens — is ended outright:
        at once when it has been up a while, and when it has only just
        started, after the moment a runner needs to get as far as listening."""
        p = self._proc
        if p is None:
            return
        if not WINPROC:
            if os.name == "nt":
                p.kill()
            else:
                os.kill(p.processId(), signum)
            return
        name = self._stop_name
        WINPROC.ask_stop(name)

        def settle(tries=0):
            if p is not self._proc:
                return                                      # it ended
            if WINPROC.listening(name):
                if tries >= 50:                             # heard, and ten seconds on still there
                    self._end_tree(p)
                else:
                    QTimer.singleShot(200, lambda: settle(tries + 1))
            elif time.monotonic() - self._started_at < 3.0:
                QTimer.singleShot(200, lambda: settle(tries))
            else:
                self._end_tree(p)
        settle()

    @Slot(str)
    def write(self, data):
        if self._proc is not None:
            self._proc.write(data.encode("utf-8"))

    @Slot("QVariant")
    def exec(self, what):
        if isinstance(what, dict):
            what = what.get("command", [])
        self._set_running(False)
        self._set_command(what)
        self._set_running(True)

    @Slot()
    def startDetached(self):
        if self._command:
            start_detached(self._command)


@QmlElement
@QmlSingleton
class FileViewError(QObject):
    @QEnum
    class Enum(IntEnum):
        Success = 0
        Unknown = 1
        FileNotFound = 2
        PermissionDenied = 3
        NotAFile = 4

    @Slot(int, result=str)
    def toString(self, e):
        return {0: "Success", 1: "Unknown Error", 2: "File Not Found",
                3: "Permission Denied", 4: "Not A File"}.get(int(e), "Unknown Error")


def local_path(p: str) -> str:
    p = str(p or "")
    if p.startswith("file:"):
        return QUrl(p).toLocalFile()
    return p


@QmlElement
class FileView(QObject):
    pathChanged = Signal()
    preloadChanged = Signal()
    blockLoadingChanged = Signal()
    blockAllReadsChanged = Signal()
    blockWritesChanged = Signal()
    printErrorsChanged = Signal()
    atomicWritesChanged = Signal()
    watchChangesChanged = Signal()
    textChanged = Signal()
    loadedSignal = Signal(name="loaded")
    loadFailed = Signal(int, arguments=["error"])
    saved = Signal()
    saveFailed = Signal(int, arguments=["error"])
    fileChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._path = ""
        self._text = None        # what the file holds, as far as is known
        self._preload = True
        self._block_loading = False
        self._block_reads = False
        self._block_writes = False
        self._print = True
        self._atomic = True
        self._watch = False
        self._ops = deque()      # ("load",) | ("write", path, text): one a tick, in order
        self._sig = None         # the file's (mtime, size) when last read or written here
        self._posted = False
        self._watcher = None
        self._poll = None

    # --- properties
    def _get_path(self):
        return self._path

    def _set_path(self, v):
        v = local_path(v)
        if v == self._path:
            return
        self._path = v
        self._text = None
        self._sig = None
        self.pathChanged.emit()
        self._rewatch()
        if self._path and self._preload:
            self._queue(("load",))

    def _flag(name, signal_name):
        def get(self):
            return getattr(self, name)

        def put(self, v):
            if bool(v) != getattr(self, name):
                setattr(self, name, bool(v))
                getattr(self, signal_name).emit()
                if name == "_watch":
                    self._rewatch()
        return get, put

    path = Property(str, _get_path, _set_path, notify=pathChanged)
    preload = Property(bool, *_flag("_preload", "preloadChanged"), notify=preloadChanged)
    blockLoading = Property(bool, *_flag("_block_loading", "blockLoadingChanged"), notify=blockLoadingChanged)
    blockAllReads = Property(bool, *_flag("_block_reads", "blockAllReadsChanged"), notify=blockAllReadsChanged)
    blockWrites = Property(bool, *_flag("_block_writes", "blockWritesChanged"), notify=blockWritesChanged)
    printErrors = Property(bool, *_flag("_print", "printErrorsChanged"), notify=printErrorsChanged)
    atomicWrites = Property(bool, *_flag("_atomic", "atomicWritesChanged"), notify=atomicWritesChanged)
    watchChanges = Property(bool, *_flag("_watch", "watchChangesChanged"), notify=watchChangesChanged)

    # --- the queue: one job a tick, in the order asked
    # Posted, not timed: a job asked for now is heard before anything the
    # page puts off with Qt.callLater afterwards, as Quickshell's read on a
    # thread mostly is; a zero timer came after it. Not always, here or
    # there: a callLater made earlier in the same turn runs first, and the
    # page puts its later ones in with it. So the note does not count on it
    # for the keys (NoteEditor.focusNote owes them until its lines come).
    def _queue(self, op):
        self._ops.append(op)
        self._post()

    def _post(self):
        if not self._posted:
            self._posted = True
            QMetaObject.invokeMethod(self, "_step", Qt.ConnectionType.QueuedConnection)

    @Slot()
    def _step(self):
        self._posted = False
        if not self._ops:
            return
        op = self._ops.popleft()
        if self._ops:
            self._post()
        if op[0] == "load":
            self._load(announce=True)
        else:
            self._write(op[1], op[2])

    def _stat(self, path=None):
        try:
            st = os.stat(path or self._path)
            return (st.st_mtime_ns, st.st_size)
        except OSError:
            return None

    def _read(self):
        """(text, error): the file as it is, never translated."""
        if not self._path:
            return None, FileViewError.Enum.FileNotFound
        if os.name == "nt" and self._path.replace("\\", "/").endswith(palette.SUFFIX) and not os.path.exists(self._path):
            return palette.colors_toml(), FileViewError.Enum.Success     # Windows' own palette, under the theme's name
        for wait in (0.01, 0.02, 0.05, None):
            try:
                if os.path.isdir(self._path):
                    return None, FileViewError.Enum.NotAFile
                with open(self._path, "rb") as f:
                    raw = f.read()
                return raw.decode("utf-8", "replace"), FileViewError.Enum.Success
            except FileNotFoundError:
                return None, FileViewError.Enum.FileNotFound
            except PermissionError:
                if os.name != "nt" or wait is None:
                    return None, FileViewError.Enum.PermissionDenied
                time.sleep(wait)
            except OSError:
                return None, FileViewError.Enum.Unknown

    def _load(self, announce):
        text, err = self._read()
        if text is None:
            self._sig = None
            self._text = None
            if announce:
                self.loadFailed.emit(int(err))
            return False
        self._sig = self._stat()
        self._text = text
        if announce:
            self.textChanged.emit()
            self.loadedSignal.emit()
        return True

    def _write(self, path, text):
        data = text.encode("utf-8")
        try:
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            if self._atomic:
                tmp = f"{path}.{os.getpid()}.tmp"
                with open(tmp, "wb") as f:
                    f.write(data)
                    f.flush()
                    os.fsync(f.fileno())
                # Windows refuses the rename while another program holds the
                # file open (a sync tool, an editor): a few tries, briefly.
                replace(tmp, path, BRIEF)
            else:
                with open(path, "wb") as f:
                    f.write(data)
        except PermissionError:
            self.saveFailed.emit(int(FileViewError.Enum.PermissionDenied))
            return
        except OSError:
            self.saveFailed.emit(int(FileViewError.Enum.Unknown))
            return
        if path == self._path:
            self._sig = self._stat()
            self._rewatch()
        self.saved.emit()

    # --- what the page calls
    @Slot(result=str)
    def text(self):
        if self._text is None and self._path and (self._block_loading or self._block_reads):
            self._load(announce=False)
        return self._text or ""

    @Slot(result=str)
    def data(self):
        return self.text()

    @Slot()
    def reload(self):
        if self._path:
            self._queue(("load",))

    @Slot(str)
    def setText(self, text):
        if not self._path:
            return
        if self._text == text:
            return           # the file holds exactly this: nothing written, nothing said
        self._text = text
        self.textChanged.emit()
        self._queue(("write", self._path, text))

    @Slot(str)
    def setData(self, data):
        self.setText(data)

    @Slot()
    def waitForJob(self):
        while self._ops:
            self._step()

    # --- watching
    def _rewatch(self):
        if self._watcher is not None:
            old = self._watcher.files() + self._watcher.directories()
            if old:
                self._watcher.removePaths(old)
        if not (self._watch and self._path):
            if self._poll is not None:
                self._poll.stop()
            return
        if self._watcher is None:
            self._watcher = QFileSystemWatcher(self)
            # Through a lambda, not the bound method: see Process._set_running.
            self._watcher.fileChanged.connect(lambda where: self._changed(where))
            self._watcher.directoryChanged.connect(lambda where: self._changed(where))
        self._take_up()
        if os.name == "nt":
            # Windows' FindFirstChangeNotification can drop an os.replace that
            # lands right after a sibling mkstemp while Qt re-arms the watch
            # (2026-11-24: pomo wrote done to deadlines.tsv while FileView
            # stayed deaf). A lightweight stat check catches any dropped event.
            if self._poll is None:
                self._poll = QTimer(self)
                self._poll.setInterval(500)
                self._poll.timeout.connect(lambda: self._changed(self._path))
            if not self._poll.isActive():
                self._poll.start()

    def _take_up(self):
        """Watch the file, and its folder for the day it is made or replaced.
        On a first run the folder is not there either (the timer's state,
        before `pomo` has ever run): then the nearest folder above that is,
        until it comes — or a bar would stay deaf to the file for good."""
        if self._watcher is None:
            return
        folder = os.path.dirname(self._path)
        while folder and not os.path.isdir(folder):
            above = os.path.dirname(folder)
            if above == folder:
                break
            folder = above
        want = ([folder] if os.path.isdir(folder) else []) + ([self._path] if os.path.isfile(self._path) else [])
        have = {os.path.normcase(os.path.normpath(p)) for p in self._watcher.files() + self._watcher.directories()}
        for p in want:
            if os.path.normcase(os.path.normpath(p)) not in have:
                self._watcher.addPath(p)

    def _changed(self, _where):
        now = self._stat()
        # A file replaced by a rename drops out of the watch, and a folder
        # that was missing may be there now: take them up again.
        self._take_up()
        if now != self._sig:
            self._sig = now
            self.fileChanged.emit()


@QmlElement
class IpcHandler(QObject):
    """Quickshell.Io.IpcHandler stand-in: holds declared QML methods under
    `target` so tests/page/qt_host.py can drive tests/page/harness.qml."""
    targetChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._target = ""

    def _get_target(self):
        return self._target

    def _set_target(self, v):
        v = str(v or "")
        if v != self._target:
            self._target = v
            self.targetChanged.emit()

    target = Property(str, _get_target, _set_target, notify=targetChanged)
