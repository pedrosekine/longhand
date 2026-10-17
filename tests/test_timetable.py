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


# The shape Exchange/Outlook publishes (2026-10-17, the student's real
# feed): Windows zone names, a moved occurrence, UNTIL in UTC, and meetings
# that are off said in the title and by TRANSP rather than by STATUS.
OUTLOOK = """BEGIN:VCALENDAR\r
PRODID:Microsoft Exchange Server 2010\r
BEGIN:VEVENT\r
UID:jf\r
DTSTART;TZID=W. Europe Standard Time:20260922T121500\r
DTEND;TZID=W. Europe Standard Time:20260922T131500\r
RRULE:FREQ=WEEKLY;UNTIL=20261020T101500Z;INTERVAL=2;BYDAY=TU;WKST=MO\r
SUMMARY:Jour Fixe\r
STATUS:CONFIRMED\r
TRANSP:OPAQUE\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:jf\r
RECURRENCE-ID;TZID=W. Europe Standard Time:20261006T121500\r
DTSTART;TZID=W. Europe Standard Time:20261005T150000\r
DTEND;TZID=W. Europe Standard Time:20261005T160000\r
SUMMARY:Jour Fixe\r
STATUS:CONFIRMED\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:x1\r
DTSTART;TZID=W. Europe Standard Time:20261201T161500\r
DTEND;TZID=W. Europe Standard Time:20261201T171500\r
SUMMARY:Canceled: Open Lab Day\r
STATUS:CONFIRMED\r
TRANSP:TRANSPARENT\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:x2\r
DTSTART;TZID=W. Europe Standard Time:20261106T140000\r
DTEND;TZID=W. Europe Standard Time:20261106T150000\r
SUMMARY:Abgesagt: Workshop\r
STATUS:CONFIRMED\r
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

    # The machine's own zone, with its rules: a weekly class keeps its hour
    # across the change of clocks on 25 Oct (a fixed offset put the winter
    # ones an hour out, whichever season it was read in).
    os.environ["TZ"] = "Europe/Vienna"
    check(str(timetable.local_zone()) == "Europe/Vienna", "local time is this machine's zone, not today's offset")
    rp = [e["start"] for e in timetable.parse(FIXED) if e["summary"].startswith("Research")]
    check([t.time() for t in rp] == [dt.time(13, 15)] * 3 and rp[0].month == 10 and rp[-1].month == 11,
          f"a class keeps its hour on both sides of the clocks changing ({[t.isoformat() for t in rp]})")

    # Outlook's way of saying the same things.
    ol = timetable.parse(OUTLOOK, local=ZoneInfo("Asia/Tokyo"))
    jf = [e["start"] for e in ol if e["summary"] == "Jour Fixe"]
    check(jf[0] == dt.datetime(2026, 9, 22, 19, 15),
          f"a Windows zone name is read as its zone, not as local time (in Tokyo: {jf[0]})")
    ol = timetable.parse(OUTLOOK, local=VIENNA)
    jf = [e["start"] for e in ol if e["summary"] == "Jour Fixe"]
    check(jf == [dt.datetime(2026, 9, 22, 12, 15), dt.datetime(2026, 10, 5, 15, 0), dt.datetime(2026, 10, 20, 12, 15)],
          f"a moved occurrence stands in for its slot, and UNTIL in UTC keeps the last one ({[d.isoformat() for d in jf]})")
    check(not any(e["summary"].startswith(("Canceled", "Abgesagt")) for e in ol),
          "a meeting that is off — said in its title or marked free — is not a session")

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
    Uni.status, Uni.body, Uni.etag = 200, b"<html><p>Maintenance</p></html>", '"v2"'
    r = timetable.refresh(url, cache, now=t0 + 9000)
    check(r == "failed: not a calendar" and cache.read_bytes() == FIXED.encode(), f"a page that is not a calendar never replaces it ({r})")
    Uni.body = b"<html><title>Sign in to your account</title></html>"
    r = timetable.refresh(url, cache, now=t0 + 9500)
    check(r == "failed: asks to sign in", f"a sign-in page where the calendar should be is named as one ({r})")

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
    check("Something else entirely" not in payload,
          "…and nothing that is not a class: a feed can be a whole personal calendar, and the rest stays here")
    check(f"Weekdays with no class:" in payload and f"{today + dt.timedelta(days=5):%a %d %b}" in payload.split("Weekdays with no class:")[1]
          or (today + dt.timedelta(days=5)).weekday() >= 5,
          "…and the weekdays with no class, counting only classes")
    check("SECRET" not in payload, "…and never the feed's address")
    hits = len(Uni.hits)
    agent("context", "--trigger", "open")
    check(len(Uni.hits) == hits, "a pass never fetches: it reads the copy kept")

    # The Settings sheet: the address in settings.json, the page's own file,
    # read over the config; and what the sheet is told.
    cfg.write_text(json.dumps(base))
    settings = cfg.with_name("settings.json")
    settings.write_text(json.dumps({"timetable": url, "vault": "/somewhere/else"}))
    st = json.loads(agent("timetable", "--fetch"))
    check(st["configured"] and st["result"] in ("fetched", "unchanged") and st["sessions"] == 2,
          f"an address saved in the sheet is read, and fetched on asking ({st['result']}, {st['sessions']})")
    check(st["address"] == f"127.0.0.1:{server.server_port}/…" and "SECRET" not in json.dumps(st),
          f"the sheet is shown where it goes, not its token ({st['address']})")
    sem = next(c for c in st["courses"] if c["name"] == "Interdisciplinary Seminar")
    check(sem["sessions"] == 1 and any(c["name"] == "Thesis" and c["code"] == "" for c in st["courses"]),
          "it says which courses the feed knows, and which have no code to match by")
    check(st["other"] == ["Something else entirely"], "…and the sessions it could not name")
    pr = {p["tag"]: p for p in json.loads(agent("projects"))}
    check(pr["intsem"]["next"]["room"] == "Bronze", "the sidebar follows it")
    check(json.loads(agent("timetable"))["result"] == "", "without --fetch, nothing is fetched")
    hits = len(Uni.hits)
    st = json.loads(agent("timetable"))
    check(len(Uni.hits) == hits, "…not even once")

    # Another address: the old copy is no copy.
    other = url.replace("feed.ics", "other.ics")
    settings.write_text(json.dumps({"timetable": other}))
    Uni.status = 404
    st = json.loads(agent("timetable", "--fetch"))
    check(st["error"] == "HTTP 404" and st["sessions"] == 0 and st["copy"] is False,
          f"a new address that fails never shows the old one's sessions ({st['error']}, {st['sessions']})")
    pr = {p["tag"]: p for p in json.loads(agent("projects"))}
    check(pr["intsem"]["next"]["room"] == "Stale copy", "…and the sidebar falls back to the knowledge files")
    Uni.status = 200
    check(timetable.http_url("webcal://uni.example/f.ics?t=1") == "https://uni.example/f.ics?t=1"
          and timetable.http_url("https://uni.example/f.ics") == "https://uni.example/f.ics",
          "a webcal:// address, as calendars hand them out, is fetched over https")
    settings.write_text(json.dumps({"timetable": url}))
    st = json.loads(agent("timetable", "--fetch"))
    check(st["sessions"] == 2 and st["error"] == "", "the first address again: fetched afresh")

    # Removed: no address, no copy.
    settings.write_text(json.dumps({"timetable": ""}))
    st = json.loads(agent("timetable", "--forget"))
    check(not st["configured"] and not (tmp / "xdg" / "longhand" / "timetable.ics").exists(),
          "removing the address drops the copy")

    server.shutdown()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
