"""Windows only: a file is replaced even while someone is reading it.

Longhand writes its files whole, to a temporary file beside them, and moves
that over the old one with `os.replace`: whoever reads sees the old file or
the new, never half of one. On Linux the move always succeeds. On Windows it
fails (WinError 5, access denied; or 32, in use) while another process holds
the old file open, and here something nearly always does for a moment: the
page's FileView rereads a file as soon as it changes, `longhand-check` reads
the ledger and the day's note, Syncthing reads what changed to send it. A
moment later the move goes through.

Found first in `pomo` (2026-11-24: a tick was lost while the popup's
`longhand-check` read the store); the agent, the reader, the plan, the
documents and the keys sheet replace the same way and could lose a write
the same way. `install()`, called once at start by every Python Longhand
starts (pyshim/sitecustomize.py; the launchers and the tests call it too),
makes every `os.replace`, and so every `Path.replace`, try again for about
three seconds before it gives up, as `pomo` does. Anything but "in use" or
"access denied" is raised at once, and so is the last try's.

The page's host is not given it: it draws the page, and three seconds
there is a frozen window. It calls `replace(..., BRIEF)` where it replaces
a file itself, as it did before.
"""
import os
import time

# The system's own, even when this is imported again under another name
# after install() (the host imports it as pyshim.longhand_replace).
_replace = getattr(os.replace, "__wrapped__", os.replace)
PATIENT = (0.02, 0.05, 0.1, 0.2, 0.4, 0.8, 1.6)    # about three seconds, as pomo
BRIEF = (0.02,) * 7                                   # the host's: well under a frame's worth of waiting each


def replace(src, dst, waits=PATIENT, *, src_dir_fd=None, dst_dir_fd=None):
    """os.replace, tried again after each of `waits` (seconds) while
    Windows says another process holds the file."""
    if os.name == "nt":
        for wait in waits:
            try:
                return _replace(src, dst, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)
            except PermissionError:
                time.sleep(wait)
    return _replace(src, dst, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)


def _patient(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
    return replace(src, dst, PATIENT, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)


_patient.__doc__ = _replace.__doc__
_patient.__wrapped__ = _replace


def install() -> None:
    """On Windows, every os.replace from here on is the patient one."""
    if os.name == "nt" and not hasattr(os.replace, "__wrapped__"):
        os.replace = _patient
