#!/usr/bin/env python3
"""cli/pomo.py (Python) says and leaves what cli/pomo (bash) does.

Two halves:

1. A phrase means to pomo.py's `read_date` what it means to GNU `date -d`:
   a corpus of phrases, each read by both at the same second.

2. The same commands, one after another, through both programs, each in a
   state folder of its own, with one clock for both: after every command
   their stdout, stderr and exit code are the same, and so are state.json,
   deadlines.tsv, deadlines.seq and pomo.log, byte for byte.

   The clock is pinned (LONGHAND_NOW) and moved by the test, so a session
   can run out in no time. The bash program takes the pinned clock from a
   `date` of the test's own, first on its PATH, which reads phrases with
   `read_date` — the reader half 1 holds to the real one.

Needs bash and its tools (sed, awk, sort); where there is no `flock` (Git
for Windows), a stand-in that always gets the lock. With no bash, or no GNU
date, that half says so and is skipped.

Run: python3 tests/test_pomo_port.py
"""
import datetime as dt
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASH_POMO = ROOT / "cli" / "pomo"
PY_POMO = ROOT / "cli" / "pomo.py"
failures = 0

spec = importlib.util.spec_from_file_location("pomo_py", PY_POMO)
pomo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pomo)


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def git_tools():
    """Git for Windows' usr/bin (bash, date, sed, awk), or None."""
    git = shutil.which("git")
    if not git:
        return None
    root = pathlib.Path(git).resolve().parent.parent
    for cand in (root / "usr" / "bin", root.parent / "usr" / "bin"):
        if (cand / "bash.exe").is_file():
            return cand
    return None


WINDOWS = os.name == "nt"
TOOLS = git_tools() if WINDOWS else None


def find(tool):
    if WINDOWS:
        return str(TOOLS / (tool + ".exe")) if TOOLS and (TOOLS / (tool + ".exe")).is_file() else None
    return shutil.which(tool)


# ------------------------------------------------------------ 1. phrases

DAYS = ["sun", "monday", "tue", "tues", "wednesday", "thu", "thurs", "friday", "sat"]
MONTHS = ["jan", "february", "mar", "apr.", "may", "june", "jul", "aug", "sept", "oct", "november", "dec"]
TIMES = ["17:00", "9:30", "5pm", "5 pm", "12am", "12pm", "9:30am", "23:59", "17:00:30", "1700", "17"]
RELS = ["tomorrow", "yesterday", "today", "now", "next week", "last week", "next month", "next year", "3 days",
        "3 days ago", "2 weeks", "1 month", "2 months ago", "fortnight", "week", "3 hours", "30 min", "1 hour ago",
        "+2 days", "-1 week"]
DATES = ["2026-12-01", "2028-02-29", "2027-02-29", "20261201", "12/01/2026", "2026/12/01", "1/15", "12/31", "2/30",
         "15 jan", "jan 15", "15 jan 2027", "jan 15, 2027", "1 december", "31 dec 2026", "17-JUN-2027", "feb 30",
         "31 nov", "3 sept", "2026-12-01T09:00", "2026-3-9"]
ODD = ["", "friday monday", "17:00 18:00", "december", "jan 2027", "2027", "noon", "midnight", "in 3 hours",
       "june 17th", "9.30", "12.11", "24:00", "13pm", "0am", "23:60", "17:00 UTC", "5pm GMT", "17:00 +1 day",
       "17:00 +0200", "17 +0100", "@1795467322", "tomorrow tomorrow", "friday week", "a week ago", "next", "ago",
       "pm", "1 2 3", "(an aside) friday", "FRIDAY 5PM", "5P.M.", "sat. 10am", "T09:00", "1 day 2 hours 3 min",
       "2 weeks 3 days ago", "third week", "second", "1 second", "13 months", "2026-11-31", "2026-13-01",
       "tuesday next week", "mon 9", "9am mon", "17.00", "5:5", "05:05:05 pm", "2026-12-01 17", "20261201 1700",
       "20261201 +2 days", "1700 friday", "+1", "+ 2 days", "2days", "2 dayss", "ago 2 days", "6 nov 23:59",
       "6 nov 2026 23:59", "nov 6 23:59", "15 jan 17:00", "1 dec 2026 17:00"]


