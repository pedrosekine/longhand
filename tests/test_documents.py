"""Course documents (docs/agent.md, slice 4): the Downloads inbox matched
to courses by name, first pages or class time; nothing else listed or
remembered; filing as a proposal; the course's index for the sidebar and
the agent — against a throwaway inbox, vault and state.

Run: python3 tests/test_documents.py
"""
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import tempfile

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


def pdf(path: pathlib.Path, text: str, title: str = "", when: dt.datetime | None = None) -> None:
    """A one-page PDF whose text pdftotext reads back."""
    stream = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET".encode()
    info = f"<< /Title ({title}) >>" if title else "<< >>"
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            info.encode()]
    out = bytearray(b"%PDF-1.4\n")
    offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offs)
    out += b"trailer\n<< /Size %d /Root 1 0 R /Info 6 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    path.write_bytes(bytes(out))
    if when:
        os.utime(path, (when.timestamp(), when.timestamp()))


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="docs-test-"))
    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    know = vault / "agents/longhand/knowledge/projects"
    know.mkdir(parents=True)
    (know / "dtm.md").write_text("# Design Theory & Methods\n\n- Tag: `#dtm`\n- Course code: M_IC_DTM_Spe_W26\n")
    (know / "hfpi.md").write_text("# Human Factors & Psychology of Interaction\n\n- Tag: `#hfpi`\n- Course code: M_IC_HFPI_Spe_W26\n")
    (know / "intsem.md").write_text("# Interdisciplinary Seminar\n\n- Tag: `#intsem`\n- Course code: M_IC_IntSem_W26\n")

    inbox = tmp / "Downloads"
    inbox.mkdir()
    yday = dt.date.today() - dt.timedelta(days=1)
    in_class = dt.datetime.combine(yday, dt.time(11, 30))
    pdf(inbox / "DTM_week2_reading.pdf", "Some reading")
    pdf(inbox / "PIC_Ethnographic_Methods.pdf", "Slides for Human Factors and Psychology of Interaction", title="Ethnographic Methods")
    pdf(inbox / "The_Seven_Deadly_Myths.pdf", "On autonomy", title="The Seven Deadly Myths of &quot;Autonomous Systems&quot;", when=in_class)
    pdf(inbox / "The_Seven_Deadly_Myths (1).pdf", "On autonomy", title="The Seven Deadly Myths of &quot;Autonomous Systems&quot;", when=in_class)
    (inbox / "The_Seven_Deadly_Myths (1).pdf").write_bytes((inbox / "The_Seven_Deadly_Myths.pdf").read_bytes())
    os.utime(inbox / "The_Seven_Deadly_Myths (1).pdf", (in_class.timestamp(), in_class.timestamp()))
    pdf(inbox / "Rechnung_2026_4711.pdf", "Invoice total 120 EUR")
    pdf(inbox / "Meldezettel_ID_998877.pdf", "Identity certificate")
    pdf(inbox / "Design_Theory_old_handout.pdf", "old", when=dt.datetime.now() - dt.timedelta(days=200))

    state = tmp / "state"
    cfgdir = tmp / "config"
    cfgdir.mkdir()
    cfg = cfgdir / "config.json"
    url = "https://uni.example/feed.ics?token=SECRET"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "inbox": str(inbox),
                               "calendars": [{"name": "IT:U", "url": url, "agent": "classes"}]}))
    cache = timetable.cache_path(state / "longhand", url)
    cache.parent.mkdir(parents=True)
    cache.write_text("BEGIN:VCALENDAR\r\n"
                     f"BEGIN:VEVENT\r\nUID:a\r\nDTSTART:{yday:%Y%m%d}T104500\r\nDTEND:{yday:%Y%m%d}T121500\r\n"
                     "SUMMARY:Seminar M_IC_IntSem_W26\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    cache.with_suffix(".json").write_text(json.dumps({"fetched": 1, "source": timetable._source(url)}))
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir))

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    out = json.loads(agent("proposals").stdout)
    files = [x for x in out["open"] if x["kind"] == "file"]
    by = {x["project"]: x for x in files}
    check(len(files) == 3, f"three documents proposed for filing ({[x['name'] for x in files]})")
    check(by.get("dtm", {}).get("why", "").startswith("its name says Design Theory"), "one by its name")
    check("first page names Human Factors" in by.get("hfpi", {}).get("why", ""), "one by its first page (& read as and)")
    check("downloaded during Interdisciplinary Seminar" in by.get("intsem", {}).get("why", ""), "one by the class it was downloaded in")
    check(by.get("intsem", {}).get("name") == f"{yday.isoformat()} The Seven Deadly Myths of Autonomous Systems.pdf",
          f"…named by its date and its own title, cleaned ({by.get('intsem', {}).get('name')})")
    check(by.get("hfpi", {}).get("name", "").endswith(" Ethnographic Methods.pdf"), "…or by its title when it has one")
    check(by.get("dtm", {}).get("name", "").endswith(" DTM week2 reading.pdf"), "…else by its file name, made readable")
    shown = json.dumps(out) + (state / "longhand" / "inbox.json").read_text() + (state / "longhand" / "proposals.json").read_text()
    check(not any(w in shown for w in ("Rechnung", "Meldezettel", "998877", "4711")),
          "an invoice and an ID are never listed, named or remembered")
    check("old_handout" not in shown, "a download older than the semester is not looked at")

    again = json.loads(agent("proposals").stdout)
    check(len([x for x in again["open"] if x["kind"] == "file"]) == 3, "asked again: the same three, not six")

    # Accepting files it; declining is remembered.
    agent("proposal", "accept", "--id", str(by["intsem"]["id"]))
    dest = vault / "projects" / "intsem" / "docs" / by["intsem"]["name"]
    check(dest.is_file() and not (inbox / "The_Seven_Deadly_Myths.pdf").exists(), "accepting moves it into projects/<tag>/docs/")
    check((inbox / "The_Seven_Deadly_Myths (1).pdf").exists(), "…its duplicate stays in Downloads, untouched")
    agent("proposal", "decline", "--id", str(by["dtm"]["id"]))
    (inbox / "PIC_Ethnographic_Methods.pdf").unlink()
    out = json.loads(agent("proposals").stdout)
    check([x for x in out["open"] if x["kind"] == "file"] == [],
          "declined, gone from the inbox, or the duplicate of one filed: nothing more is proposed")
    items = json.loads((state / "longhand" / "proposals.json").read_text())["items"]
    check(next(x for x in items if x["id"] == by["hfpi"]["id"])["status"] == "moot", "a file that left the inbox is moot")
    check(agent("proposal", "accept", "--id", str(by["dtm"]["id"])).returncode == 0, "a declined one stays declined")

    # The index: for the sidebar, and for the agent on a run about the course.
    docs = json.loads(agent("documents", "--tag", "intsem").stdout)["intsem"]
    check(len(docs) == 1 and docs[0]["pages"] == 1 and docs[0]["name"].endswith("Autonomous Systems"), "documents lists a course's, with pages")
    projects = json.loads(agent("projects", "--now", dt.datetime.now().isoformat(timespec="minutes")).stdout)
    check(next(p for p in projects if p["tag"] == "intsem")["docs"] == docs, "…and the sidebar's projects carry them")
    note = daily / f"{dt.date.today().isoformat()}.md"
    note.write_text("# Interdisciplinary Seminar #intsem\n\n- [ ] what does the reading say about autonomy?\n")
    import hashlib  # noqa: E402
    sys.path.insert(0, str(ROOT / "agent"))
    import blocks  # noqa: E402
    h = blocks.split(note.read_text())[-1]["hash"] if hasattr(blocks, "split") else ""
    ctx = agent("context", "--trigger", "checkbox", "--hash", h).stdout if h else ""
    check("# Documents filed for #intsem" in ctx and "Autonomous Systems (1 pages)" in ctx,
          "a run about the course carries the index — a line each, nothing read")
    other = agent("context", "--trigger", "open").stdout
    check("# Documents filed" not in other, "…and a run about nothing in particular does not")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
