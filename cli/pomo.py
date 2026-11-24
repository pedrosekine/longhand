#!/usr/bin/env python3
"""pomo, in Python: the timer and the deadline store, command for command.

The same CLI, the same files and the same words as `cli/pomo` (bash), for a
machine that has no bash, sed, awk, flock or GNU date — Windows. Written
from the bash line by line (2026-11-23) and held to it by
tests/test_pomo_port.py, which runs both and compares what they say and what
they leave on disk. Where bash leans on a tool, the tool's behaviour is what
is ported: sed's "last match on the line" for the state file, awk's numbers
for ids, sort's order for the list, and GNU date's reading of a phrase
(`read_date`, below).

State: ${XDG_STATE_HOME:-~/.local/state}/longhand/ — state.json, pomo.log,
deadlines.tsv, deadlines.seq.

Three places differ from the bash on purpose:
- JSON escapes a backslash and control characters in a title (the awk left a
  backslash bare, which is not JSON);
- a sound is played without holding the caller's stdout open;
- Windows has no notify-send: there the running Longhand says it from the
  tray, else a Windows toast (windows/notify.py); the sound, at the shell's
  volume and never under Do Not Disturb, is windows/play_sound.py.
"""
from __future__ import annotations

import calendar
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

TAB = "\t"
WRITES = ("add", "set", "edit", "done", "submit", "undone", "reopen", "grade", "hide", "unhide",
          "show", "cancel", "rm", "remove", "reserve", "put")
CHECKED = WRITES[:-2]      # a change typed by hand: the notes follow at once


class Exit(Exception):
    """bash's `exit N`, from wherever it is said."""

    def __init__(self, code=0):
        super().__init__(code)
        self.code = code


def out(s: str) -> None:
    sys.stdout.buffer.write(s.encode("utf-8", "surrogateescape"))
    sys.stdout.buffer.flush()


def err(s: str) -> None:
    sys.stderr.buffer.write(s.encode("utf-8", "surrogateescape"))
    sys.stderr.buffer.flush()


def now() -> int:
    # LONGHAND_NOW pins the clock (an epoch), for a test that must say the
    # same thing twice: tests/test_pomo_port.py.
    pinned = os.environ.get("LONGHAND_NOW", "")
    return int(pinned) if pinned.lstrip("-").isdigit() else int(time.time())


def today() -> dt.date:
    return dt.datetime.fromtimestamp(now()).date()


def home() -> str:
    return os.environ.get("HOME") or os.path.expanduser("~").replace("\\", "/")


STATE_DIR = (os.environ.get("XDG_STATE_HOME") or home() + "/.local/state") + "/longhand"
STATE_FILE = STATE_DIR + "/state.json"
LOG_FILE = STATE_DIR + "/pomo.log"
DEADLINE_FILE = STATE_DIR + "/deadlines.tsv"
DEADLINE_SEQ = STATE_DIR + "/deadlines.seq"

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SOUND_FILE = os.path.join(SCRIPT_DIR, "..", "sounds", "done.wav")
if not os.path.isfile(SOUND_FILE):
    SOUND_FILE = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"


# ------------------------------------------------------------------ files

def read_text(path: str) -> str:
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "surrogateescape")
    except OSError:
        return ""


def write_text(path: str, text: str, append: bool = False) -> None:
    with open(path, "ab" if append else "wb") as f:
        f.write(text.encode("utf-8", "surrogateescape"))


def has_size(path: str) -> bool:
    """bash's `[ -s file ]`."""
    try:
        return os.path.getsize(path) > 0
    except OSError:
        return False


def records(path: str) -> list[str]:
    """A file's lines as awk sees them."""
    text = read_text(path)
    if text == "":
        return []
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    return lines


_NUM = re.compile(r"[ \t\n]*([-+]?(?:\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))")


def num(s: str) -> float:
    """A string as awk's `s+0`: the number it starts with, else 0."""
    m = _NUM.match(s)
    return float(m.group(1)) if m else 0.0


def shown(x: float) -> str:
    """A number as awk prints it."""
    return str(int(x)) if x == int(x) else "%.6g" % x


def digits(s: str) -> bool:
    return s != "" and s.isascii() and s.isdigit()


# ------------------------------------------------------------------ state

def scan(key: str, kind: str) -> str:
    """sed -n 's/.*"key":…/\\1/p' | head -1: on the first line that has the
    key, the value of its last occurrence; empty when there is none."""
    value = {"word": r'"([^"]*)"', "flag": r"([a-z]*)", "number": r"([0-9]*)"}[kind]
    pattern = re.compile('.*"' + re.escape(key) + '":' + value)
    for line in read_text(STATE_FILE).split("\n"):
        m = pattern.match(line)
        if m:
            return m.group(1)
    return ""


def get(key: str, default: str) -> str:
    kind = "word" if key in ("phase", "status") else "flag" if key in ("auto", "countup") else "number"
    return scan(key, kind) or default


class Timer:
    focus_len = 1500
    break_len = 300
    total = 0
    target = 0          # the deadline id this session is for, 0 when none


T = Timer()


def load_lengths() -> None:
    T.focus_len = int(scan("focus_len", "number") or 1500)
    T.break_len = int(scan("break_len", "number") or 300)
    T.total = int(scan("total", "number") or 0)
    T.target = int(scan("for", "number") or 0)


def save(phase: str, status: str, ends_at, remaining, auto: str = "", countup: str = "") -> None:
    auto = auto or get("auto", "false")
    countup = countup or get("countup", "false")
    write_text(STATE_FILE, '{"phase":"%s","status":"%s","ends_at":%d,"remaining":%d,"auto":%s,"countup":%s,'
               '"focus_len":%d,"break_len":%d,"total":%d,"for":%d}\n'
               % (phase, status, int(ends_at), int(remaining), auto, countup, T.focus_len, T.break_len, T.total, T.target))


def ensure_state() -> None:
    if not os.path.isfile(STATE_FILE):
        save("idle", "idle", 0, 0)


def fmt(secs: int) -> str:
    return "%d:%02d" % (secs // 60, secs % 60)


def report(message: str) -> None:
    out("pomo: " + message + "\n")
    write_text(LOG_FILE, time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now())) + " " + message + "\n", append=True)


def for_text() -> str:
    if T.target <= 0:
        return ""
    line = find_deadline(str(T.target))
    # The deadline may have been removed since; the id still means what it meant.
    return " · for #%d %s" % (T.target, line[2]) if line else " · for #%d" % T.target


def live_remaining() -> int:
    status, ends_at, remaining = get("status", "idle"), int(get("ends_at", "0")), int(get("remaining", "0"))
    n = now()
    if get("countup", "false") == "true":
        return max(n - ends_at, 0) if status == "running" else remaining
    if status == "done":
        return 0
    if status == "running":
        return max(ends_at - n, 0)
    return remaining


def is_expired_running() -> bool:
    # A count-up session has no end, so it can never expire.
    if get("countup", "false") == "true":
        return False
    return get("status", "idle") == "running" and get("phase", "idle") != "idle" and now() >= int(get("ends_at", "0"))


# ------------------------------------------------------------------ bell

WINDOWS_DIR = os.path.join(SCRIPT_DIR, "..", "windows")


