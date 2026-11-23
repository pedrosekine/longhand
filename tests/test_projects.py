"""Making a project (2026-10-22): its file, made by the person from the page
or by accepting the agent's proposal, never over one that exists; the agent
may add to a project's file but not make one, rename it or re-tag it.
Against projects.py and plan.py directly, and the CLI against a stub model.

Run: python3 tests/test_projects.py
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
import plan  # noqa: E402
import projects  # noqa: E402

failures = 0
TODAY = dt.date.today()


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def units() -> None:
    check(projects.clean_tag("#thesis") == "thesis" and projects.clean_tag("msc/thesis") == "msc/thesis",
          "a tag: without its #, a / allowed")
    check(projects.clean_tag("two words") == "" and projects.clean_tag("") == "" and projects.clean_tag("#") == "",
          "…never with a space, never empty")
    check(projects.file_name("msc/thesis") == "msc-thesis.md" and projects.file_name("über") == "-ber.md",
          "its file: the tag, in the characters a knowledge file may have")
    check(projects.stub("Master Thesis", "thesis") == "# Master Thesis\n\n- Tag: `#thesis`\n",
          "a new project's file: its name and its tag, nothing else")

    old = "# Research Proficiency\n\n- Tag: `#respro`; course M_IC_ResPro_W26.\n- Sessions on Mondays.\n"
    new = "# ResPro\n\n- Tag: `#rp`; course M_IC_ResPro_W26, winter term.\n- Sessions on Mondays.\n- Draft due 4 Dec.\n"
    kept = projects.keep_identity(old, new, "respro")
    check(kept.startswith("# Research Proficiency\n") and "- Tag: `#respro`; course M_IC_ResPro_W26, winter term." in kept
          and "- Draft due 4 Dec." in kept, f"the agent's rewrite keeps the name and the tag, and what it added ({kept!r})")
    kept = projects.keep_identity(old, "Just facts.\n- Draft due 4 Dec.", "respro")
    check(kept.startswith("# Research Proficiency\n\n- Tag: `#respro`\n") and "Draft due" in kept,
          f"…both put back when it left them out ({kept!r})")
    kept = projects.keep_identity("# Studio\n\nnotes\n", "# Studio Work\n\n- Tag: `#art`\nnotes", "studio")
    check(kept == "# Studio\n\n- Tag: `#studio`\nnotes", f"…a file with no Tag line goes by its name: not re-tagged either ({kept!r})")

    days = [{"date": (TODAY + dt.timedelta(days=i)).isoformat()} for i in range(14)]
    ledger = {"next": 1, "items": []}
    reply = {"proposals": [
        {"kind": "project", "name": "Master Thesis", "tag": "#thesis", "why": "four days of notes on it"},
        {"kind": "project", "name": "Research Proficiency", "tag": "ResPro", "why": "a project already"},
        {"kind": "project", "name": "Bikes", "tag": "bikes", "why": ""},
        {"kind": "project", "name": "", "tag": "empty", "why": "no name"},
        {"kind": "project", "name": "Bad", "tag": "two words", "why": "not a tag"}], "questions": []}
    props, _ = plan.validate(reply, [], days, ledger, TODAY, [], [], plan.autonomy({}), [], ["respro", "dtm"])
    check([(p["title"], p["project"]) for p in props] == [("Master Thesis", "thesis")],
          f"a project proposed: never one that exists, never without a reason, a name and a tag ({props})")
    check(plan.autonomy({"autonomy": {"project": "do"}})["project"] == "ask",
          "making a project stays the person's: 'do it and tell me' is not a level it can have")
    check(plan.ident(props[0]) == ("project", "thesis"), "a proposed project is known by its tag")
    ledger = {"next": 2, "items": [dict(props[0], id=1, status="declined", at="x")]}
    again = dict(reply, proposals=[dict(reply["proposals"][0], name="MSc Thesis")])
    props2, _ = plan.validate(again, [], days, ledger, TODAY, [], [], plan.autonomy({}), [], [])
    check(props2 == [], "one the person declined is not proposed again, under another name either")
    ledger = {"next": 2, "items": [dict(props[0], id=1, status="open", at="x")]}
    check(plan.settle_projects(ledger, ["Thesis"], "now") == 1 and ledger["items"][0]["status"] == "moot",
          "one the person made meanwhile is moot")


STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
sys.stdin.read()
reply = open(os.path.join(d, "reply.json")).read()
print(json.dumps({"type": "text", "sessionID": "ses_proj", "part": {"type": "text", "text": "```json\\n" + reply + "\\n```"}}))
"""


