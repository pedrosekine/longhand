#!/usr/bin/env python3
"""Every test file can run beside the others (tests/run_all.py runs them
side by side): what can be seen in the source, checked. A file writes only
into folders it made with tempfile, never a fixed /tmp path that another
file (or a second run) could share, never the home folder, never the repo.
A file that truly cannot run beside the others is listed in run_all.py's
SERIAL with its reason.

Run: python3 tests/test_parallel.py
"""
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# The live page test runs alone after the rest, so it may keep a fixed folder.
FILES = sorted(TESTS.glob("test_*.py")) + [TESTS / "fakes.py", TESTS / "fake_hyprctl.py", TESTS / "desktop.py"]

FIXED_TMP = re.compile(r"""["'](/tmp|/var/tmp)(/|["'])""")
HOME = re.compile(r"Path\.home\(|expanduser\(|environ\[[\"']HOME[\"']\]|getenv\([\"']HOME[\"']")
INTO_REPO = re.compile(r"\bROOT\b.*\.(write_text|write_bytes|mkdir|unlink|touch|rename|replace)\(|rmtree\(\s*ROOT\b")


def offenders(pattern: re.Pattern) -> list[str]:
    out = []
    for f in FILES:
        for n, line in enumerate(f.read_text().splitlines(), 1):
            code = line.split("#", 1)[0]
            if pattern.search(code):
                out.append(f"{f.name}:{n}")
    return out


def main() -> int:
    bad = offenders(FIXED_TMP)
    check(not bad, f"no fixed /tmp path: each file makes its own with tempfile ({', '.join(bad)})")
    bad = offenders(HOME)
    check(not bad, f"nothing reads or writes the home folder: XDG_*_HOME point into the test's own ({', '.join(bad)})")
    bad = offenders(INTO_REPO)
    check(not bad, f"nothing is written into the repo, which every file shares ({', '.join(bad)})")

    spec = importlib.util.spec_from_file_location("run_all", TESTS / "run_all.py")
    run_all = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(run_all)
    names = {name for name, *_ in run_all.jobs()}
    check(all(n in names and why.strip() for n, why in run_all.SERIAL.items()),
          f"each file run alone is a real test, with its reason ({run_all.SERIAL})")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