def windows_helper(name: str, *args: str) -> None:
    """windows/<name>.py, started and left: pomo does not wait on Windows'
    sound or toast, as it does not wait on pw-play."""
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.Popen([sys.executable, os.path.join(WINDOWS_DIR, name + ".py"), *args], creationflags=flags,
                     close_fds=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def notify(message: str) -> None:
    if os.name == "nt":
        # Windows has no notify-send: the running Longhand says it from the
        # tray, else Windows itself (windows/notify.py). Quiet in a test.
        if not os.environ.get("LONGHAND_SILENT") and os.path.isfile(os.path.join(WINDOWS_DIR, "notify.py")):
            try:
                windows_helper("notify", "Pomodoro", message)
            except OSError:
                pass
        return
    if shutil.which("notify-send"):
        try:
            subprocess.run(["notify-send", "Pomodoro", message], stderr=subprocess.DEVNULL)
        except OSError:
            pass


def play_sound() -> None:
    if os.environ.get("LONGHAND_SILENT"):
        return
    quiet = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if os.name == "nt":
            # As pw-play --volume=0.6, and not under Do Not Disturb
            # (windows/play_sound.py asks Windows, as the shell is asked below).
            if os.path.isfile(SOUND_FILE):
                windows_helper("play_sound", "--volume", "0.6", SOUND_FILE)
            return
        if shutil.which("omarchy-shell"):
            dnd = subprocess.run(["omarchy-shell", "notifications", "isDnd"], capture_output=True, text=True)
            if dnd.stdout.strip() == "on":
                return
        for player in (["pw-play", "--volume=0.6"], ["paplay"], ["aplay", "-q"]):
            if shutil.which(player[0]):
                subprocess.Popen(player + [SOUND_FILE], start_new_session=True, **quiet)
                return
    except OSError:
        pass


# ------------------------------------------------------------------ timer

def start_usage():
    err("usage: pomo start [focus|break|up] [minutes|up] [--for <deadline id>]\n")
    raise Exit(1)


def cmd_start(args: list[str]) -> None:
    phase = mins = target = ""
    countup = "false"
    # --for may sit anywhere after `start`; the bare words are phase then minutes.
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--for":
            if i + 1 >= len(args):
                start_usage()
            target = args[i + 1]
            i += 1
        elif a.startswith("--for="):
            target = a[len("--for="):]
        elif a == "":
            pass
        elif phase == "":
            phase = a
        elif mins == "":
            mins = a
        else:
            start_usage()
        i += 1
    phase = phase or "focus"
    if phase == "up":
        phase, countup = "focus", "true"
    elif phase not in ("focus", "break"):
        start_usage()
    # A session either targets a deadline or it does not: starting without
    # --for never inherits the previous session's target.
    if target != "":
        if not digits(target) or target == "0":
            err("pomo: --for needs a deadline id (pomo deadline list)\n")
            raise Exit(1)
        if not find_deadline(target):
            err("pomo: no deadline #%s\n" % target)
            raise Exit(1)
        T.target = int(target)
    else:
        T.target = 0
    if mins == "up":
        # Open-ended focus: the session counts up until skipped or reset.
        if phase == "break":
            err("count-up only works for focus, not breaks\n")
            raise Exit(1)
        countup = "true"
        length = 0
    elif mins != "":
        if not digits(mins) or mins == "0":
            err('minutes must be a positive number or "up"\n')
            raise Exit(1)
        length = int(mins) * 60
        if phase == "focus":
            T.focus_len = length
        else:
            T.break_len = length
    elif countup == "true":
        length = 0
    elif phase == "focus":
        length = T.focus_len
    else:
        length = T.break_len
    T.total = length
    n = now()
    if countup == "true":
        # ends_at carries the session START; elapsed = now - ends_at.
        save("focus", "running", n, 0, "", countup)
        report("focus started · counting up" + for_text())
    elif phase == "focus":
        save("focus", "running", n + length, length, "", countup)
        report("focus started · " + fmt(length) + for_text())
    else:
        save("break", "running", n + length, length, "", countup)
        report("break started · " + fmt(length) + for_text())


def start_next() -> None:
    cmd_start(["break"] if get("phase", "idle") == "focus" else ["focus"])


def cmd_pause() -> None:
    ensure_state()
    status = get("status", "idle")
    if status == "done":
        report(get("phase", "focus") + " finished — use toggle/skip to start next")
        raise Exit(0)
    if status != "running":
        report("nothing to pause (status: %s)" % status)
        raise Exit(0)
    if is_expired_running():
        # Finished but not yet completed: log it once instead of pausing a 0:00 timer.
        cmd_expired()
        raise Exit(0)
    phase, ends_at, n = get("phase", "focus"), int(get("ends_at", "0")), now()
    # Count-up: freeze the elapsed time in "remaining".
    remaining = max(n - ends_at, 0) if get("countup", "false") == "true" else max(ends_at - n, 0)
    save(phase, "paused", ends_at, remaining)
    report("%s paused · %s%s" % (phase, fmt(remaining), for_text()))


def cmd_resume() -> None:
    ensure_state()
    status = get("status", "idle")
    if status == "done":
        report(get("phase", "focus") + " finished — use toggle/skip to start next")
        raise Exit(0)
    if status != "paused":
        report("nothing to resume (status: %s)" % status)
        raise Exit(0)
    remaining = int(get("remaining", "0"))
    if remaining <= 0:
        # Legacy expired-paused state: mark finished instead of resuming a
        # timer that would instantly re-expire and log a duplicate completion.
        phase = get("phase", "focus")
        save(phase, "done", get("ends_at", "0"), 0)
        report(phase + " finished — use toggle/skip to start next")
        raise Exit(0)
    phase, n = get("phase", "focus"), now()
    if get("countup", "false") == "true":
        # Count-up: rewind ends_at so now - ends_at keeps counting from the pause point.
        save(phase, "running", n - remaining, remaining)
        report("%s resumed · %s elapsed%s" % (phase, fmt(remaining), for_text()))
    else:
        save(phase, "running", n + remaining, remaining)
        report("%s resumed · %s left%s" % (phase, fmt(remaining), for_text()))


def cmd_toggle() -> None:
    ensure_state()
    status = get("status", "idle")
    if status == "done":
        start_next()        # finished session acknowledged: start the next phase
        return
    if status == "paused" and int(get("remaining", "0")) <= 0:
        cmd_resume()        # legacy expired-paused: converts to done + reports
        return
    if is_expired_running():
        # Expired but completion not logged yet: log once, then start next
        # (unless auto-start already advanced us).
        cmd_expired()
        if get("status", "idle") == "done":
            start_next()
        return
    if status == "running":
        cmd_pause()
    elif status == "paused":
        cmd_resume()
    else:
        cmd_start(["focus"])


def cmd_reset() -> None:
    T.total = 0
    T.target = 0
    save("idle", "idle", 0, 0, "", "false")
    report("reset to idle")


def cmd_skip() -> None:
    ensure_state()
    if get("status", "idle") == "done":
        start_next()
        return
    if is_expired_running():
        # Skipping a just-finished phase: the completion is logged once.
        cmd_expired()
        if get("status", "idle") == "running":
            return
    if get("countup", "false") == "true" and get("status", "idle") != "idle":
        # Leaving a count-up focus: log the elapsed time as a completed session.
        elapsed = live_remaining()
        T.total = elapsed
        report("focus completed · %s · count-up%s" % (fmt(elapsed), for_text()))
        notify("Count-up focus done · " + fmt(elapsed))
    start_next()


def cmd_status() -> str:
    ensure_state()
    phase, status, ends_at = get("phase", "idle"), get("status", "idle"), int(get("ends_at", "0"))
    remaining, n = live_remaining(), now()
    expired = "false"
    if status == "done":
        expired = "true"
    elif get("countup", "false") == "true":
        expired = "false"
    elif status == "running" and n >= ends_at and phase != "idle":
        expired = "true"
    return ('{"phase":"%s","status":"%s","ends_at":%d,"remaining":%d,"expired":%s,"auto":%s,"countup":%s,"total":%d,"for":%d}\n'
            % (phase, status, ends_at, remaining, expired, get("auto", "false"), get("countup", "false"),
               int(get("total", "0")), int(get("for", "0"))))


def count_from(start: str) -> int:
    """Focus sessions completed since a day (YYYY-MM-DD), from the log."""
    count = 0
    for line in records(LOG_FILE):
        fields = line.split()
        if fields and fields[0] >= start and "focus completed" in line:
            count += 1
    return count


def stats_json() -> str:
    day = today()
    monday = day - dt.timedelta(days=day.isoweekday() - 1)
    return '{"day":%d,"week":%d,"month":%d}\n' % (count_from(day.isoformat()), count_from(monday.isoformat()),
                                                 count_from(day.strftime("%Y-%m-01")))


def cmd_stats(scope: str) -> None:
    if scope == "--json":
        out(stats_json())
        return
    day = today()
    if scope == "day":
        n, words = count_from(day.isoformat()), "today"
    elif scope == "week":
        n, words = count_from((day - dt.timedelta(days=day.isoweekday() - 1)).isoformat()), "this week"
    elif scope == "month":
        n, words = count_from(day.strftime("%Y-%m-01")), "this month"
    else:
        err("usage: pomo stats [day|week|month|--json]\n")
        raise Exit(1)
    out("1 focus session %s\n" % words if n == 1 else "%d focus sessions %s\n" % (n, words))


def cmd_bell() -> None:
    ensure_state()
    message = {"focus": "Focus done — break time", "break": "Break over — back to focus"}.get(get("phase", "idle"), "Pomodoro")
    notify(message)
    play_sound()
    report("bell: " + message)


def cmd_autostart(what: str) -> None:
    ensure_state()
    auto = get("auto", "false")
    if what == "on":
        following = "true"
    elif what == "off":
        following = "false"
    elif what == "toggle":
        following = "false" if auto == "true" else "true"
    elif what == "status":
        out("auto-start %s\n" % auto)
        return
    else:
        err("usage: pomo autostart [on|off|toggle]\n")
        raise Exit(1)
    save(get("phase", "idle"), get("status", "idle"), get("ends_at", "0"), get("remaining", "0"), following)
    report("auto-start " + following)


def cmd_expired() -> None:
    """A running phase may have hit zero: ring once, keep a "done" state, and
    start the next phase when auto-start is on. Silent unless something expired."""
    ensure_state()
    phase, status, ends_at, n = get("phase", "idle"), get("status", "idle"), int(get("ends_at", "0")), now()
    # Count-up sessions never expire (ends_at holds their start, not a deadline).
    if get("countup", "false") == "true" or status == "done":
        raise Exit(0)
    if status != "running" or phase == "idle" or n < ends_at:
        raise Exit(0)
    if phase == "focus":
        message, following = "Focus done — break time", "break"
    else:
        message, following = "Break over — back to focus", "focus"
    if T.total <= 0:
        T.total = T.focus_len if phase == "focus" else T.break_len
    report("%s completed · %s%s" % (phase, fmt(T.total), for_text()))
    notify(message)
    play_sound()
    if get("auto", "false") == "true":
        cmd_start([following])
    else:
        # Arm the next phase at full length in a paused "ready" state. It is
        # a new session, so it carries no deadline target.
        length = T.focus_len if following == "focus" else T.break_len
        T.total = length
        T.target = 0
        save(following, "paused", 0, length)


# ------------------------------------------------------------------ dates
#
# `date -d`, as far as a deadline is ever written: GNU's own grammar
# (gnulib's parse-datetime.y), read token by token the way its parser takes
# them, so a phrase means here what it means on Omarchy — its quirks too
# ("next friday" on a Wednesday is this week's; "6 nov 23:59" is refused,
# since the 23 is taken for a year).

MONTHS = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER",
          "NOVEMBER", "DECEMBER"]
