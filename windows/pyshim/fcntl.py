"""fcntl.flock on Windows, as far as Longhand's lock files need it (spike).

The agent, the planner and longhand-check take a whole-file lock around a
read-change-write. Windows locks byte ranges, and its locks are mandatory:
a locked byte cannot be read by another handle. So the lock is taken on one
byte far past the end of any real file, which nothing reads, and the file's
own position is left where it was.
"""
import msvcrt
import os
import time

LOCK_SH = 1
LOCK_EX = 2
LOCK_NB = 4
LOCK_UN = 8

_FAR = 1 << 30


def flock(fd, operation):
    if hasattr(fd, "fileno"):
        fd = fd.fileno()
    here = os.lseek(fd, 0, os.SEEK_CUR)
    try:
        if operation & LOCK_UN:
            os.lseek(fd, _FAR, os.SEEK_SET)
            try:
                msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
            return
        while True:
            os.lseek(fd, _FAR, os.SEEK_SET)
            try:
                msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
                return
            except OSError:
                if operation & LOCK_NB:
                    raise BlockingIOError("the file is locked") from None
                time.sleep(0.05)
    finally:
        os.lseek(fd, here, os.SEEK_SET)
