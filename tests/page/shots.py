#!/usr/bin/env python3
"""Screenshots of the page, for design reviews: the real page, drawn as it
draws, on a throwaway vault (the same one run.py builds).

It draws in a Hyprland of its own: a second, private Hyprland started inside
yours, with its one window turned off and a headless output to draw on. A
headless output is drawn on its own clock, so the shots come whatever your
session is doing — the Air at home with its lid shut, its panel off and the
session locked (a lock covers every output of the session it locks, a new
one too, and Qt's own grab waits for frames that never come). Nothing shows
in your session, your windows and rules are not touched, and the private
Hyprland is stopped when it is done.

Run: python3 tests/page/shots.py OUT                         every scene
     python3 tests/page/shots.py OUT --scene dashboard        one of: dashboard, note, day, keys, chat, project, acronyms, reach
     python3 tests/page/shots.py OUT --order date             the dashboard's order (ask, course, date)
     python3 tests/page/shots.py OUT --root DIR               draw another checkout (a variant study)
     python3 tests/page/shots.py OUT --env NAME=VALUE         an environment variable for the page
Writes OUT/<scene>-<n>.png, at scale 2. Needs a running Hyprland to start
the private one in (over SSH too: tests/desktop.py finds it).
"""
import argparse
import datetime as dt
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
TITLE = "Page shots"
SIZE = (1100, 850)       # the window, in logical pixels
MODE = "2400x1800"       # the output: 1200x900 logical at scale 2, room for the window


def hypr(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10).stdout


def window():
    return next((c for c in json.loads(hypr("clients", "-j") or "[]") if c["title"] == TITLE), None)