NAMED = [(m, "MONTH", i + 1) for i, m in enumerate(MONTHS)] + [("SEPT", "MONTH", 9)] + [
    ("SUNDAY", "DAY", 0), ("MONDAY", "DAY", 1), ("TUESDAY", "DAY", 2), ("TUES", "DAY", 2),
    ("WEDNESDAY", "DAY", 3), ("WEDNES", "DAY", 3), ("THURSDAY", "DAY", 4), ("THUR", "DAY", 4),
    ("THURS", "DAY", 4), ("FRIDAY", "DAY", 5), ("SATURDAY", "DAY", 6)]
UNITS = {"YEAR": ("year", 1), "MONTH": ("month", 1), "FORTNIGHT": ("day", 14), "WEEK": ("day", 7), "DAY": ("day", 1),
         "HOUR": ("hour", 1), "MINUTE": ("minute", 1), "MIN": ("minute", 1), "SECOND": ("second", 1), "SEC": ("second", 1)}
RELATIVE = {"TOMORROW": ("SHIFT", 1), "YESTERDAY": ("SHIFT", -1), "TODAY": ("SHIFT", 0), "NOW": ("SHIFT", 0),
            "LAST": ("ORDINAL", -1), "THIS": ("ORDINAL", 0), "NEXT": ("ORDINAL", 1), "FIRST": ("ORDINAL", 1),
            "THIRD": ("ORDINAL", 3), "FOURTH": ("ORDINAL", 4), "FIFTH": ("ORDINAL", 5), "SIXTH": ("ORDINAL", 6),
            "SEVENTH": ("ORDINAL", 7), "EIGHTH": ("ORDINAL", 8), "NINTH": ("ORDINAL", 9), "TENTH": ("ORDINAL", 10),
            "ELEVENTH": ("ORDINAL", 11), "TWELFTH": ("ORDINAL", 12), "AGO": ("AGO", -1), "HENCE": ("AGO", 1)}
ZONES = {"UTC": 0, "UT": 0, "GMT": 0, "Z": 0}


class NoDate(Exception):
    pass


def word_token(word: str):
    w = word.upper()
    if w in ("AM", "A.M."):
        return ("MERIDIAN", "am")
    if w in ("PM", "P.M."):
        return ("MERIDIAN", "pm")
    short = len(w) == 3 or (len(w) == 4 and w[3] == ".")
    for name, kind, value in NAMED:
        if (w[:3] == name[:3]) if short else (w == name):
            return (kind, value)
    if w in ZONES:
        return ("ZONE", ZONES[w])
    if w in UNITS:
        return ("UNIT",) + UNITS[w]
    if w.endswith("S") and w[:-1] in UNITS:
        return ("UNIT",) + UNITS[w[:-1]]
    if w in RELATIVE:
        return RELATIVE[w]
    if w == "T":
        return ("T", 0)
    if len(w) == 1 and w != "J":
        # One letter is a military time zone to GNU date, which is how "a
        # week ago" reads there: zone A, a week, ago.
        n = ord(w) - ord("A")
        hours = n + 1 if n < 9 else n if n < 13 else -(n - 12) if n < 25 else 0
        return ("ZONE", hours * 3600)
    bare = w.replace(".", "")
    if bare != w and bare in ZONES:
        return ("ZONE", ZONES[bare])
    raise NoDate(word)


