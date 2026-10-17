"""The university timetable, pulled from its .ics feed (2026-10-11/17).

Pull, never push: when the page or its sidebar opens (`longhand-agent
projects`) and the copy kept here is older than an hour, the feed is asked
again — conditionally, so an unchanged timetable costs a 304 and nothing
else. Nothing watches in the background (the watcher was refused on
2026-09-17). The copy lives in the state folder, a file the model cannot
rewrite, so an agent edit can never drop a schedule; the session lines in
the agent's knowledge files stay as the fallback when there is no feed.

The feed's address is the student's, from the university portal: it goes
in the local config (`"timetable"`), never the repo, and is never printed —
it can carry a token.

Courses are matched by the code their knowledge file names (`Course code:
M_IC_IntSem_W26`) appearing anywhere in an event.

Only what a timetable needs from iCalendar is read: VEVENTs with a start
and an end, their summary, location and description, times in UTC, with a
TZID or floating; and the recurrences a timetable uses (DAILY and WEEKLY,
INTERVAL, COUNT, UNTIL, BYDAY, EXDATE). All-day events are not sessions.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MAX_AGE = 3600          # seconds a fetched copy is good for
TIMEOUT = 5             # seconds the sidebar may wait for the university
HORIZON = 400           # days of a recurrence expanded, at most

DAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


# ------------------------------------------------------------------ fetch

def meta_of(cache: Path) -> dict:
    try:
        return json.loads(cache.with_suffix(".json").read_text())
    except (OSError, ValueError):
        return {}


def _write(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def refresh(url: str, cache: Path, now: float | None = None, max_age: int = MAX_AGE) -> str:
    """Bring the kept copy up to date if it is older than `max_age`. Says
    what happened: "fresh", "unchanged", "fetched", or "failed: …" — in
    which case the copy kept is used as it is."""
    now = now if now is not None else time.time()
    meta = meta_of(cache)
    # A copy from another address is no copy: the address was changed.
    source = _source(url)
    url = http_url(url)
    if meta.get("source") != source:
        forget(cache)
        meta = {}
    if cache.exists() and now - meta.get("fetched", 0) < max_age:
        return "fresh"
    req = urllib.request.Request(url, headers={"User-Agent": "longhand"})
    if cache.exists():
        if meta.get("etag"):
            req.add_header("If-None-Match", meta["etag"])
        if meta.get("modified"):
            req.add_header("If-Modified-Since", meta["modified"])
    cache.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            body = r.read()
            if b"BEGIN:VCALENDAR" not in body[:2048]:
                # A sign-in page where a calendar should be: the address is
                # right but the university wants a login for it (IT:U's
                # redirects to /sso/login, then Microsoft's "Sign in").
                signin = re.search(r"sso|login|signin|oauth", r.geturl(), re.I) \
                    or re.search(rb"sign.?in|log.?in", body[:8192], re.I)
                raise ValueError("asks to sign in" if signin else "not a calendar")
            _write(cache, body)
            meta = {"fetched": now, "source": source, "etag": r.headers.get("ETag", ""),
                    "modified": r.headers.get("Last-Modified", "")}
            what = "fetched"
    except urllib.error.HTTPError as e:
        meta["source"] = source
        if e.code != 304:
            meta["error"] = f"HTTP {e.code}"
            _write(cache.with_suffix(".json"), json.dumps(meta).encode())
            return f"failed: HTTP {e.code}"
        meta["fetched"] = now
        meta.pop("error", None)
        what = "unchanged"
    except (OSError, ValueError) as e:
        # Never the address: it may carry a token.
        reason = _reason(e)
        meta["source"] = source
        meta["error"] = reason
        _write(cache.with_suffix(".json"), json.dumps(meta).encode())
        return f"failed: {reason}"
    _write(cache.with_suffix(".json"), json.dumps(meta).encode())
    return what


def _source(url: str) -> str:
    """Which address a copy came from, without keeping the address."""
    return hashlib.sha256(url.encode()).hexdigest()[:16]


def _reason(e: Exception) -> str:
    """Why a fetch failed, in words, and never with the address in them."""
    if isinstance(e, ValueError):
        return str(e)
    r = getattr(e, "reason", None)
    if isinstance(r, TimeoutError) or isinstance(e, TimeoutError):
        return "the university did not answer"
    if isinstance(r, OSError) and getattr(r, "errno", None) in (-2, -3, -5):
        return "no such address (or no network)"
    if isinstance(r, ConnectionRefusedError):
        return "the connection was refused"
    return type(r).__name__ if r is not None else type(e).__name__


def http_url(url: str) -> str:
    """webcal://, as calendar apps hand feeds out, is https underneath."""
    return "https://" + url[len("webcal://"):] if url.lower().startswith("webcal://") else url


def forget(cache: Path) -> None:
    for p in (cache, cache.with_suffix(".json")):
        try:
            p.unlink()
        except FileNotFoundError:
            pass


def masked(url: str) -> str:
    """An address as the Settings sheet shows it once saved: where it goes,
    not the token it may carry."""
    m = re.match(r"^\w+://([^/?#]+)", url or "")
    return (m.group(1) + "/…") if m else ""


# ------------------------------------------------------------------ parse

def _unfold(text: str) -> list[str]:
    out: list[str] = []
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if line[:1] in (" ", "\t") and out:
            out[-1] += line[1:]
        elif line:
            out.append(line)
    return out


