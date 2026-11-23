#!/usr/bin/env python3
"""qmltestrunner, where Qt came with PySide6 and has none: one tst_*.qml,
run by Qt Quick Test from Python.

Qt's own report does not reach a redirected stdout on Windows, so it is
written to a file of the run's own and said from there.

Run: python tests/windows/qmltest.py -input tests/tst_dates.qml
"""
import os
import sys
import tempfile
from pathlib import Path

from PySide6.QtQuickTest import QUICK_TEST_MAIN


def main() -> int:
    argv = list(sys.argv)
    here = Path(argv[argv.index("-input") + 1]).resolve().parent if "-input" in argv else Path.cwd()
    fd, log = tempfile.mkstemp(prefix="qmltest-", suffix=".txt")
    os.close(fd)
    try:
        code = QUICK_TEST_MAIN("longhand", argv + ["-o", log + ",txt"], str(here))
        sys.stdout.buffer.write(Path(log).read_bytes())
        sys.stdout.buffer.flush()
    finally:
        try:
            os.unlink(log)
        except OSError:
            pass
    return code


if __name__ == "__main__":
    sys.exit(main())