def tokens(text: str) -> list:
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\n\r\f\v":
            i += 1
        elif c.isascii() and c.isdigit() or c in "+-":
            sign = 0
            if c in "+-":
                sign = -1 if c == "-" else 1
                i += 1
                while i < n and text[i] in " \t\n\r\f\v":
                    i += 1
                if not (i < n and text[i].isascii() and text[i].isdigit()):
                    continue                    # a sign before no number is skipped
            j = i
            while j < n and text[j].isascii() and text[j].isdigit():
                j += 1
            if j + 1 < n and text[j] in ".," and text[j + 1].isascii() and text[j + 1].isdigit():
                raise NoDate("a decimal")       # seconds with a fraction: no deadline is written so
            value = int(text[i:j])
            toks.append(("SNUM", -value if sign < 0 else value, j - i) if sign else ("UNUM", value, j - i))
            i = j
        elif c.isascii() and c.isalpha():
            j = i
            while j < n and (text[j].isascii() and text[j].isalpha() or text[j] == "."):
                j += 1
            toks.append(word_token(text[i:j]))
            i = j
        elif c == "(":
            depth = 0
            while i < n:
                depth += 1 if text[i] == "(" else -1 if text[i] == ")" else 0
                i += 1
                if depth <= 0:
                    break
        else:
            toks.append((c,))
            i += 1
    return toks


def to_year(value: int, width: int) -> int:
    if width == 2:
        return value + (2000 if value < 69 else 1900)
    return value