def _unescape(v: str) -> str:
    return re.sub(r"\\([\\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), v)


def _prop(line: str) -> tuple[str, dict, str]:
    head, _, value = line.partition(":")
    name, *params = head.split(";")
    ps = {}
    for p in params:
        k, _, v = p.partition("=")
        ps[k.upper()] = v.strip('"')
    return name.upper(), ps, value


def _when(value: str, params: dict, local: dt.tzinfo) -> dt.datetime | None:
    """A DATE-TIME as a naive local time; None for an all-day DATE."""
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return None
    m = re.fullmatch(r"(\d{8})T(\d{4})(\d{2})?(Z?)", value)
    if not m:
        return None
    t = dt.datetime.strptime(m.group(1) + m.group(2) + (m.group(3) or "00"), "%Y%m%d%H%M%S")
    if m.group(4):
        t = t.replace(tzinfo=dt.timezone.utc)
    elif params.get("TZID"):
        try:
            t = t.replace(tzinfo=ZoneInfo(params["TZID"]))
        except (ZoneInfoNotFoundError, ValueError):
            return t
    else:
        return t
    return t.astimezone(local).replace(tzinfo=None)


def _expand(start: dt.datetime, rule: str, exdates: set[dt.datetime]) -> list[dt.datetime]:
    r = dict(p.partition("=")[::2] for p in rule.split(";") if "=" in p)
    freq = r.get("FREQ", "")
    if freq not in ("DAILY", "WEEKLY"):
        return [start]
    step = max(1, int(r.get("INTERVAL", "1") or 1))
    count = int(r["COUNT"]) if r.get("COUNT", "").isdigit() else None
    until = None
    if r.get("UNTIL"):
        u = re.match(r"(\d{8})(?:T(\d{6}))?", r["UNTIL"])
        if u:
            until = dt.datetime.strptime(u.group(1) + (u.group(2) or "235959"), "%Y%m%d%H%M%S")
    days = sorted(DAYS[d[-2:]] for d in r.get("BYDAY", "").split(",") if d[-2:] in DAYS) \
        if freq == "WEEKLY" else []
    if not days and freq == "WEEKLY":
        days = [start.weekday()]
    out: list[dt.datetime] = []
    end = start + dt.timedelta(days=HORIZON)
    if freq == "DAILY":
        cands = (start + dt.timedelta(days=i * step) for i in range(HORIZON))
    else:
        week0 = start - dt.timedelta(days=start.weekday())
        cands = (week0 + dt.timedelta(weeks=w * step, days=d)
                 for w in range(HORIZON // 7 + 1) for d in days)
    seen = 0
    for c in cands:
        if c < start:
            continue
        if c > end or (until and c > until) or (count is not None and seen >= count):
            break
        seen += 1
        if c not in exdates:
            out.append(c)
    return out


def parse(text: str, local: dt.tzinfo | None = None) -> list[dict]:
    """Every session in a feed, soonest first: start and end (naive, local
    time), summary, location, and all of its text for matching codes."""
    local = local or dt.datetime.now().astimezone().tzinfo
    out: list[dict] = []
    ev: dict | None = None
    for line in _unfold(text):
        if line == "BEGIN:VEVENT":
            ev = {"exdates": set(), "text": []}
            continue
        if ev is None:
            continue
        if line == "END:VEVENT":
            start, end = ev.get("start"), ev.get("end")
            if start and (end or ev.get("duration")) and ev.get("status") != "CANCELLED":
                length = (end - start) if end else ev["duration"]
                starts = _expand(start, ev["rrule"], ev["exdates"]) if ev.get("rrule") else [start]
                for s in starts:
                    out.append({"start": s, "end": s + length, "summary": ev.get("summary", ""),
                                "location": ev.get("location", ""), "text": " ".join(ev["text"])})
            ev = None
            continue
        name, params, value = _prop(line)
        if name == "DTSTART":
            ev["start"] = _when(value, params, local)
        elif name == "DTEND":
            ev["end"] = _when(value, params, local)
        elif name == "DURATION":
            m = re.fullmatch(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?", value)
            if m:
                ev["duration"] = dt.timedelta(days=int(m.group(1) or 0), hours=int(m.group(2) or 0),
                                              minutes=int(m.group(3) or 0))
        elif name == "RRULE":
            ev["rrule"] = value
        elif name == "EXDATE":
            for v in value.split(","):
                t = _when(v, params, local)
                if t:
                    ev["exdates"].add(t)
        elif name == "STATUS":
            ev["status"] = value.upper()
        elif name in ("SUMMARY", "LOCATION", "DESCRIPTION", "CATEGORIES", "UID"):
            v = _unescape(value)
            if name in ("SUMMARY", "LOCATION"):
                ev[name.lower()] = v.strip()
            ev["text"].append(v)
    out.sort(key=lambda e: e["start"])
    return out


# ------------------------------------------------------------------ use

def cache_path(state_home: Path) -> Path:
    return state_home / "timetable.ics"


def sessions(cfg: dict, state_home: Path, fetch: bool = True) -> list[dict] | None:
    """The sessions in the kept copy, brought up to date first when `fetch`
    (the sidebar opening). None when no feed is configured, or none has
    ever been fetched — the knowledge files' lines are used then."""
    url = (cfg.get("timetable") or "").strip()
    if not url:
        return None
    cache = cache_path(state_home)
    if not fetch and meta_of(cache).get("source") != _source(url):
        return None      # a copy from another address, or none yet
    if fetch:
        refresh(url, cache)
    try:
        text = cache.read_text(errors="replace")
    except OSError:
        return None
    return parse(text)


def matches(event: dict, code: str) -> bool:
    return bool(code) and code.lower() in (event["summary"] + " " + event["text"]).lower()
