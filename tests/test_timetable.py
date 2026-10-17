"""The timetable feed (agent/timetable.py): read the way a university feed
writes it, fetched only when stale and only for what changed, and used by
the sidebar and the agent in place of the session lines in the knowledge
files — which stay the fallback.

A throwaway HTTP server plays the university; nothing leaves the machine.

Run: python3 tests/test_timetable.py
"""
import datetime as dt
import http.server
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import threading
from zoneinfo import ZoneInfo

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
import timetable  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


VIENNA = ZoneInfo("Europe/Vienna")

FIXED = """BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:-//University//Timetable//EN\r
BEGIN:VEVENT\r
UID:1@uni\r
DTSTART;TZID=Europe/Vienna:20261012T104500\r
DTEND;TZID=Europe/Vienna:20261012T121500\r
SUMMARY:Interdisciplinary Seminar (M_IC_IntSem_W26)\r
LOCATION:Gold\\, Building A\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:2@uni\r
DTSTART:20261013T120000Z\r
DTEND:20261013T133000Z\r
SUMMARY:Design Theory\r
DESCRIPTION:Course M_IC_DTM_Spe_W26\\nweekly lecture with a long descrip\r
 tion folded onto a second line\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:3@uni\r
DTSTART;VALUE=DATE:20261026\r
SUMMARY:National holiday\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:4@uni\r
DTSTART;TZID=Europe/Vienna:20261014T090000\r
DTEND;TZID=Europe/Vienna:20261014T100000\r
SUMMARY:Cancelled one\r
STATUS:CANCELLED\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:5@uni\r
DTSTART;TZID=Europe/Vienna:20261015T131500\r
DURATION:PT2H30M\r
RRULE:FREQ=WEEKLY;COUNT=4;BYDAY=TH\r
EXDATE;TZID=Europe/Vienna:20261022T131500\r
SUMMARY:Research Proficiency M_IC_ResPro_W26\r
END:VEVENT\r
END:VCALENDAR\r
"""


def relative_feed(today: dt.date) -> str:
    """Sessions around today, for the parts that ask for "next"."""
    def ev(uid, day, a, b, summary, room):
        return (f"BEGIN:VEVENT\r\nUID:{uid}\r\nDTSTART;TZID=Europe/Vienna:{day:%Y%m%d}T{a}00\r\n"
                f"DTEND;TZID=Europe/Vienna:{day:%Y%m%d}T{b}00\r\nSUMMARY:{summary}\r\nLOCATION:{room}\r\nEND:VEVENT\r\n")
    return ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
            + ev("a", today - dt.timedelta(days=3), "1045", "1215", "Interdisciplinary Seminar M_IC_IntSem_W26", "Gold")
            + ev("b", today + dt.timedelta(days=2), "1045", "1215", "Interdisciplinary Seminar M_IC_IntSem_W26", "Bronze")
            + ev("c", today + dt.timedelta(days=5), "0900", "1030", "Something else entirely", "Room 9")
            + "END:VCALENDAR\r\n")


class Uni(http.server.BaseHTTPRequestHandler):
    body = b""
    etag = '"v1"'
    status = 200
    hits: list = []

    def do_GET(self):
        Uni.hits.append(dict(self.headers))
        if Uni.status != 200:
            self.send_response(Uni.status)
            self.end_headers()
            return
        if self.headers.get("If-None-Match") == Uni.etag:
            self.send_response(304)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("ETag", Uni.etag)
        self.send_header("Content-Type", "text/calendar")
        self.end_headers()
        self.wfile.write(Uni.body)

    def log_message(self, *a):
        pass