def load_run(root: pathlib.Path):
    sys.argv = ["run.py"]
    spec = importlib.util.spec_from_file_location("pagerun", root / "tests" / "page" / "run.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def page(m, order):
    """run.py's Page, retitled for the shots window, the dashboard in `order`
    and the pointer left where it is (it would follow the selection, and a
    hint would open under it)."""
    real = m.subprocess.Popen

    class Popen(real):
        def __init__(self, args, **kw):
            if args and args[0] == "quickshell" and "ipc" not in args:
                shell = pathlib.Path(args[2])
                qml = shell / "shell.qml"
                qml.write_text(qml.read_text().replace('windowTitle: "Page scratch"', f'windowTitle: "{TITLE}"'))
                tmp = shell.parent
                (tmp / "state" / "longhand" / "page.json").write_text(json.dumps({"dashOrder": order}))
                (tmp / "config" / "longhand" / "settings.json").write_text(json.dumps({"pointer": "off"}))
            super().__init__(args, **kw)

    m.subprocess.Popen = Popen
    try:
        return m.Page()
    finally:
        m.subprocess.Popen = real


def fixture(m, p):
    """Three boxes — one the agent answered (unread), one talked about and
    read, one never — and a question the agent asks about the first."""
    d0 = dt.date.today()
    d1 = d0 + dt.timedelta(days=1)
    lines = [f"- [ ] Revise Themenvorschlag based on Bernd's feedback and send the updated version #thesis ⏳ {d0} 📅 {d0}",
             f"- [ ] Reflective research diary 2 #studio 📅 {d0}",
             f"- [ ] read ch. 4-5 and take notes on the reforms #history 📅 {d1}"]
    h0 = m.blocks.split(lines[0])[0]["hash"]
    h1 = m.blocks.split(lines[1])[0]["hash"]
    (p.vault / "agents" / "longhand" / "daily").mkdir(parents=True, exist_ok=True)
    (p.vault / "agents" / "longhand" / "daily" / f"{m.TODAY}.json").write_text(json.dumps({"blocks": {
        h0: {"state": "reply", "reply": "It first appears in your 10 November note; 13 November is its due date.",
             "read": False, "head": lines[0],
             "chat": [{"role": "student", "text": "when did I write this?"},
                      {"role": "agent", "text": "It first appears in your 10 November note; 13 November is its due date."}]},
        h1: {"state": "reply", "reply": "The template is in the course folder.", "read": True, "head": lines[1],
             "chat": [{"role": "agent", "text": "The template is in the course folder."},
                      {"role": "student", "text": "which questions does this one ask?"}]}}}))
    # The agent's key for a box: its project, a tab, its words (agent/lifespan.py).
    key = "thesis\t- Revise Themenvorschlag based on Bernd's feedback and send the updated version #thesis"
    (p.state / "longhand" / "proposals.json").write_text(json.dumps({"items": [
        {"kind": "question", "id": 1, "key": key, "status": "open", "at": f"{d0}T09:00:00",
         "question": "Does the draft clinic require a half-page submission or a longer one?",
         "recommended": "A half-page building block using the current thesis draft, not a new text."}]}))
    (p.daily / f"{m.TODAY}.md").write_text(m.header(m.TODAY) + "Plans for the day.\n\n" + "\n\n".join(lines) + "\n")
    # Written yesterday for today: the band above today's note counts it.
    (p.daily / f"{m.YDAY}.md").write_text(m.header(m.YDAY) + f"- [ ] Print the A0 poster #studio 📅 {d0} 16:00\n"
                                          f"- [x] Book the plotter #studio ⏳ {d0} ✅ {d0}\n")


def project_fixture(m, p):
    """A thesis as Longhand sees one: its knowledge file, its folder with a
    bibliography and papers (one read over two days, with questions; the
    rest not begun), its proposal, and three days of sections."""
    import importlib.util as iu
    spec = iu.spec_from_file_location("tread", HERE.parent / "test_read.py")
    tr = iu.module_from_spec(spec)
    spec.loader.exec_module(tr)
    know = p.vault / "agents" / "longhand" / "knowledge" / "projects"
    know.mkdir(parents=True, exist_ok=True)
    (know / "thesis.md").write_text("# Master Thesis\n\n- Tag: `#thesis`\n")
    lit = p.vault / "projects" / "thesis_itu" / "literature" / "pdf"
    lit.mkdir(parents=True)
    papers = {
        "moser2026identifying": ("Moser, Martin and Graf, David and Resch, Bernd", "2026",
                                 "Identifying environmental stress factors in urban cycling using multimodal human sensing"),
        "zeile2016urban": ("Zeile, Peter and Resch, Bernd and Loidl, Martin", "2016", "Urban Emotions and Cycling Experience"),
        "kyriakou2019spatial": ("Kyriakou, Kalliopi and Resch, Bernd", "2019", "Spatial Analysis of Moments of Stress Derived from Wearable Sensor Data"),
        "fox2011procedures": ("Fox, Mark and Ericsson, Anders and Best, Ryan", "2011", "Do procedures for verbal reporting of thinking have to be reactive?"),
        "haug2023identifying": ("Haug, Nina and Schmidt, Tom and Resch, Bernd", "2023", "Identifying urban stress and bicycle infrastructure relationships"),
        "resch2020interdisciplinary": ("Resch, Bernd and Puetz, Inga and Bluemke, Matthias", "2020", "An Interdisciplinary Mixed-Methods Approach to Analyzing Urban Spaces"),
    }
    bib = []
    for key, (authors, year, title) in papers.items():
        tr.pdf(lit / f"{key}.pdf", [["Negative exposures within multifaceted urban settings", "can discourage active mobility usage.",
                                     "We apply Getis-Ord Gi* hot spot analysis", "to the stress moments of each rider."],
                                    ["Subjective experience gives an objective assessment", "when many riders agree on a place.", "End."]])
        bib.append(f"@article{{{key},\n  author = {{{authors}}},\n  title = {{{title}}},\n  year = {{{year}}},\n}}\n")
    (p.vault / "projects" / "thesis_itu" / "proposal").mkdir()
    (p.vault / "projects" / "thesis_itu" / "proposal" / "references.bib").write_text("\n".join(bib))
    tr.pdf(p.vault / "projects" / "thesis_itu" / "proposal" / "proposal.pdf", [["Proposal"]])
    d0 = dt.date.today()
    day = lambda n: (d0 - dt.timedelta(days=n)).isoformat()
    paper = "projects/thesis_itu/literature/pdf/moser2026identifying.pdf"
    read = [str(m.ROOT / "cli" / "longhand-read")]
    for page_, text, kind, n in [(1, "Negative exposures within multifaceted urban settings", "h", 1),
                                 (1, "Getis-Ord Gi* hot spot analysis", "q", 1),
                                 (2, "Subjective experience gives an objective assessment", "q", 1),
                                 (1, "can discourage active mobility usage", "h", 0)]:
        subprocess.run(read + ["mark", "--pdf", paper, "--page", str(page_), "--text", text, "--kind", kind, "--day", day(n),
                               "--tag", "thesis"], env=p.env, check=True, capture_output=True)
    stem = lambda n: (d0 - dt.timedelta(days=n)).strftime("%Y.%m.%d")
    (p.daily / f"{stem(2)}.md").write_text(m.header(stem(2)) + f"- [ ] Finish the Themenvorschlag #thesis 📅 {d0}\n")
    (p.daily / f"{stem(6)}.md").write_text(m.header(stem(6)) + "- [x] Revise Themenvorschlag based on Bernd's feedback #thesis\n")
    (p.daily / f"{stem(11)}.md").write_text(m.header(stem(11)) + "# Bernd Meeting #thesis\n\nTalk out loud can go more natural.\n\n- 30 as a cohort of riders\n")


def grab(path):
    # The private Hyprland's own notice (it was started without
    # start-hyprland, as a throwaway one is) sits on top of the window.
    hypr("dismissnotify")
    time.sleep(0.2)
    w = window()
    (x, y), (wd, ht) = w["at"], w["size"]
    subprocess.run(["grim", "-g", f"{x},{y} {wd}x{ht}", str(path)], timeout=15, check=True)


def scenes(m, p, out, which):
    shots = []

    def shot(name):
        time.sleep(0.6)
        path = out / f"{name}.png"
        grab(path)
        shots.append(path)

    if which in ("all", "dashboard"):
        p.call("dash")
        p.wait(lambda: sum(r.get("kind") == "task" for r in json.loads(p.call("dashRows"))) >= 3, 8)
        time.sleep(1)
        rows = json.loads(p.call("dashRows"))
        acts = [i for i, r in enumerate(rows) if r.get("kind") in ("task", "deadline", "question", "proposal")]
        for n, i in enumerate(acts):
            p.call("dashFocus", i)
            shot(f"dashboard-{n}")
        p.call("dash")
    if which in ("all", "chat"):
        p.call("dash")
        p.wait(lambda: any(r.get("kind") == "task" for r in json.loads(p.call("dashRows"))), 8)
        rows = json.loads(p.call("dashRows"))
        p.call("dashFocus", next(i for i, r in enumerate(rows) if r.get("kind") == "task"))
        p.call("dashKey", 0x43, 0)          # C: its chat, beside
        shot("chat-0")
        p.call("closePanes")
        p.call("dash")
    if which in ("all", "note"):
        p.open_fresh()
        p.call("cursorLine", 2)
        shot("note-0")
    if which in ("all", "day"):
        p.open_fresh()
        p.wait(lambda: len(json.loads(p.call("dayTasks"))["titles"]) >= 4, 8)
        shot("day-0")
        p.call("keyPage", 0x54, 0x04000000 | 0x02000000)   # Ctrl+Shift+T: the list
        shot("day-1")
        p.call("keyPage", 0x54, 0x04000000 | 0x02000000)
    if which in ("all", "project"):
        project_fixture(m, p)
        p.open_fresh()
        p.call("sidebar")
        p.wait(lambda: any(x.startswith("thesis|") for x in json.loads(p.call("projects"))), 10)
        i = next(n for n, x in enumerate(json.loads(p.call("projects"))) if x.startswith("thesis|"))
        p.call("openProject", i)
        p.wait(lambda: any(r.startswith("read|") for r in json.loads(p.call("projectRows"))["rows"]), 10)
        time.sleep(0.8)
        shot("project-0")
        rows = json.loads(p.call("projectRows"))["rows"]
        p.call("projectPick", next(r.split("|", 1)[1] for r in rows if r.startswith("question|")))
        shot("project-1")
        p.call("projectPick", "fold:shelf")
        p.call("projectOpenRow")
        p.call("projectPick", "fold:files")
        p.call("projectOpenRow")
        shot("project-2")
        rows = json.loads(p.call("projectRows"))["rows"]
        p.call("projectPick", next(r.split("|", 1)[1] for r in rows if r.startswith("question|")))
        p.call("projectOpenRow")
        time.sleep(2.5)
        shot("project-3")
    if which in ("all", "acronyms"):
        # Acronyms in a paper (plan.md item 18): one hovered, then the list.
        sys.path.insert(0, str(HERE.parent))
        from test_read import pdf as lined_pdf
        lined_pdf(p.vault / "Papers" / "Stress on bikes.pdf", [[
            "Cyclists wore a wristband that read their heart rate",
            "variability (HRV) and electrodermal activity (EDA) while",
            "riding through the city, and a GPS logger kept the route.",
            "Moments of stress (MOS) were found where the EDA rose and",
            "the HRV fell together. A large language model (LLM) wrote",
            "nothing here. Each MOS was placed on the route by its GPS",
            "time, and the HRV around it was compared with the HRV of",
            "the same rider on a quiet street."]])
        p.call("openFile", "Papers/Stress on bikes.pdf", "false")
        ac = lambda: json.loads(p.call("pdfAcronyms"))
        p.wait(lambda: len(ac()["list"]) >= 4, 10)
        spot = [x for x in ac()["spots"][0] if x["a"] == "MOS"][-1]["r"]
        p.call("pdfHover", "0", str(spot[0] + spot[2] / 2), str(spot[1] + spot[3] / 2))
        p.wait(lambda: ac()["tip"], 5)
        shot("acronyms-0")
        spot = [x for x in ac()["spots"][0] if x["a"] == "GPS"][-1]["r"]
        p.call("pdfHover", "0", "400", "500")
        p.wait(lambda: not ac()["tip"], 5)
        p.call("pdfHover", "0", str(spot[0] + spot[2] / 2), str(spot[1] + spot[3] / 2))
        p.wait(lambda: ac()["tip"], 5)
        shot("acronyms-1")
        p.call("pdfHover", "0", "400", "500")
        p.call("pdfKey", 0x41, 0)           # a: the list
        p.wait(lambda: ac()["listing"], 5)
        shot("acronyms-2")
        p.call("pdfKey", 0x01000000, 0)
    if which in ("all", "answers"):
        # A question hovered shows its answer; Enter opens the chat at it.
        import hashlib
        if which == "answers":
            scenes(m, p, out, "acronyms")
        rel = "Papers/Stress on bikes.pdf"
        mk = lambda: json.loads(p.call("pdfMarks"))
        p.call("openFile", rel, "false")
        p.wait(lambda: json.loads(p.call("pdf"))["settled"], 10)
        p.call("pdfMarkText", "0", "Moments of stress (MOS) were found where the EDA rose", "q")
        if not p.wait(lambda: len(mk()["read"]["marks"]) >= 1, 10):
            raise SystemExit(f"no mark made: {mk()['error']!r}")
        qid = mk()["read"]["marks"][0]["id"]
        talk = p.vault / "agents" / "longhand" / "notes" / (hashlib.md5(rel.encode()).hexdigest()[:16] + ".json")
        talk.parent.mkdir(parents=True, exist_ok=True)
        talk.write_text(json.dumps({"path": rel, "session": "", "seen": "", "turns": [
            {"role": "student", "text": "how do they decide a moment of stress?", "marks": [qid], "at": "2026-11-16T10:00:00"},
            {"role": "agent", "at": "2026-11-16T10:00:09", "text":
             "A moment of stress is a stretch where skin conductance rises while heart rate variability falls, both "
             "within a few seconds. The paper says “Moments of stress (MOS) were found where the EDA rose” (p. 1): "
             "the rule needs both signals, so a rise in EDA alone, from heat or effort, does not count. Each one is "
             "then placed on the route by its GPS time."},
            {"role": "student", "text": "and how long is a moment?", "at": "2026-11-16T10:02:00"},
            {"role": "agent", "text": "A few seconds; the paper does not fix a length.", "at": "2026-11-16T10:02:07"}]}))
        p.call("pdfKey", 0x01000000, 0)
        p.wait(lambda: not json.loads(p.call("pdf"))["shown"], 5)
        p.call("openFile", rel, "false")
        p.wait(lambda: mk()["read"]["marks"] and mk()["read"]["marks"][0]["boxes"], 10)
        time.sleep(1)
        r = mk()["read"]["marks"][0]["boxes"][0]["rects"][0]
        p.call("pdfHover", "0", "400", "500")
        time.sleep(0.4)
        p.call("pdfHover", "0", str(r[0] + 40), str(r[1] + r[3] / 2))
        p.wait(lambda: json.loads(p.call("pdfAcronyms"))["tip"], 5)
        shot("answers-0")
        p.call("pdfKey", 0x01000004, 0)     # Enter: the chat at it
        time.sleep(0.8)
        shot("answers-1")
    if which in ("all", "reach"):
        # Reaching a project (plan.md item 19): `#th` typed in the sidebar,
        # Hold Ctrl's Alt+digit on each project, the switcher.
        know = p.vault / "agents" / "longhand" / "knowledge" / "projects"
        know.mkdir(parents=True, exist_ok=True)
        for tag, name in [("respro", "Research Proficiency"), ("hfpi", "Human Factors & Psychology"), ("studio", "Design Studio"),
                          ("dtm", "Design Theory & Methods"), ("coach", "Coaching"), ("thesis", "Master Thesis")]:
            if not (know / f"{tag}.md").exists():
                (know / f"{tag}.md").write_text(f"# {name}\n\n- Tag: `#{tag}`\n")
        p.call("closePanes")
        p.call("keysToSidebar")
        p.wait(lambda: len(json.loads(p.call("projects"))) >= 6, 10)
        p.call("sideType", "#th")
        shot("reach-0")
        p.call("sideKey", 0x01000000, 0)
        p.call("ctrlHold", "true")
        shot("reach-1")
        p.call("ctrlHold", "false")
        p.call("closePanes")
        p.call("pageKey", 0x4f, 0x04000000)  # Ctrl+O
        p.call("switcherType", "de")
        shot("reach-2")
        p.call("switcherKey", 0x01000000, 0)
    if which in ("all", "keys"):
        p.call("keys")
        shot("keys-0")
        p.call("keys")
    return shots


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--scene", default="all", choices=["all", "dashboard", "note", "day", "keys", "chat", "project", "acronyms", "answers", "reach"])
    ap.add_argument("--order", default="ask", choices=["ask", "course", "date"])
    ap.add_argument("--root", type=pathlib.Path, default=HERE.parent.parent)
    ap.add_argument("--env", action="append", default=[])
    a = ap.parse_args()
    sys.path.insert(0, str(HERE.parent))
    import desktop
    desktop.reach("the page", wake_screen=False)
    for kv in a.env:
        k, _, v = kv.partition("=")
        os.environ[k] = v
    a.out.mkdir(parents=True, exist_ok=True)
    m = load_run(a.root.resolve())
    with desktop.Private(MODE, 2, [f'hl.window_rule({{ match = {{ title = "^{TITLE}$" }}, float = true, '
                                   f'size = {{ {SIZE[0]}, {SIZE[1]} }} }})']):
        p = page(m, a.order)
        try:
            fixture(m, p)
            p.open_fresh()
            for path in scenes(m, p, a.out, a.scene):
                print(path)
        finally:
            p.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