def corpus():
    out = set(DAYS + MONTHS + TIMES + RELS + DATES + ODD)
    out.update(f"{o} {d}" for o in ("next", "last", "this", "first", "third", "2") for d in DAYS)
    out.update(f"{d} {t}" for d in DAYS for t in TIMES)
    out.update(f"{t} {d}" for d in DAYS[:3] for t in TIMES[:5])
    out.update(f"{r} {t}" for r in RELS for t in TIMES[:6])
    out.update(f"{d} {t}" for d in DATES for t in TIMES[:6])
    out.update(f"{d} {r}" for d in DATES[:8] for r in RELS)
    out.update(f"{d} {r}" for d in DAYS[:4] for r in RELS)
    out.update(f"{a} {b}" for a in RELS[:10] for b in RELS[:6])
    out.update(f"{n} {m}" for n in (1, 15, 29, 30, 31, 32) for m in MONTHS)
    out.update(f"{m} {n}" for n in (1, 15, 31) for m in MONTHS)
    return sorted(out)


def phrases_agree():
    date = find("date")
    version = subprocess.run([date, "--version"], capture_output=True, text=True).stdout if date else ""
    if "GNU" not in version:
        print("skip the phrases: no GNU date here to read them against")
        return
    env = dict(os.environ, LC_ALL="C")

    def gnu(phrase):
        r = subprocess.run([date, "-d", phrase, "+%s"], capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)
        text = r.stdout.strip()
        return int(text) if r.returncode == 0 and text.lstrip("-").isdigit() else None

    def mine(phrase, at):
        try:
            return pomo.read_date(phrase, at)
        except pomo.NoDate:
            return None

    def nameable(ts):
        """Whether this machine's Python can turn the moment into a day at all
        (Windows cannot before 1970, or far ahead)."""
        try:
            return dt.datetime.fromtimestamp(ts).year < 9000 and int(dt.datetime.fromtimestamp(ts).timestamp()) == ts
        except (OSError, OverflowError, ValueError):
            return False

    phrases = corpus()
    differ = []
    skipped = 0
    for p in phrases:
        for _ in range(3):
            before = int(time.time())
            theirs = gnu(p)
            if int(time.time()) == before:
                break
        ours = mine(p, before)
        if theirs != ours:
            if theirs is not None and ours is None and not nameable(theirs):
                skipped += 1
                continue
            differ.append(f"{p!r}: date {theirs}, pomo.py {ours}")
    check(not differ, f"{len(phrases)} phrases read as GNU date reads them"
          + (f" ({skipped} past what Python can name here)" if skipped else "")
          + ("".join("\n       " + d for d in differ[:12]) + (f"\n       … and {len(differ) - 12} more" if len(differ) > 12 else "")))


# ------------------------------------------------------------ 2. commands

FAKE_DATE = r'''
import datetime as dt, importlib.util, sys
spec = importlib.util.spec_from_file_location("pomo_py", sys.argv[1])
pomo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pomo)
args, text, form, i = sys.argv[2:], None, "%a %b %d %H:%M:%S %Y", 0
while i < len(args):
    if args[i] == "-d":
        text, i = args[i + 1], i + 1
    elif args[i].startswith("+"):
        form = args[i][1:]
    i += 1
try:
    ts = pomo.read_date(text) if text is not None else pomo.now()
    m = dt.datetime.fromtimestamp(ts)
except (pomo.NoDate, OSError, OverflowError, ValueError):
    sys.stderr.write("date: invalid date\n")
    sys.exit(1)
names = {"s": str(ts), "F": m.strftime("%Y-%m-%d"), "T": m.strftime("%H:%M:%S"), "u": str(m.isoweekday()),
         "a": "Mon Tue Wed Thu Fri Sat Sun".split()[m.weekday()],
         "b": "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()[m.month - 1],
         "Y": "%04d" % m.year, "m": "%02d" % m.month, "d": "%02d" % m.day, "H": "%02d" % m.hour,
         "M": "%02d" % m.minute, "S": "%02d" % m.second, "%": "%"}
out, i = "", 0
while i < len(form):
    if form[i] == "%" and i + 1 < len(form):
        out, i = out + names.get(form[i + 1], "%" + form[i + 1]), i + 2
    else:
        out, i = out + form[i], i + 1
sys.stdout.buffer.write((out + "\n").encode("utf-8"))
'''