def main() -> int:
    # Reading a feed.
    ev = timetable.parse(FIXED, local=VIENNA)
    by = {e["summary"]: e for e in ev}
    sem = by["Interdisciplinary Seminar (M_IC_IntSem_W26)"]
    check(sem["start"] == dt.datetime(2026, 10, 12, 10, 45) and sem["end"] == dt.datetime(2026, 10, 12, 12, 15),
          f"a time with its zone, as local time ({sem['start']})")
    check(sem["location"] == "Gold, Building A", "escaped commas read back")
    dtm = by["Design Theory"]
    check(dtm["start"] == dt.datetime(2026, 10, 13, 14, 0), f"a UTC time moved into local time ({dtm['start']})")
    check("tion folded onto a second line" in dtm["text"] and timetable.matches(dtm, "M_IC_DTM_Spe_W26"),
          "a folded description is one line, and a code in it is found")
    check("National holiday" not in by and "Cancelled one" not in by, "all-day and cancelled events are not sessions")
    rp = [e for e in ev if e["summary"].startswith("Research")]
    check([e["start"].date() for e in rp] == [dt.date(2026, 10, 15), dt.date(2026, 10, 29), dt.date(2026, 11, 5)],
          f"a weekly rule, counted, with a date taken out ({[e['start'].date().isoformat() for e in rp]})")
    check(all(e["end"] - e["start"] == dt.timedelta(hours=2, minutes=30) for e in rp), "a duration instead of an end")
    check(ev == sorted(ev, key=lambda e: e["start"]), "soonest first")

    # Fetching: only when stale, and only what changed.
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="timetable-"))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Uni)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/feed.ics?token=SECRET"
    cache = tmp / "state" / "timetable.ics"
    Uni.body = FIXED.encode()
    t0 = 1_800_000_000
    check(timetable.refresh(url, cache, now=t0) == "fetched" and cache.read_bytes() == FIXED.encode(), "first open: fetched and kept")
    check(timetable.refresh(url, cache, now=t0 + 600) == "fresh" and len(Uni.hits) == 1, "within the hour: not asked again")
    check(timetable.refresh(url, cache, now=t0 + 4000) == "unchanged" and Uni.hits[-1].get("If-None-Match") == '"v1"',
          "an hour on: asked whether it changed, and it had not")
    Uni.status = 500
    r = timetable.refresh(url, cache, now=t0 + 8000)
    check(r.startswith("failed") and cache.read_bytes() == FIXED.encode(), f"the university down: the kept copy stays ({r})")
    check("SECRET" not in r and "SECRET" not in (tmp / "state" / "timetable.json").read_text(),
          "the address, which may carry a token, is never written down")
    Uni.status, Uni.body, Uni.etag = 200, b"<html>login</html>", '"v2"'
    r = timetable.refresh(url, cache, now=t0 + 9000)
    check(r.startswith("failed") and cache.read_bytes() == FIXED.encode(), "a page that is not a calendar never replaces it")

    # The sidebar and the agent, through the runner.
    today = dt.date.today()
    Uni.body, Uni.etag = relative_feed(today).encode(), '"v3"'
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    pd = vault / "agents/longhand/knowledge/projects"
    pd.mkdir(parents=True)
    (pd / "intsem.md").write_text("# Interdisciplinary Seminar\n\n- Tag: `#intsem`\n- Course code: M_IC_IntSem_W26\n"
                                  f"  - {today + dt.timedelta(days=1):%a %d %b}: 08:00–09:00 (Stale copy)\n")
    (pd / "thesis.md").write_text("# Thesis\n\n- Tag: `#thesis`\n"
                                  f"  - {today + dt.timedelta(days=3):%a %d %b}: 10:00–11:00 (Lab)\n")
    cfg = tmp / "config.json"
    base = {"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"}}
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "xdg"))

    def agent(*args):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr
        return r.stdout

    cfg.write_text(json.dumps(base))
    pr = {p["tag"]: p for p in json.loads(agent("projects"))}
    check(pr["intsem"]["next"]["room"] == "Stale copy", "no feed configured: the knowledge file's lines, as before")

    cfg.write_text(json.dumps({**base, "timetable": url}))
    pr = {p["tag"]: p for p in json.loads(agent("projects"))}
    soon = today + dt.timedelta(days=2)
    check(pr["intsem"]["next"]["at"] == f"{soon.isoformat()}T10:45" and pr["intsem"]["next"]["room"] == "Bronze",
          f"with a feed: the next session is the university's, matched by course code ({pr['intsem']['next']})")
    check(pr["thesis"]["next"]["room"] == "Lab", "a project the feed does not know keeps its own lines")
    check((tmp / "xdg" / "longhand" / "timetable.ics").exists(), "the copy is kept in the state folder")

    (vault / "Daily" / f"{today.isoformat()}.md").write_text("A line of today.\n")
    payload = agent("context", "--trigger", "open")
    check("# Timetable" in payload and f"{soon:%a %d %b} 10:45–12:15 Interdisciplinary Seminar #intsem (Bronze)" in payload,
          "the agent sees the next two weeks, each session named by its course")
    check("Something else entirely" in payload, "…and sessions it cannot name, by the feed's own words")
    check("Weekdays with no session:" in payload, "…and the weekdays that are free")
    check("SECRET" not in payload, "…and never the feed's address")
    hits = len(Uni.hits)
    agent("context", "--trigger", "open")
    check(len(Uni.hits) == hits, "a pass never fetches: it reads the copy kept")

    server.shutdown()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
