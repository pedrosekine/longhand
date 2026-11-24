"""Stopping a model's run on Windows: what a process group and SIGTERM are
to the runner on Linux (longhand-agent, "Stopping a run").

Linux: the model's process is started in a session of its own, so its whole
group can be ended with one `killpg`; and the page stops the runner with
SIGTERM, which the runner handles — it ends the group, logs the run as
stopped, and writes no turn.

Windows has neither, so:

- the model's process is put in a *job* of its own (`adopt`). Everything it
  starts is in the job too, and `end` ends the job whole. The job is also
  set to end when its handle closes, so a runner that is killed outright
  takes the model with it instead of leaving it running;
- there is no signal a process can handle and go on. The runner waits on a
  named *event* instead (`listen_for_stop`); whoever started it gave it the
  name in LONGHAND_STOP_EVENT, and asks it to stop by setting the event
  (`ask_stop`). Asked that way, the runner does what its SIGTERM handler
  does. A process that listens to no event can only be ended outright.

Imported on Windows only.
"""
from __future__ import annotations

import ctypes
import os
import subprocess
import threading
import uuid
from ctypes import wintypes

STOP_ENV = "LONGHAND_STOP_EVENT"

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
HANDLE = ctypes.c_void_p
for name, result, args in (
        ("CreateJobObjectW", HANDLE, (ctypes.c_void_p, wintypes.LPCWSTR)),
        ("SetInformationJobObject", wintypes.BOOL, (HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD)),
        ("AssignProcessToJobObject", wintypes.BOOL, (HANDLE, HANDLE)),
        ("TerminateJobObject", wintypes.BOOL, (HANDLE, wintypes.UINT)),
        ("OpenProcess", HANDLE, (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)),
        ("CloseHandle", wintypes.BOOL, (HANDLE,)),
        ("CreateEventW", HANDLE, (ctypes.c_void_p, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR)),
        ("OpenEventW", HANDLE, (wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR)),
        ("SetEvent", wintypes.BOOL, (HANDLE,)),
        ("WaitForSingleObject", wintypes.DWORD, (HANDLE, wintypes.DWORD))):
    fn = getattr(k32, name)
    fn.restype, fn.argtypes = result, args


class _BasicLimits(ctypes.Structure):
    _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64), ("PerJobUserTimeLimit", ctypes.c_int64),
                ("LimitFlags", wintypes.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD), ("SchedulingClass", wintypes.DWORD)]


class _IoCounters(ctypes.Structure):
    _fields_ = [(n, ctypes.c_uint64) for n in ("ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
                                               "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


class _ExtendedLimits(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", _BasicLimits), ("IoInfo", _IoCounters), ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t), ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t)]


KILL_ON_JOB_CLOSE = 0x2000
EXTENDED_LIMITS = 9
_jobs: dict[int, int] = {}          # a child's pid -> its job
_lock = threading.Lock()


def adopt(p: subprocess.Popen) -> None:
    """A process just started, put in a job of its own: it and whatever it
    starts can be ended together."""
    job = k32.CreateJobObjectW(None, None)
    if not job:
        return
    limits = _ExtendedLimits()
    limits.BasicLimitInformation.LimitFlags = KILL_ON_JOB_CLOSE
    k32.SetInformationJobObject(job, EXTENDED_LIMITS, ctypes.byref(limits), ctypes.sizeof(limits))
    process = k32.OpenProcess(0x0100 | 0x0001, False, p.pid)           # set quota, terminate
    assigned = bool(process) and bool(k32.AssignProcessToJobObject(job, process))
    if process:
        k32.CloseHandle(process)
    if not assigned:
        k32.CloseHandle(job)
        return
    with _lock:
        _jobs[p.pid] = job


def end(p: subprocess.Popen) -> None:
    """The process and everything it started, ended now."""
    with _lock:
        job = _jobs.get(p.pid)
    if job and k32.TerminateJobObject(job, 1):
        return
    try:        # no job (it could not be made): the tree, as far as it can still be walked
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)], capture_output=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        pass
    if p.poll() is None:
        try:
            p.kill()
        except OSError:
            pass


def release(p: subprocess.Popen) -> None:
    """The run is over: let go of its job (which ends anything it left)."""
    with _lock:
        job = _jobs.pop(p.pid, None)
    if job:
        k32.CloseHandle(job)


def new_stop() -> tuple[str, int]:
    """For whoever starts a process it may want to stop: an event made now,
    so a stop asked before the process has got as far as listening is still
    heard, and its name, to put in the process's LONGHAND_STOP_EVENT. Keep
    the handle while the process lives; `close` it after."""
    name = "Local\\longhand-stop-" + uuid.uuid4().hex
    return name, k32.CreateEventW(None, True, False, name) or 0


def close(handle: int) -> None:
    if handle:
        k32.CloseHandle(handle)


def listen_for_stop(callback) -> bool:
    """Wait, beside the work, for whoever started this process to ask it to
    stop; then `callback()`, from the waiting thread. A second event,
    "<name>-on", says that someone is listening: a process that is not a
    runner never makes it, and can only be ended outright. False when nobody
    gave this process a name to wait on."""
    name = os.environ.get(STOP_ENV, "")
    if not name:
        return False
    event = k32.CreateEventW(None, True, False, name)
    if not event:
        return False
    k32.CreateEventW(None, True, True, name + "-on")         # kept open as long as this process lives

    def wait() -> None:
        if k32.WaitForSingleObject(event, 0xFFFFFFFF) == 0:
            callback()

    threading.Thread(target=wait, daemon=True, name="longhand-stop").start()
    return True


def listening(name: str) -> bool:
    """Whether the process given `name` is a runner waiting on it."""
    if not name:
        return False
    marker = k32.OpenEventW(0x0002, False, name + "-on")
    if marker:
        k32.CloseHandle(marker)
    return bool(marker)


def ask_stop(name: str) -> bool:
    """Set the event: the runner waiting on it stops as on SIGTERM. True
    when there was an event to set (whether anyone listens: `listening`)."""
    if not name:
        return False
    event = k32.OpenEventW(0x0002, False, name)             # modify state
    if not event:
        return False
    try:
        return bool(k32.SetEvent(event))
    finally:
        k32.CloseHandle(event)