def posix(p):
    return str(p).replace("\\", "/")


def stand_ins(folder: pathlib.Path) -> pathlib.Path:
    """What goes first on PATH for both programs: the test's `date`, a
    `notify-send` that notifies nobody, and a `flock` where there is none."""
    bin_dir = folder / "bin"
    bin_dir.mkdir()
    (folder / "fake_date.py").write_text(FAKE_DATE, encoding="utf-8")
    scripts = {"date": f'#!/bin/sh\nexec "{posix(sys.executable)}" "{posix(folder / "fake_date.py")}" "{posix(PY_POMO)}" "$@"\n',
               "notify-send": "#!/bin/sh\nexit 0\n"}
    if not find("flock"):
        scripts["flock"] = "#!/bin/sh\nexit 0\n"
    for name, body in scripts.items():
        path = bin_dir / name
        path.write_bytes(body.encode("utf-8"))
        path.chmod(0o755)
    return bin_dir


def start_of(year, month, day, hour, minute=0):
    return int(dt.datetime(year, month, day, hour, minute).timestamp())


# A step is a command's words, ("later", seconds) or ("line", a raw line for
# deadlines.tsv, as an older store has them).
STEPS = [
    ["status"], ["start"], ["status"], ("later", 60), ["pause"], ["pause"], ["status"], ("later", 30), ["resume"],
    ["resume"], ["toggle"], ["toggle"], ("later", 2000), ["status"], ["expired"], ["expired"], ["status"],
    ["toggle"], ("later", 400), ["pause"], ["status"], ["resume"],
    ["autostart"], ["autostart", "on"], ["autostart", "toggle"], ["autostart", "toggle"], ["autostart", "bogus"],
    ["start", "focus", "1"], ("later", 61), ["skip"], ["status"],
    ["start", "up"], ("later", 125), ["status"], ["pause"], ("later", 10), ["resume"], ("later", 5), ["skip"],
    ["start", "focus", "up"], ("later", 7), ["reset"],
    ["start", "break", "up"], ["start", "focus", "0"], ["start", "focus", "abc"], ["start", "nap"],
    ["start", "focus", "5", "extra"], ["start", "--for"], ["start", "--for", "abc"], ["start", "--for", "99"],
    ["start", "break", "3"], ("later", 181), ["toggle"], ["status"], ["autostart", "off"],
    ["start", "", "focus", "2"], ("later", 121), ["toggle"], ["toggle"], ["skip"], ["skip"],
    ["reset"], ["stats"], ["stats", "week"], ["stats", "month"], ["stats", "--json"], ["stats", "year"], ["bell"],
    ["toggle"], ("later", 1500), ["skip"], ["status"], ["reset"],

    ["deadline"], ["deadline", "list", "--json"], ["deadline", "next"], ["deadline", "next", "--json"],
    ["deadline", "add", "Essay draft", "--project", "stats", "next", "friday", "17:00"],
    ["deadline", "add", "Read ch.7", "tomorrow"],
    ["deadline", "add", "Thesis ch 2", "--subject", "thesis", "--link", "https://example.org/x?a=1&b=2", "in", "3", "days"],
    ["deadline", "add", "Synced one", "--id", "40", "12.12."],
    ["deadline", "add", "Twice", "--id", "40", "friday"],
    ["deadline", "add", "After forty", "2w"],
    ["deadline", "add", "A tab\tand a \"quote\"", "1", "dec", "2027", "at", "9:30"],
    ["deadline", "add", "Übung für Montag — résumé", "--project", "Üb", "monday", "9am"],
    ["deadline", "add", "No date", "phone"], ["deadline", "add", "Only a title"], ["deadline", "add"],
    ["deadline", "add", "Bad id", "--id", "0", "friday"], ["deadline", "add", "Flag last", "friday", "--project"],
    ["deadline", "list"], ["deadline", "list", "--json"], ["deadline", "list", "--all", "--json"], ["deadline", "--json"],
    # (A project's capitals fold as the locale folds them, and this test runs
    # both in the C locale: only ASCII is asked to fold here.)
    ["deadline", "ls", "--project", "STATS"], ["deadline", "list", "--project", "Üb", "--json"],
    ["deadline", "list", "--project", "none"], ["deadline", "list", "--bogus"], ["deadline", "list", "--project"],
    ["deadline", "next"], ["deadline", "next", "--json"],
    ["deadline", "when", "friday", "17:00"], ["deadline", "when", "the", "8th", "of", "Feb"],
    ["deadline", "when", "12.11.26", "at", "9:30"], ["deadline", "when", "31.02"], ["deadline", "when", "24.12"],
    ["deadline", "when", "1.2."], ["deadline", "when", "3h"], ["deadline", "when", "2D"], ["deadline", "when", "today"],
    ["deadline", "when", "tomorrow"], ["deadline", "when", "15", "jan"], ["deadline", "when", "1/15"],
    ["deadline", "when", "today", "(2026-10-12)"], ["deadline", "when", "by", "monday"],
    ["deadline", "when", "due", "next", "friday", "at", "5pm"], ["deadline", "when", "6", "Nov", "2026", "at", "23:59"],
    ["deadline", "when", "6", "nov", "23:59"], ["deadline", "when", "next", "week"], ["deadline", "when", "in", "3", "hours"],
    ["deadline", "when", "1st", "march"], ["deadline", "when", "22nd"], ["deadline", "when"], ["deadline", "when", "phone"],
    ["deadline", "set", "1", "friday", "18:00"], ["deadline", "set", "1", "--title", "Essay final", "--project", ""],
    ["deadline", "set", "1"], ["deadline", "set", "x"], ["deadline", "set", "99", "friday"],
    ["deadline", "edit", "1", "--link", "essay.pdf", "--when"], ["deadline", "set", "2", "--title", "", "saturday"],
    ["deadline", "set", "2", "never"], ["deadline", "set", "2", "--title"],
    ["start", "focus", "25", "--for", "1"], ("later", 10), ["pause"], ["resume"], ("later", 1500), ["expired"], ["reset"],
    ["deadline", "done", "1"], ["deadline", "done", "1"], ["deadline", "reopen", "1"], ["deadline", "undone", "1"],
    ["deadline", "submit", "2", "--at", "1700000000"], ["deadline", "grade", "3", "7.5"], ["deadline", "grade", "3"],
    ["deadline", "grade", "41", "A", "minus"], ["deadline", "grade", "x"], ["deadline", "grade"],
    ["deadline", "hide", "2"], ["deadline", "hide", "2"], ["deadline", "unhide", "2"], ["deadline", "show", "2"],
    ["deadline", "hide", "41"], ["deadline", "hide", "42"], ["deadline", "cancel", "40"], ["deadline", "cancel", "40"],
    ["deadline", "reopen", "40"], ["deadline", "cancel", "40"],
    ["deadline", "list"], ["deadline", "list", "--all"], ["deadline", "list", "--all", "--json"], ["deadline", "next"],
    ["deadline", "put", "7", "--due", "1800000000", "--title", "From afar", "--status", "done", "--done-at",
     "1799990000", "--grade", "1.3", "--project", "intsem", "--from", "air"],
    ["deadline", "put", "7", "--due", "1800000500", "--title", "From afar, again", "--status", "open", "--done-at", "soon"],
    ["deadline", "put", "8", "--title", "No due", "--status", "open"],
    ["deadline", "put", "8", "--due", "1800000000", "--title", "Bad status", "--status", "late"],
    ["deadline", "put", "8", "--due", "1800000000", "--colour", "red"], ["deadline", "put", "8", "--due"],
    ["deadline", "put", "0", "--due", "1", "--title", "t", "--status", "open"], ["deadline", "put"],
    ["deadline", "reserve", "100"], ["deadline", "add", "After the reserve", "monday"], ["deadline", "reserve", "x"],
    ["deadline", "reserve", "5"], ["deadline", "add", "And the next", "sunday", "23:00"],
    ("line", "200\t1790000000\tThree fields from an old store"),
    ("line", "201\t1790000100\tSix fields\tdone\t1789990000\t8"),
    ("line", "202\t1790000100\tA status nobody knows\tpaused\tx\t\t\t"),
    ("line", "not a deadline"),
    ["deadline", "list", "--all"], ["deadline", "list", "--all", "--json"], ["deadline", "done", "200"],
    ["deadline", "grade", "201", "9"], ["deadline", "set", "202", "--project", "old"], ["deadline", "add", "After the old ones", "3d"],
    ["deadline", "rm", "3"], ["deadline", "rm", "3"], ["deadline", "remove"], ["deadline", "rm", "abc"],
    ["start", "--for=7"], ["deadline", "rm", "7"], ("later", 5), ["pause"], ["reset"],
    ["report", "--json"], ["report"], ["deadline", "help"], ["deadline", "bogus"], ["bogus"], [], ["help"],
    ("later", 40 * 86400), ["deadline", "list"], ["deadline", "next"], ["deadline", "next", "--json"],
    ["deadline", "list", "--all", "--json"], ["stats"], ["report", "--json"],
]