def end_to_end() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="projects-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    (vault / "Daily" / f"{TODAY.isoformat()}.md").write_text("Reading for the #thesis again.\n\n- [ ] read the paper\n")
    folder = vault / "agents" / "longhand" / "knowledge" / "projects"
    folder.mkdir(parents=True)
    (folder / "respro.md").write_text("# Research Proficiency\n\n- Tag: `#respro`\n")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/plan"}))
    state = tmp / "state"
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}{os.pathsep}{os.environ['PATH']}")

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    out = json.loads(agent("project", "--tag", "#studio", "--name", "  Studio   Work ").stdout)
    check(out == {"tag": "studio", "name": "Studio Work", "file": "studio.md"}
          and (folder / "studio.md").read_text() == "# Studio Work\n\n- Tag: `#studio`\n",
          f"`project` makes its file ({out})")
    check([p["tag"] for p in json.loads(agent("projects", "--now", f"{TODAY}T09:00").stdout)] == ["respro", "studio"],
          "…and it is in the projects the sidebar lists")
    r = agent("project", "--tag", "RESPRO", "--name", "Again", ok=False)
    check(r.returncode == 2 and "is a project already" in r.stderr and "Again" not in (folder / "respro.md").read_text(),
          "never over a project that exists, whatever the case of its tag")
    r = agent("project", "--tag", "two words", ok=False)
    check(r.returncode == 2 and "cannot be a tag" in r.stderr, "…nor with a tag that cannot be one")
    agent("project", "--tag", "dtm")
    check((folder / "dtm.md").read_text() == "# dtm\n\n- Tag: `#dtm`\n", "with no name, the tag is its name")

    # The planner proposes one; it is made only once accepted.
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "project", "name": "Master Thesis", "tag": "thesis", "why": "today's note reads for it"}],
        "questions": [], "knowledge": [
        {"file": "projects/bikes.md", "content": "# Bikeability\n\n- Tag: `#bikes`\n"},
        {"file": "projects/respro.md", "content": "# ResPro\n\n- Tag: `#rp`\n- Critical review due 4 Dec."}]}))
    agent("plan", "--force")
    check(not (folder / "bikes.md").exists(), "a project file the agent writes on its own is not kept")
    rp = (folder / "respro.md").read_text()
    check(rp == "# Research Proficiency\n\n- Tag: `#respro`\n- Critical review due 4 Dec.\n",
          f"…one that exists it adds to, its name and tag as they were ({rp!r})")
    props = json.loads(agent("proposals").stdout)["open"]
    card = next((x for x in props if x["kind"] == "project"), None)
    check(card is not None and card["title"] == "Master Thesis" and card["project"] == "thesis"
          and not (folder / "thesis.md").exists(), f"the proposal waits as a card; nothing made yet ({props})")
    agent("proposal", "accept", "--id", str(card["id"]))
    check((folder / "thesis.md").read_text() == "# Master Thesis\n\n- Tag: `#thesis`\n",
          "accepting it makes the project")
    items = json.loads((state / "longhand" / "proposals.json").read_text())["items"]
    check(next(x for x in items if x["id"] == card["id"])["status"] == "accepted", "…recorded as accepted")
    kinds = {k["kind"]: k for k in json.loads(agent("autonomy").stdout)["kinds"]}
    check(kinds["project"]["ask_only"] and kinds["project"]["accepted"] == 1, "Settings lists it, a question only")

    # One the person makes meanwhile leaves nothing to accept.
    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "project", "name": "Bikeability", "tag": "bikes", "why": "the supervision"}], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    card = next(x for x in json.loads(agent("proposals").stdout)["open"] if x["kind"] == "project")
    agent("project", "--tag", "bikes", "--name", "Bikes in Linz")
    check(not any(x["kind"] == "project" for x in json.loads(agent("proposals").stdout)["open"]),
          "a proposed project made from the page meanwhile is moot")
    check((folder / "bikes.md").read_text().startswith("# Bikes in Linz"), "…and the person's name stands")