def read_date(text: str, at: int | None = None) -> int:
    """A phrase as GNU date reads it, as an epoch; NoDate when it does not."""
    at = now() if at is None else at
    stripped = text.strip()
    if re.fullmatch(r"@-?\d+", stripped):
        return int(stripped[1:])
    start = dt.datetime.fromtimestamp(at)
    year, year_width, month, day = start.year, 0, start.month, start.day
    hour, minute, second, meridian = start.hour, start.minute, start.second, ""
    rel = {"year": 0, "month": 0, "day": 0, "hour": 0, "minute": 0, "second": 0}
    seen = {"date": 0, "day": 0, "time": 0, "zone": 0}
    rels = False
    day_number = day_ordinal = 0
    zone = None
    toks = tokens(text)
    i = 0

    def at_(k):
        return toks[k] if k < len(toks) else ("END",)

    def kind(k):
        return at_(k)[0]

    def loose_number(value, width):
        nonlocal year, year_width, month, day, hour, minute, second, meridian
        if seen["date"] and not year_width and not rels and (seen["time"] or width > 2):
            year, year_width = value, width
        elif width > 4:
            seen["date"] += 1
            day, month, year, year_width = value % 100, (value // 100) % 100, value // 10000, width - 4
        else:
            seen["time"] += 1
            hour, minute = (value, 0) if width <= 2 else (value // 100, value % 100)
            second, meridian = 0, ""

    def unit(k, amount):
        """A unit at k, taken `amount` times; with `ago` after it, the other way."""
        nonlocal rels
        what, each = at_(k)[1], at_(k)[2]
        k += 1
        if kind(k) == "AGO":
            amount *= at_(k)[1]
            k += 1
        rel[what] += amount * each
        rels = True
        return k

    def zone_offset(k):
        """A signed number after a time is a time zone: +1, +0100, +01:00."""
        nonlocal zone
        value, width = at_(k)[1], at_(k)[2]
        k += 1
        if kind(k) == ":" and kind(k + 1) == "UNUM":
            minutes = abs(value) * 60 + at_(k + 1)[1]
            k += 2
        elif width <= 2:
            minutes = abs(value) * 60
        else:
            minutes = (abs(value) // 100) * 60 + abs(value) % 100
        zone = (-minutes if value < 0 else minutes) * 60
        seen["zone"] += 1
        return k

    def clock(k):
        """h[:mm[:ss]] [am|pm] [zone offset], from the number at k."""
        nonlocal hour, minute, second, meridian
        hour, minute, second, meridian = at_(k)[1], 0, 0, ""
        k += 1
        if kind(k) == ":":
            if kind(k + 1) != "UNUM":
                raise NoDate(text)
            minute = at_(k + 1)[1]
            k += 2
            if kind(k) == ":":
                if kind(k + 1) != "UNUM":
                    raise NoDate(text)
                second = at_(k + 1)[1]
                k += 2
        if kind(k) == "MERIDIAN":
            meridian = at_(k)[1]
            k += 1
        elif kind(k) == "SNUM":
            k = zone_offset(k)
        seen["time"] += 1
        return k

    while i < len(toks):
        t = toks[i]
        k1, k2 = kind(i + 1), kind(i + 2)
        if t[0] == "UNUM":
            value, width = t[1], t[2]
            if k1 == "MERIDIAN" or k1 == ":":
                i = clock(i)
            elif k1 == "/":
                if k2 != "UNUM":
                    raise NoDate(text)
                if kind(i + 3) == "/":
                    if kind(i + 4) != "UNUM":
                        raise NoDate(text)
                    third = at_(i + 4)
                    if width >= 4:      # YYYY/MM/DD
                        year, year_width, month, day = value, width, at_(i + 2)[1], third[1]
                    else:               # MM/DD/YY
                        month, day, year, year_width = value, at_(i + 2)[1], third[1], third[2]
                    i += 5
                else:
                    month, day = value, at_(i + 2)[1]
                    i += 3
                seen["date"] += 1
            elif k1 == "SNUM" and k2 == "SNUM":     # 2026-12-01
                year, year_width, month, day = value, width, -at_(i + 1)[1], -at_(i + 2)[1]
                seen["date"] += 1
                i += 3
                if kind(i) == "T":                  # …T09:00
                    if kind(i + 1) != "UNUM" or kind(i + 2) not in (":", "SNUM"):
                        raise NoDate(text)
                    i = clock(i + 1)
            elif k1 == "SNUM" and k2 == "UNIT":     # 20261201 +2 days
                loose_number(value, width)
                i = unit(i + 2, at_(i + 1)[1])
            elif k1 == "SNUM":                      # 17 +0100
                i = clock(i)
            elif k1 == "MONTH":
                day, month = value, at_(i + 1)[1]
                i += 2
                # The parser takes a number here for the year, whatever follows it.
                if kind(i) == "UNUM":
                    year, year_width = at_(i)[1], at_(i)[2]
                    i += 1
                elif kind(i) == "SNUM":             # 17-JUN-2027
                    year, year_width = -at_(i)[1], at_(i)[2]
                    i += 1
                seen["date"] += 1
            elif k1 == "DAY":                       # 2 friday
                day_ordinal, day_number = value, at_(i + 1)[1]
                seen["day"] += 1
                i += 2
            elif k1 == "UNIT":
                i = unit(i + 1, value)
            else:
                loose_number(value, width)
                i += 1
        elif t[0] == "SNUM":
            if k1 != "UNIT":
                raise NoDate(text)
            i = unit(i + 1, t[1])
        elif t[0] == "MONTH":
            month = t[1]
            if k1 == "UNUM":
                day = at_(i + 1)[1]
                i += 2
                if kind(i) == ",":
                    if kind(i + 1) != "UNUM":
                        raise NoDate(text)
                    year, year_width = at_(i + 1)[1], at_(i + 1)[2]
                    i += 2
            elif k1 == "SNUM" and k2 == "SNUM":     # JUN-17-2027
                day, year, year_width = -at_(i + 1)[1], -at_(i + 2)[1], at_(i + 2)[2]
                i += 3
            else:
                raise NoDate(text)
            seen["date"] += 1
        elif t[0] == "DAY":
            day_ordinal, day_number = 0, t[1]
            seen["day"] += 1
            i += 2 if k1 == "," else 1
        elif t[0] == "ORDINAL":
            if k1 == "DAY":
                day_ordinal, day_number = t[1], at_(i + 1)[1]
                seen["day"] += 1
                i += 2
            elif k1 == "UNIT":
                i = unit(i + 1, t[1])
            else:
                raise NoDate(text)
        elif t[0] == "UNIT":
            i = unit(i, 1)
        elif t[0] == "SHIFT":
            rel["day"] += t[1]
            rels = True
            i += 1
        elif t[0] == "ZONE" or t[0] == "T":
            zone = t[1] if t[0] == "ZONE" else -7 * 3600      # a T alone is zone T
            seen["zone"] += 1
            i += 1
        else:
            raise NoDate(text)

    if max(seen.values()) > 1:
        raise NoDate(text)
    if year_width:
        year = to_year(year, year_width)
    if seen["time"] or (rels and not seen["date"] and not seen["day"]):
        if meridian:
            if not 1 <= hour <= 12:
                raise NoDate(text)
            hour = hour % 12 + (12 if meridian == "pm" else 0)
    else:
        hour = minute = second = 0

    def stamp(moment: dt.datetime) -> int:
        if zone is not None:
            return calendar.timegm(moment.timetuple()) - zone
        return int(moment.timestamp())

    def local(ts: int) -> dt.datetime:
        if zone is not None:
            return dt.datetime(1970, 1, 1) + dt.timedelta(seconds=ts + zone)
        return dt.datetime.fromtimestamp(ts)

    def carried(y, m, d, hh, mm, ss) -> dt.datetime:
        """Fields past their range carried over, as mktime does."""
        y += (m - 1) // 12
        m = (m - 1) % 12 + 1
        return dt.datetime(y, m, 1, hh, mm, ss) + dt.timedelta(days=d - 1)

    try:
        moment = dt.datetime(year, month, day, hour, minute, second)
        ts = stamp(moment)
        if local(ts) != moment:
            raise NoDate(text)              # an hour the clocks skip
        if seen["day"] and not seen["date"]:
            weekday = (moment.weekday() + 1) % 7        # Sunday is 0, as in C
            ordinal = day_ordinal - (1 if day_ordinal > 0 and weekday != day_number else 0)
            moment = carried(moment.year, moment.month, moment.day + (day_number - weekday + 7) % 7 + 7 * ordinal,
                             hour, minute, second)
            ts = stamp(moment)
        if rel["year"] or rel["month"] or rel["day"]:
            before = ts
            moment = carried(moment.year + rel["year"], moment.month + rel["month"], moment.day + rel["day"],
                             moment.hour, moment.minute, moment.second)
            if zone is None and not (seen["date"] or seen["day"] or seen["time"]):
                # Nothing but a distance ("3 days", "2 months ago"): GNU date
                # keeps the summer-or-winter time it started in, so across a
                # clock change the hour moves by one. Kept, for the same answer.
                offset = calendar.timegm(dt.datetime.fromtimestamp(before).timetuple()) - before
                ts = calendar.timegm(moment.timetuple()) - offset
            else:
                ts = stamp(moment)
        return ts + rel["hour"] * 3600 + rel["minute"] * 60 + rel["second"]
    except (ValueError, OverflowError, OSError):
        raise NoDate(text) from None


MONTH_NAMED = re.compile(r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b", re.I | re.A)
DOTTED = re.compile(r"^([0-9]{1,2})\.([0-9]{1,2})(\.([0-9]{4}|[0-9]{2})?)?([ \t\n\r\f\v]+(.*))?$", re.A | re.S)


def parse_when(when: str) -> int:
    """Free date text as an epoch, forgiving of what people type; NoDate if none."""
    # An aside in parentheses goes ("today (2026-10-12)" would be *now*); the
    # filler word a deadline is said with goes; so does an "at" before the time.
    norm = re.sub(r"\([^)]*\)", "", when)
    norm = re.sub(r"^\s*(in|by|on|at|due|until|till)\s+", "", norm, count=1, flags=re.I | re.A)
    norm = re.sub(r"\s+at\s+([0-9]{1,2}(:[0-9]{2})?(\s*[ap]m)?)\b", r" \1", norm, count=1, flags=re.I | re.A)
    norm = re.sub(r"\s+$", "", norm, flags=re.A)
    # Dates as written in English ("the 8th of Feb"): only with a month named,
    # since a bare "22nd" would come out as 22:00 today.
    if MONTH_NAMED.search(norm):
        norm = re.sub(r"^the\s+", "", norm, count=1, flags=re.I | re.A)
        norm = re.sub(r"\b([0-9]{1,2})(st|nd|rd|th)\b", r"\1", norm, flags=re.I | re.A)
        norm = re.sub(r"\s+of\s+", " ", norm, flags=re.I | re.A)
    this_day = today()
    # A dotted day, day first ("12.11", "12.11.2026"), as written in Germany
    # and Brazil; with no year and already over, next year's.
    m = DOTTED.match(norm)
    if m:
        dd, mm, yy, rest = int(m.group(1)), int(m.group(2)), m.group(4) or "", m.group(6) or ""
        y = int(yy) if yy else this_day.year
        if len(yy) == 2:
            y += 2000
        if not yy and "%04d-%02d-%02d" % (y, mm, dd) < this_day.isoformat():
            y += 1
        try:
            day = dt.date(y, mm, dd)
        except ValueError:
            raise NoDate(when) from None       # 31.02 is no day
        norm = day.isoformat() + (" " + rest if rest else "")
    # Only digits then the letter: "3h", "2d", "1w".
    m = re.fullmatch(r"([0-9]+)([hHdDwW])", norm, flags=re.A)
    if m:
        norm = m.group(1) + {"h": " hours", "d": " days", "w": " weeks"}[m.group(2).lower()]
    # today/tomorrow/yesterday are now +/- 24h to GNU date, clock time and
    # all: pinned to their date, so the end-of-day snap below sees them.
    try:
        if norm.lower() in ("today", "tomorrow", "yesterday"):
            norm = dt.datetime.fromtimestamp(read_date(norm.lower())).strftime("%Y-%m-%d") + " 00:00"
        ts = read_date(norm)
        # A date with no year ("15 jan", "1/15") that is already over is next year's.
        if (not re.search(r"[0-9]{4}", norm) and (MONTH_NAMED.search(norm) or re.search(r"[0-9]/[0-9]", norm))
                and dt.datetime.fromtimestamp(ts).date() < this_day):
            ts = read_date(dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S") + " next year")
        # A bare day parses to 00:00, the start of the day nobody intends: its end.
        moment = dt.datetime.fromtimestamp(ts)
        if (moment.hour, moment.minute, moment.second) == (0, 0, 0):
            ts = read_date(moment.strftime("%Y-%m-%d") + " 23:59")
        time.localtime(ts)
    except (OSError, OverflowError, ValueError):
        raise NoDate(when) from None       # a day this machine's clock cannot name
    return ts


def when_text(ts) -> str:
    return time.strftime("%a %d %b %H:%M", time.localtime(int(num(str(ts)))))


def rel_text(ts) -> str:
    d = int(num(str(ts))) - now()
    a = abs(d)
    span = "%dd" % (a // 86400) if a >= 86400 else "%dh" % (a // 3600) if a >= 3600 else "%dm" % (a // 60)
    return span + " late" if d < 0 else "in " + span


# ------------------------------------------------------------------ deadlines
#
# One deadline per line:
#   id<TAB>due<TAB>title<TAB>status<TAB>done_at<TAB>grade<TAB>project<TAB>link
# Lines from before the status column have three fields, lines from before
# project/link have six; every reader brings them to eight.

STATUSES = ("open", "done", "hidden", "cancelled")


def normal(line: str):
    """A line's eight fields, or None when it is not a deadline."""
    f = line.split(TAB)
    if len(f) < 3:
        return None
    f += [""] * (8 - len(f))
    return [f[0], f[1], f[2], f[3] if f[3] in STATUSES else "open", shown(num(f[4])), f[5], f[6], f[7]]


def same_id(field: str, wanted: str) -> bool:
    return num(field) == num(wanted)


def find_deadline(wanted: str):
    if not has_size(DEADLINE_FILE):
        return None
    for line in records(DEADLINE_FILE):
        if same_id(line.split(TAB)[0], wanted):
            return normal(line)
    return None


_SORT_NUM = re.compile(r"[ \t]*(-?\d*\.?\d*)")


def sort_number(s: str) -> float:
    m = _SORT_NUM.match(s)
    try:
        return float(m.group(1)) if m and m.group(1) not in ("", "-", ".", "-.") else 0.0
    except ValueError:
        return 0.0


def sorted_deadlines() -> list:
    """Open by due date, then done, then hidden, then cancelled; a tie as
    `sort` breaks it, by the whole line."""
    rows = [d for d in (normal(line) for line in records(DEADLINE_FILE)) if d]
    rank = {"open": 0, "done": 1, "hidden": 2, "cancelled": 3}

    def key(d):
        return (rank[d[3]], sort_number(d[1]), (str(rank[d[3]]) + TAB + TAB.join(d)).encode("utf-8", "surrogateescape"))
    return sorted(rows, key=key)


def write_deadline(wanted, due, title, status, done_at, grade, project, link) -> None:
    lines = []
    for line in records(DEADLINE_FILE):
        f = line.split(TAB)
        lines.append(TAB.join([f[0], str(due), title, status, str(done_at), grade, project, link])
                     if same_id(f[0], str(wanted)) else line)
    replace_store(lines)


def replace_store(lines: list) -> None:
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(DEADLINE_FILE) + ".", dir=os.path.dirname(DEADLINE_FILE))
    with os.fdopen(fd, "wb") as f:
        f.write("".join(line + "\n" for line in lines).encode("utf-8", "surrogateescape"))
    os.replace(tmp, DEADLINE_FILE)


def clean_field(s: str) -> str:
    """Tabs and newlines are the record's delimiters: flattened to spaces."""
    return s.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def read_seq() -> int:
    return int("".join(c for c in read_text(DEADLINE_SEQ) if c in "0123456789") or 0) if has_size(DEADLINE_SEQ) else 0


def next_id() -> int:
    """Never the same id twice, even across removals: the high-water mark has
    a file of its own, healed from the store when it is missing or behind."""
    seq = read_seq()
    if has_size(DEADLINE_FILE):
        top = 0.0
        for line in records(DEADLINE_FILE):
            top = max(top, num(line.split(TAB)[0]))
        seq = max(seq, int(top))
    seq += 1
    write_text(DEADLINE_SEQ, "%d\n" % seq)
    return seq


def require_deadline(wanted: str, verb: str):
    if not digits(wanted):
        err("usage: pomo deadline %s <id>\n" % verb)
        raise Exit(1)
    line = find_deadline(wanted)
    if not line:
        err("pomo: no deadline #%s\n" % wanted)
        raise Exit(1)
    return line


def read_when(when: str) -> int:
    try:
        return parse_when(when)
    except NoDate:
        err('pomo: can\'t read a date out of "%s"\n' % when)
        raise Exit(1) from None


def add_usage():
    err("usage: pomo deadline add <title> [--project <s>] [--link <url-or-path>] [--id <n>] <when...>\n"
        '  e.g. pomo deadline add "Essay draft" --project stats next friday 17:00\n')
    raise Exit(1)


def cmd_deadline_add(args: list[str]) -> None:
    title = args[0] if args else ""
    when, project, link, want = [], "", "", ""
    i = 1
    while i < len(args):
        a = args[i]
        if a in ("--project", "--subject", "--link", "--id"):
            if i + 1 >= len(args):
                add_usage()
            if a == "--link":
                link = args[i + 1]
            elif a == "--id":
                # A deadline another machine made: kept under its own id.
                want = args[i + 1]
            else:
                project = args[i + 1]
            i += 1
        else:
            when.append(a)
        i += 1
    phrase = " ".join(when)
    if title == "" or phrase == "":
        add_usage()
    ts = read_when(phrase)
    title, project, link = clean_field(title), clean_field(project), clean_field(link)
    if want != "":
        if not digits(want) or want == "0":
            add_usage()
        if find_deadline(want):
            err("pomo: deadline #%s exists already\n" % want)
            raise Exit(1)
        ident = int(want)
        # Never hand this id out again here: the high-water mark moves past it.
        if ident > read_seq():
            write_text(DEADLINE_SEQ, "%d\n" % ident)
    else:
        ident = next_id()
    write_text(DEADLINE_FILE, "%d\t%d\t%s\topen\t0\t\t%s\t%s\n" % (ident, ts, title, project, link), append=True)
    report("deadline #%d · %s · %s%s" % (ident, when_text(ts), title, " · " + project if project else ""))


def cmd_deadline_put(args: list[str]) -> None:
    """The whole record, exactly as another machine has it: made or replaced
    as given, nothing worked out."""
    ident = args[0] if args else ""
    given = {"--due": "", "--title": "", "--status": "", "--done-at": "0", "--grade": "", "--project": "", "--link": "", "--from": ""}
    i = 1
    while i < len(args):
        if i + 1 >= len(args):
            err("usage: pomo deadline put <id> --due <epoch> --title <t> --status <s> [...]\n")
            raise Exit(1)
        if args[i] not in given:
            err("pomo: put does not know %s\n" % args[i])
            raise Exit(1)
        given[args[i]] = args[i + 1]
        i += 2
    if not digits(ident) or ident == "0":
        err("usage: pomo deadline put <id> ...\n")
        raise Exit(1)
    if not digits(given["--due"]):
        err("pomo: put needs --due <epoch>\n")
        raise Exit(1)
    done_at = given["--done-at"] if digits(given["--done-at"]) else "0"
    status = given["--status"]
    if status not in STATUSES:
        err("pomo: put needs --status open|done|hidden|cancelled\n")
        raise Exit(1)
    title, grade = clean_field(given["--title"]), clean_field(given["--grade"])
    project, link = clean_field(given["--project"]), clean_field(given["--link"])
    was = find_deadline(ident)
    if was:
        write_deadline(ident, given["--due"], title, status, done_at, grade, project, link)
    else:
        os.makedirs(STATE_DIR, exist_ok=True)
        write_text(DEADLINE_FILE, "%d\t%d\t%s\t%s\t%d\t%s\t%s\t%s\n"
                   % (int(ident), int(given["--due"]), title, status, int(done_at), grade, project, link), append=True)
        cmd_deadline_reserve(ident)
    report("deadline #%s %s · %s%s" % (ident, "updated" if was else "added", title,
                                      " (as on %s)" % given["--from"] if given["--from"] else ""))


def cmd_deadline_reserve(ident: str) -> None:
    """The high-water mark at least this: an id another machine handed out is
    never handed out here as well."""
    if not digits(ident):
        err("usage: pomo deadline reserve <id>\n")
        raise Exit(1)
    if int(ident) > read_seq():
        write_text(DEADLINE_SEQ, "%d\n" % int(ident))


def set_usage():
    err("usage: pomo deadline set <id> [--title <t>] [--project <s>] [--link <l>] [<when...>]\n"
        '  e.g. pomo deadline set 1 friday 17:00       (--project "" clears the project)\n')
    raise Exit(1)


def cmd_deadline_set(args: list[str]) -> None:
    """Edited in place: sessions attach to a deadline's id, so a retimed
    deadline keeps its identity."""
    ident = args[0] if args else ""
    if not digits(ident):
        set_usage()
    d = require_deadline(ident, "set")
    title, when, project, link, changed = "", [], d[6], d[7], False
    i = 1
    while i < len(args):
        a = args[i]
        if a in ("--title", "--project", "--subject", "--link"):
            if i + 1 >= len(args):
                set_usage()
            # An explicitly empty value clears the field; no flag keeps it.
            if a == "--title":
                title = args[i + 1]
            elif a == "--link":
                link = args[i + 1]
            else:
                project = args[i + 1]
            changed = True
            i += 1
        elif a == "--when":
            pass
        else:
            when.append(a)
            changed = True
        i += 1
    if not changed:
        set_usage()
    phrase = " ".join(when)
    ts = read_when(phrase) if phrase != "" else d[1]
    title = clean_field(title or d[2])
    project, link = clean_field(project), clean_field(link)
    write_deadline(d[0], ts, title, d[3], d[4], d[5], project, link)
    report("deadline #%s · %s · %s%s" % (d[0], when_text(ts), title, " · " + project if project else ""))


def cmd_deadline_done(args: list[str]) -> None:
    d = require_deadline(args[0] if args else "", "done")
    at = now()
    # --at: when it was done, for a deadline brought back from cancelled.
    if len(args) >= 3 and args[1] == "--at" and digits(args[2]):
        at = args[2]
    if d[3] == "done":
        out("deadline #%s already done\n" % d[0])
        return
    write_deadline(d[0], d[1], d[2], "done", at, d[5], d[6], d[7])
    report("deadline #%s done · %s" % (d[0], d[2]))


def cmd_deadline_reopen(wanted: str) -> None:
    d = require_deadline(wanted, "reopen")
    if d[3] == "open":
        out("deadline #%s already open\n" % d[0])
        return
    write_deadline(d[0], d[1], d[2], "open", 0, d[5], d[6], d[7])
    report("deadline #%s reopened · %s" % (d[0], d[2]))


def cmd_deadline_grade(args: list[str]) -> None:
    ident = args[0] if args else ""
    if not digits(ident):
        err("usage: pomo deadline grade <id> [<grade>]\n  e.g. pomo deadline grade 3 7.5      (no grade clears it)\n")
        raise Exit(1)
    d = require_deadline(ident, "grade")
    grade = " ".join(args[1:]).replace(TAB, " ")
    status, done_at = d[3], d[4]
    # A graded deadline has been handed in: grading an open one marks it done.
    if grade != "" and status == "open":
        status, done_at = "done", now()
    write_deadline(d[0], d[1], d[2], status, done_at, grade, d[6], d[7])
    report("deadline #%s graded %s · %s" % (d[0], grade, d[2]) if grade != "" else "deadline #%s grade cleared · %s" % (d[0], d[2]))


def cmd_deadline_hide(wanted: str) -> None:
    d = require_deadline(wanted, "hide")
    if d[3] == "hidden":
        out("deadline #%s already hidden\n" % d[0])
        return
    # Hiding something never handed in would lose that it was missed: closed out first.
    done_at = d[4] if num(d[4]) > 0 else now()
    write_deadline(d[0], d[1], d[2], "hidden", done_at, d[5], d[6], d[7])
    report("deadline #%s hidden · %s" % (d[0], d[2]))


def cmd_deadline_cancel(wanted: str) -> None:
    """Its line is gone or was cancelled: kept as history, off every list."""
    d = require_deadline(wanted, "cancel")
    if d[3] == "cancelled":
        out("deadline #%s already cancelled\n" % d[0])
        return
    write_deadline(d[0], d[1], d[2], "cancelled", now(), d[5], d[6], d[7])
    report("deadline #%s cancelled · %s" % (d[0], d[2]))


def cmd_deadline_unhide(wanted: str) -> None:
    d = require_deadline(wanted, "unhide")
    if d[3] != "hidden":
        out("deadline #%s is not hidden\n" % d[0])
        return
    write_deadline(d[0], d[1], d[2], "done", d[4], d[5], d[6], d[7])
    report("deadline #%s unhidden · %s" % (d[0], d[2]))


def quoted(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\t", " ")
    return '"' + re.sub(r"[\x00-\x1f]", lambda m: "\\u%04x" % ord(m.group()), s) + '"'


def deadline_object(d) -> str:
    return ('{"id":%d,"due":%d,"title":%s,"status":"%s","done_at":%s,"grade":%s,"project":%s,"link":%s}'
            % (int(num(d[0])), int(num(d[1])), quoted(d[2]), d[3], shown(num(d[4])) if num(d[4]) > 0 else "null",
               "null" if d[5] == "" else quoted(d[5]), quoted(d[6]), quoted(d[7])))


def deadline_json(rows: list) -> str:
    return "[" + ",".join(deadline_object(d) for d in rows) + "]"


def list_usage():
    err("usage: pomo deadline list [--all] [--json] [--project <s>]\n")
    raise Exit(1)


def cmd_deadline_list(args: list[str]) -> None:
    everything = as_json = False
    project = ""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--all":
            everything = True
        elif a == "--json":
            as_json = True
        elif a in ("--project", "--subject"):
            if i + 1 >= len(args):
                list_usage()
            project = args[i + 1]
            i += 1
        elif a != "":
            list_usage()
        i += 1
    if not has_size(DEADLINE_FILE):
        out('{"deadlines":[]}\n' if as_json else 'no deadlines — pomo deadline add "Essay draft" friday\n')
        return
    # Hidden and cancelled only with --all; the project case-insensitive and whole.
    rows = [d for d in sorted_deadlines()
            if (everything or d[3] not in ("hidden", "cancelled")) and (project == "" or d[6].lower() == project.lower())]
    if as_json:
        out('{"deadlines":' + deadline_json(rows) + "}\n")
        return
    for d in rows:
        mark = {"done": "✓", "hidden": "·", "cancelled": "×"}.get(d[3], " ")
        out("%3s %s %-17s %-9s %s%s%s\n" % (d[0], mark, when_text(d[1]), rel_text(d[1]) if d[3] == "open" else d[3],
                                           d[2], " · " + d[6] if d[6] else "", "  [%s]" % d[5] if d[5] else ""))
    if not rows:
        out('nothing for project "%s" — pomo deadline list --all shows hidden ones\n' % project if project
            else "nothing open — pomo deadline list --all shows hidden ones\n")


def cmd_deadline_when(args: list[str]) -> None:
    """How the page reads a date it found in a note: the same forgiving parse
    as add, so a line and the store never disagree on what a phrase means."""
    phrase = " ".join(args)
    if phrase == "":
        err("usage: pomo deadline when <when...>\n")
        raise Exit(1)
    ts = read_when(phrase)
    out("%d\t%s\n" % (ts, when_text(ts)))


def cmd_deadline_rm(wanted: str) -> None:
    d = require_deadline(wanted, "rm")
    replace_store([line for line in records(DEADLINE_FILE) if not same_id(line.split(TAB)[0], d[0])])
    report("deadline #%s removed · %s" % (d[0], d[2]))


def cmd_deadline_next(flag: str) -> None:
    """The soonest open deadline still ahead, else the least late open one."""
    chosen = None
    if has_size(DEADLINE_FILE):
        n = now()
        for d in sorted_deadlines():
            if d[3] != "open":
                continue
            if num(d[1]) >= n:
                chosen = d
                break
            chosen = d
    if not chosen:
        out('{"next":null}\n' if flag == "--json" else "no open deadlines\n")
        return
    if flag == "--json":
        out('{"next":' + deadline_object(chosen) + "}\n")
    else:
        out("#%s  %s  %s  %s%s\n" % (chosen[0], when_text(chosen[1]), rel_text(chosen[1]), chosen[2],
                                    " · " + chosen[6] if chosen[6] else ""))


DEADLINE_USAGE = """usage: pomo deadline add <title> [--project <s>] [--link <url-or-path>] <when...>
                                                # "Essay draft" --project stats next friday 17:00
       pomo deadline set <id> [--title <t>] [--project <s>] [--link <l>] [<when...>]
                                                # --project "" clears the project
       pomo deadline list [--all] [--json] [--project <s>]   # --all includes hidden
       pomo deadline done|reopen <id>           # submitted / back to open
       pomo deadline grade <id> [<grade>]       # record the mark (marks done); no grade clears it
       pomo deadline hide|unhide <id>           # keep the record, drop it from the list
       pomo deadline cancel <id>                # its line is gone: history, off every list
       pomo deadline rm <id>                    # delete outright
       pomo deadline reserve <id>               # never hand out ids up to this one (another machine has them)
       pomo deadline put <id> --due <epoch> --title <t> --status <s> [--done-at <n>] [--grade <g>] [--project <p>] [--link <l>]
                                                # the whole record as given (the sync between machines)
       pomo deadline next [--json]              # the one the bar counts down to
       pomo deadline when <when...>             # how a date phrase reads: epoch<TAB>text
"""


def lock_store():
    """One writer at a time: the page, the popup and the agent can all call in
    at once. The lock lives beside the file; ten seconds, then "busy"."""
    os.makedirs(STATE_DIR, exist_ok=True)
    handle = open(DEADLINE_FILE + ".lock", "w")
    deadline = time.monotonic() + 10
    while True:
        try:
            if os.name == "nt":
                import msvcrt
                # Windows locks are mandatory and by byte: one byte far past
                # the end, which nothing reads (as windows/pyshim/fcntl.py).
                os.lseek(handle.fileno(), 1 << 30, os.SEEK_SET)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except OSError:
            if time.monotonic() >= deadline:
                err("pomo: the deadline store is busy, try again\n")
                raise Exit(1) from None
            time.sleep(0.05)


def cmd_deadline(args: list[str]) -> None:
    sub = args[0] if args else "list"
    rest = args[1:]
    first = rest[0] if rest else ""
    lock = lock_store() if sub in WRITES else None
    if sub == "add":
        cmd_deadline_add(rest)
    elif sub in ("set", "edit"):
        cmd_deadline_set(rest)
    elif sub in ("list", "ls"):
        cmd_deadline_list(rest)
    elif sub in ("done", "submit"):
        cmd_deadline_done(rest)
    elif sub in ("undone", "reopen"):
        cmd_deadline_reopen(first)
    elif sub == "grade":
        cmd_deadline_grade(rest)
    elif sub == "hide":
        cmd_deadline_hide(first)
    elif sub == "cancel":
        cmd_deadline_cancel(first)
    elif sub in ("unhide", "show"):
        cmd_deadline_unhide(first)
    elif sub in ("rm", "remove"):
        cmd_deadline_rm(first)
    elif sub == "reserve":
        cmd_deadline_reserve(first)
    elif sub == "put":
        cmd_deadline_put(rest)
    elif sub == "next":
        cmd_deadline_next(first)
    elif sub == "when":
        cmd_deadline_when(rest)
    elif sub in ("--json", "--all", "--project", "--subject"):
        cmd_deadline_list(args)
    elif sub in ("help", "-h", "--help"):
        out(DEADLINE_USAGE)
    else:
        err(DEADLINE_USAGE)
        raise Exit(1)
    if sub in CHECKED:
        # Typed by hand in a terminal: the note lines follow at once. The page
        # and the popup run the check themselves, with LONGHAND_NO_CHECK set.
        if sys.stdout.isatty() and not os.environ.get("LONGHAND_NO_CHECK") and shutil.which("longhand-check"):
            if lock:
                lock.close()
            try:
                subprocess.run(["longhand-check", "--quiet"])
            except OSError:
                pass


def cmd_report(flag: str) -> None:
    """Everything an agent needs in one call. Hidden deadlines are included:
    they are the graded history."""
    if flag != "--json":
        err("usage: pomo report --json\n")
        raise Exit(1)

    def path(p: str) -> str:
        return p.replace("\\", "\\\\").replace('"', '\\"')
    out('{"generated_at":%d,"timer":%s,"stats":%s,"deadlines":%s,"files":{"state":"%s","log":"%s","deadlines":"%s"}}\n'
        % (now(), cmd_status().rstrip("\n"), stats_json().rstrip("\n"),
           deadline_json(sorted_deadlines()) if has_size(DEADLINE_FILE) else "[]",
           path(STATE_FILE), path(LOG_FILE), path(DEADLINE_FILE)))


def usage() -> None:
    err("usage: pomo start [focus|break|up] [minutes|up] [--for <deadline id>] | pause | resume | toggle | reset | skip | status"
        " | stats [day|week|month|--json] | bell | autostart [on|off|toggle] | expired | report --json\n"
        "       pomo deadline add|set|list|done|reopen|grade|hide|unhide|rm|next  (pomo deadline help)\n")


def main(argv: list[str]) -> int:
    try:
        import locale
        if os.name != "nt":
            locale.setlocale(locale.LC_TIME, "")     # weekday and month names as `date` gives them
    except Exception:
        pass
    os.makedirs(STATE_DIR, exist_ok=True)
    load_lengths()
    try:
        ensure_state()
        command = argv[0] if argv else ""
        rest = argv[1:]
        if command == "start":
            cmd_start(rest)
        elif command == "pause":
            cmd_pause()
        elif command == "resume":
            cmd_resume()
        elif command == "toggle":
            cmd_toggle()
        elif command == "reset":
            cmd_reset()
        elif command == "skip":
            cmd_skip()
        elif command == "status":
            out(cmd_status())
        elif command == "stats":
            cmd_stats((rest[0] if rest else "") or "day")
        elif command == "bell":
            cmd_bell()
        elif command == "autostart":
            cmd_autostart((rest[0] if rest else "") or "status")
        elif command == "expired":
            cmd_expired()
        elif command == "report":
            cmd_report(rest[0] if rest else "")
        elif command in ("deadline", "deadlines"):
            cmd_deadline(rest)
        elif command in ("-h", "--help", "help", ""):
            usage()
            return 1
        else:
            err("unknown command: %s\n" % command)
            usage()
            return 1
    except Exit as e:
        return e.code
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