FILES = ("state.json", "deadlines.tsv", "deadlines.seq", "pomo.log")


def commands_agree():
    bash = find("bash")
    if not bash or not all(find(t) for t in ("sed", "awk", "sort")):
        print("skip the commands: no bash and its tools here to run cli/pomo")
        return
    folder = pathlib.Path(tempfile.mkdtemp(prefix="pomo-port-"))
    try:
        bin_dir = stand_ins(folder)
        path = os.pathsep.join([str(bin_dir)] + ([str(TOOLS)] if TOOLS else []) + [os.environ.get("PATH", "")])
        states = {"bash": folder / "bash", "python": folder / "python"}
        for s in states.values():
            (s / "longhand").mkdir(parents=True)
        programs = {"bash": [bash, str(BASH_POMO)] if WINDOWS else [str(BASH_POMO)], "python": [sys.executable, str(PY_POMO)]}
        clock = start_of(2026, 11, 23, 10)       # a Monday morning

        def run(which, words):
            env = dict(os.environ, PATH=path, XDG_STATE_HOME=posix(states[which]), LONGHAND_NOW=str(clock),
                       LONGHAND_SILENT="1", LONGHAND_NO_CHECK="1", LC_ALL="C", PYTHONUTF8="1")
            r = subprocess.run(programs[which] + list(words), capture_output=True, env=env, stdin=subprocess.DEVNULL, timeout=120)
            here = posix(states[which]).encode()
            return (r.returncode, r.stdout.replace(here, b"<state>"), r.stderr.replace(here, b"<state>"),
                    tuple((states[which] / "longhand" / f).read_bytes() if (states[which] / "longhand" / f).exists() else None
                          for f in FILES))

        def said(result):
            code, out, err, _ = result
            return f"exit {code} · out {out.decode('utf-8', 'replace')!r} · err {err.decode('utf-8', 'replace')!r}"

        ran = same = 0
        for step in STEPS:
            if isinstance(step, tuple) and step[0] == "later":
                clock += step[1]
                continue
            if isinstance(step, tuple) and step[0] == "line":
                for s in states.values():
                    with open(s / "longhand" / "deadlines.tsv", "ab") as f:
                        f.write((step[1] + "\n").encode("utf-8"))
                continue
            theirs, ours = run("bash", step), run("python", step)
            ran += 1
            what = "pomo " + " ".join(repr(w) if (" " in w or w == "") else w for w in step)
            if theirs[:3] != ours[:3]:
                check(False, f"{what}\n       bash:   {said(theirs)}\n       python: {said(ours)}")
            elif theirs[3] != ours[3]:
                which = [f for f, a, b in zip(FILES, theirs[3], ours[3]) if a != b]
                detail = "".join(f"\n       {f}\n         bash:   {a!r}\n         python: {b!r}"
                                 for f, a, b in zip(FILES, theirs[3], ours[3]) if a != b)
                check(False, f"{what}: says the same, leaves {', '.join(which)} different{detail}")
            else:
                same += 1
        check(same == ran, f"{same} of {ran} commands: the same words, exit code and files from both")
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def main() -> int:
    phrases_agree()
    commands_agree()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
