"""Windows only: a line appended to a file is appended whole.

Longhand keeps its logs by appending a line at a time: the ledger
(`ledger.tsv`), feedback, each machine's conversation, deadlines and
proposals (`<host>.jsonl`), the check-ins, the page's `usage.jsonl`. Runs
side by side append to the same file at once: the open pass, the plan and
a chat finishing together all write the ledger. On Linux a file opened for
appending is opened `O_APPEND`, and the system puts every write at the end
as it makes it. On Windows, Python's `open(..., "a")` is a seek to the end
and then a write: two processes seek to the same end, and the second
write lands over the first. Found 2026-11-25 in the page test's own log
("start plan" lost while runners started side by side, tests/page/run.py);
six processes appending 400 lines each kept 1998 of 2400 here, 23 of them
cut into one another.

Windows has the same promise as `O_APPEND`, asked for another way: a file
opened for appending only (`FILE_APPEND_DATA`, without the right to write
anywhere else) has every write put at the end by the system. `install()`,
called once at start by every Python Longhand starts (pyshim/
sitecustomize.py; the launchers and the tests call it too), opens every
file named for "a" (not "a+", which reads too) that way. Nothing else
about the file changes: the same handle Python would have, the same
errors, readers and `os.replace` beside it as before.
"""
import builtins
import functools
import io
import os

FILE_APPEND_DATA = 0x0004
FILE_READ_ATTRIBUTES = 0x0080       # Python asks what the file is (fstat) once it is open
SYNCHRONIZE = 0x00100000
SHARE_ALL = 0x7                     # read, write, delete: others read, append and replace beside it
OPEN_EXISTING, OPEN_ALWAYS = 3, 4
FILE_ATTRIBUTE_NORMAL = 0x80

_k32 = None


def _kernel32():
    global _k32
    if _k32 is None:
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.CreateFileW.restype = wintypes.HANDLE
        k32.CreateFileW.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                    wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE)
        k32.CloseHandle.argtypes = (wintypes.HANDLE,)
        _k32 = k32
    return _k32


def append_only(path, flags):
    """A descriptor on `path` opened for appending only: what `open`'s
    `opener=` is given. Raises what `open` would (FileNotFoundError,
    PermissionError, IsADirectoryError…)."""
    import ctypes
    import msvcrt
    k32 = _kernel32()
    name = os.fsdecode(path)
    how = OPEN_ALWAYS if flags & os.O_CREAT else OPEN_EXISTING
    h = k32.CreateFileW(name, FILE_APPEND_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE, SHARE_ALL, None, how,
                        FILE_ATTRIBUTE_NORMAL, None)
    if h is None or h == ctypes.c_void_p(-1).value:
        code = ctypes.get_last_error()
        raise OSError(None, ctypes.FormatError(code).strip(), name, code)
    try:
        return msvcrt.open_osfhandle(h, os.O_APPEND)
    except BaseException:
        k32.CloseHandle(h)
        raise


def _appends(file, mode, opener_given):
    return (opener_given is None and isinstance(mode, str) and "a" in mode and "+" not in mode
            and isinstance(file, (str, bytes, os.PathLike)))


def install() -> None:
    """On Windows, every file opened for "a" from here on appends whole."""
    if os.name != "nt" or getattr(io.open, "_longhand_append", False):
        return
    inner = io.open

    # Wrapping whatever `open` is by now (longhand_lf's, which ends lines
    # with "\n"), and looking like it, so that module still knows itself if
    # it is imported again.
    @functools.wraps(inner)
    def append_open(file, mode="r", buffering=-1, encoding=None, errors=None, newline=None, closefd=True,
                    opener=None):
        if _appends(file, mode, opener):
            opener = append_only
        return inner(file, mode, buffering, encoding, errors, newline, closefd, opener)

    append_open._longhand_append = True
    builtins.open = io.open = append_open