def project_page() -> None:
    """A project's page (plan.md item 5, 2026-11-16): the folder under way
    found, its Now, papers and files; the tag's sections in the daily notes
    with their boxes shown, never as boxes; private days and blocks left out;
    written in the state folder, never the vault."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="project-page-test-"))
    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    d1, d2, d3 = (TODAY - dt.timedelta(days=n) for n in (1, 2, 3))
    (daily / f"{d1.isoformat()}.md").write_text(
        "# Thesis #thesis\n\nSketched the method chapter.\n\n- [ ] email the supervisor 📅 2030-01-07 ⏫ ^d4\n- [x] read Moser\n\n"
        "> [!private]\n> a worry about the funding\n\n# Other #dtm\n\n- [ ] not the thesis's\n")
    (daily / f"{d2.isoformat()}.md").write_text("---\nagent: false\n---\n# Thesis #thesis\n\nsomething kept to myself\n")
    (daily / f"{d3.isoformat()}.md").write_text("# Thesis #thesis\n\nFirst look at the literature.\n")
    old, cur = vault / "projects" / "thesis_fhooe", vault / "projects" / "thesis_itu"
    (old).mkdir(parents=True)
    (old / "README.md").write_text("# Old thesis\n\n## Now\n\nfinished long ago\n")
    os.utime(old / "README.md", (1_600_000_000, 1_600_000_000))
    os.utime(old, (1_600_000_000, 1_600_000_000))
    (cur / "literature" / "pdf").mkdir(parents=True)
    (cur / "docs").mkdir()
    (cur / "archive").mkdir()
    (cur / "README.md").write_text("# Thesis\n\n## Now\n\n- Writing the method.\n- Next: the pilot.\n\n## Later\n\nnot now\n")
    (cur / "DECISIONS.md").write_text("# Decisions\n")
    (cur / "literature" / "pdf" / "Moser 2026.pdf").write_bytes(b"%PDF-1.4\n")
    (cur / "docs" / "Proposal.pdf").write_bytes(b"%PDF-1.4\n")
    (cur / "archive" / "Draft 0.pdf").write_bytes(b"%PDF-1.4\n")
    know = vault / "agents" / "longhand" / "knowledge" / "projects"
    know.mkdir(parents=True)
    (know / "thesis.md").write_text("# Master Thesis\n\n- Tag: `#thesis`\n")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "horizon": "2000-01-01"}))
    state = tmp / "state"
    (state / "longhand").mkdir(parents=True)
    due = int(dt.datetime.combine(TODAY + dt.timedelta(days=10), dt.time(23, 59)).timestamp())
    (state / "longhand" / "deadlines.tsv").write_text(
        f"1\t{due}\tDraft the method\topen\t\t\tthesis\t\n2\t{due}\tDTM poster\topen\t\t\tdtm\t\n")
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir))
    r = subprocess.run([sys.executable, str(AGENT), "project-page", "--tag", "#thesis"], capture_output=True, text=True, env=env)
    check(r.returncode == 0, f"`project-page` runs ({r.stderr[-400:]})")
    out = json.loads(r.stdout or "{}")
    page = pathlib.Path(out.get("path", "/nonexistent"))
    check(page == state / "longhand" / "pages" / "thesis.md" and page.is_file(), f"…written in the state folder ({out})")
    check(out.get("folder") == "projects/thesis_itu", f"of two thesis folders, the one worked on last ({out})")
    t = page.read_text() if page.is_file() else ""
    check(t.startswith("# Master Thesis\n"), "its name heads it")
    check("- Draft the method · " in t and "DTM poster" not in t, "its deadlines, not another project's")
    check("## Now" in t and "- Next: the pilot." in t and "not now" not in t and "finished long ago" not in t,
          "the README's Now section, only it")
    check("### Not marked yet" in t and "[[projects/thesis_itu/literature/pdf/Moser 2026.pdf|Moser 2026]]" in t,
          "its literature, by folder, as papers not yet marked")
    check("[[projects/thesis_itu/docs/Proposal.pdf|Proposal]] (PDF)" in t and "[[projects/thesis_itu/DECISIONS|DECISIONS]]" in t
          and "Draft 0" not in t, "its own documents and notes as working files; the archive left out")
    check(f"[[Daily/{d1.isoformat()}#Thesis #thesis|" in t and "Sketched the method chapter." in t
          and "First look at the literature." in t and t.index("Sketched") < t.index("First look"),
          "the tag's sections in the daily notes, newest first, linked to where they are written")
    check("☐ email the supervisor · due Mon 7 Jan" in t and "☑ read Moser" in t and "- [ ]" not in t and "^d4" not in t
          and "⏫" not in t, "boxes shown as ☐/☑ with their due day, never as boxes, their marks off")
    check("not the thesis's" not in t, "…not another tag's section under it")
    check("funding" not in t and "kept to myself" not in t and "1 day marked private left out." in t,
          "a private block and a private day are left out, the day counted")
    check(not any(vault.rglob("pages")), "nothing written into the vault")
    # The sidebar's list carries each project's folder, so the page asks for
    # its PDFs too (2026-11-16); a project with no folder carries "".
    (know / "dtm.md").write_text("# DTM\n\n- Tag: `#dtm`\n")
    r = subprocess.run([sys.executable, str(AGENT), "projects", "--now", f"{TODAY.isoformat()}T09:00"],
                       capture_output=True, text=True, env=env)
    folders = {p["tag"]: p.get("folder") for p in json.loads(r.stdout or "[]")}
    check(folders == {"thesis": "projects/thesis_itu", "dtm": ""},
          f"`projects`: each project's folder, the one under way; none for a project without one ({folders})")

    # The project's week (2026-11-17): done, written, coming up — the hand-in
    # however far — and what to ask, gathered from disk; the page's head
    # says the week in one line. A paper is named from a .bib kept beside
    # the LaTeX, not only at the folder's top.
    far = int(dt.datetime.combine(TODAY + dt.timedelta(days=200), dt.time(23, 59)).timestamp())
    with open(state / "longhand" / "deadlines.tsv", "a") as f:
        f.write(f"3\t{far}\tHand in the thesis\topen\t\t\tthesis\t\n")
    (cur / "literature" / "pdf" / "moser2026identifying.pdf").write_bytes(b"%PDF-1.4\n")
    (cur / "proposal").mkdir()
    (cur / "proposal" / "references.bib").write_text(
        "@article{moser2026identifying,\n  author = {Moser, Martin and Resch, Bernd and Graf, A.},\n"
        "  title = {Identifying {Stress} in Cycling},\n  year = {2026},\n}\n")
    (daily / f"{d1.isoformat()}.md").write_text((daily / f"{d1.isoformat()}.md").read_text().replace(
        "Sketched the method chapter.", "Sketched the method chapter.\nShould RQ3 ask what explains the disagreements?"))
    r = subprocess.run([sys.executable, str(AGENT), "week", "--tag", "thesis", "--date", d1.isoformat()],
                       capture_output=True, text=True, env=env)
    w = r.stdout
    check(r.returncode == 0 and w.startswith("# Master Thesis — week "), f"`week` runs ({r.stderr[-300:]})")
    check("## Coming up" in w and "Draft the method" in w and "**in 10 days**" in w
          and "Hand in the thesis" in w and "weeks**" in w and "DTM poster" not in w,
          "coming up: the near deadlines and the last one however far, never another project's")
    check("## Done" in w and "- read Moser" in w, "…what was ticked in the week")
    check("## Written" in w and f"{d1:%a %-d %b}" in w, "…the days the project was written in")
    check("## Still open" in w and "email the supervisor" in w and "⏫" not in w and "^d4" not in w,
          "…its open boxes, marks off")
    check("## Questions to bring" in w and "Should RQ3 ask what explains the disagreements?" in w,
          "…a question written in the week's notes, to bring")
    check("funding" not in w and "kept to myself" not in w, "…never a private block or day")
    check("README.md" in w and "## Files worked on" in w, "…the project folder's files changed in the week")
    r = subprocess.run([sys.executable, str(AGENT), "project-page", "--tag", "thesis"], capture_output=True, text=True, env=env)
    t = page.read_text()
    check("**Coming up:**" in t and "**This week**" in t and t.index("**Coming up:**") < t.index("## Now"),
          "the project's page opens with what is coming and the week so far")
    check("Moser et al. 2026 — Identifying Stress in Cycling" in t, "a paper named from a .bib kept in a subfolder")
    r = subprocess.run([sys.executable, str(AGENT), "week", "--tag", "thesis", "--write"], capture_output=True, text=True, env=env)
    kept = pathlib.Path(json.loads(r.stdout or "{}").get("path", "/nonexistent"))
    check(kept.is_file() and kept.parent == vault / "agents" / "longhand" / "weeks" and kept.name.startswith("thesis-"),
          f"--write keeps it in the agent's folder of the vault, to edit or export ({r.stdout}{r.stderr[-200:]})")
    r = subprocess.run([sys.executable, str(AGENT), "week", "--tag", "thesis", "--write"], capture_output=True, text=True, env=env)
    check(r.returncode != 0 and "--force" in r.stderr, "…and never over one already there without --force")


def main() -> int:
    units()
    end_to_end()
    project_page()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
