"""What the day's chat of 2026-11-19 lacked, each fixed and checked here:

- "change my late tasks for today": a box that has a day already (a late
  one) gets another when the student asks, the day it had kept for undoing
  (plan.py `validate`, `settle_moot`).
- five papers filed for #thesis, four of them already in its literature
  folder: a PDF the vault holds anywhere, byte for byte, is not filed again
  (documents.py `in_vault`, the runner's `day_file`).
- "rename those files with the name of the author in the front": a paper
  is filed as "Surname Year Title.pdf" (documents.py `paper_name`).
- #thesis filed into a new projects/thesis/docs: a project's `Docs:` line
  names its folder (documents.py `set_folders`), and the agent's rewrite
  of the project file keeps it (projects.py `keep_identity`).
- the agent could not see the papers in Downloads: those with a DOI or an
  arXiv id on page 1, when the message is about downloads or papers
  (documents.py `papers`).
- "tell me its path", sent with an unrelated box under the cursor: the
  chip that attached itself is said to be one (the runner's `refs_parts`).

Run: python3 tests/test_filing_papers.py
"""
import datetime as dt
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))

TMP = pathlib.Path(tempfile.mkdtemp(prefix="filing-papers-"))
os.environ["XDG_STATE_HOME"] = str(TMP / "state")
os.environ["XDG_CONFIG_HOME"] = str(TMP / "config")
os.environ["LONGHAND_CONFIG"] = str(TMP / "config" / "longhand" / "config.json")

import documents as doclib  # noqa: E402
import plan  # noqa: E402
import projects as projlib  # noqa: E402

failures = 0
TODAY = dt.date.today()


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def day(n):
    return (TODAY + dt.timedelta(days=n)).isoformat()


# First pages as pdftotext gives them (from the student's own library).
MOSER = """(2026) 5:6
Moser et al. Urban Informatics
https://doi.org/10.1007/s44212-025-00096-6
Urban Informatics
Open Access
RESEARCH
Identifying environmental stress factors
in urban cycling using multimodal human
sensing and machine learning
Martin Karl Moser1,2*, David Ruben Max Graf1,2, Shaily Gandhi1 and Bernd Resch1,3
Abstract
The spatiotemporal nature of urban environments
"""
ZEILE = """GI_Forum 2016, Vol.1
Page: 204-216
Full Paper
Corresponding Author:
zeile@rhrk.uni-kl.de
DOI: 10.1553/giscience2016_01_s204
Urban Emotions and Cycling
Experience – Enriching Traffic
Planning for Cyclists with Human
Sensor Data
Peter Zeile1, Bernd Resch2,3, Martin Loidl2, Andreas Petutschnig2 and
Linda Dörrzapf4
"""
ORCID = """Special Issue: Urban AI
EPB: Urban Analytics and City Science
2025, Vol. 0(0) 1–27
DOI: 10.1177/23998083251394426
Martin Karl Moser1,2 , Sebastian Schmidt1,2, David Ruben Max Graf1,2,
Maximilian Heinke6 and Bernd Resch1,2,4
Abstract
"""
SPRINGER = """Physical Violence Detection with Movement
Sensors
Liang Ye1,2(&), Le Wang1, Peng Wang1,3, Hany Ferdinando2,4,
Tapio Seppänen5, and Esko Alasaarela2
https://doi.org/10.1007/978-3-319-73564-1_20
"""
HANDOUT = """Master Thesis
Topic Proposal
GeoSocial AI | Digital Earth, Society and Networks
Project Information
"""


def names() -> None:
    p = pathlib.Path("s44212-025-00096-6 (1).pdf")
    got = dt.datetime(2026, 11, 19, 11, 0)
    title = "Identifying environmental stress factors in urban cycling using multimodal human sensing and machine learning"
    n = doclib.file_name(p, got, info={"Title": title, "Author": " Martin Karl Moser "}, text=MOSER)
    check(n.startswith("Moser 2026 Identifying environmental stress factors") and n.endswith(".pdf"),
          f"a paper is filed by its first author and year, then its title ({n})")
    check(len(n) <= doclib.TITLE_MAX + 20, "a long title is cut at a word")
    n = doclib.file_name(pathlib.Path("C02_FP_10839_Zeile.pdf"), got, info={"Author": "Griesebner Gerald"}, text=ZEILE)
    check(n.startswith("Zeile 2016 Urban Emotions and Cycling Experience"),
          f"a typesetter in the Author field is not the author; the title is read above the authors ({n})")
    n = doclib.file_name(pathlib.Path("x.pdf"), got, info={}, text=ORCID)
    check(n.startswith("Moser 2025"), f"an ORCID mark beside a name is no part of it ({n})")
    n = doclib.file_name(pathlib.Path("ye2018.pdf"), got, info={"Author": "Liang Ye "}, text=SPRINGER)
    check(n.startswith("Ye "), f"Springer's (&) mark leaves the first author first ({n})")
    n = doclib.file_name(pathlib.Path("CORP2021_72.pdf"), got, info={},
                         text="reviewed paper\nSubjektiven Verkehrsstress objektiv messen\nJule Merk, Jochen Eckart, Peter Zeile\n1 ABSTRACT\n")
    check(n == "Merk 2021 Subjektiven Verkehrsstress objektiv messen.pdf",
          f"with no year on the page, the download's name gives it ({n})")
    n = doclib.file_name(pathlib.Path("IT-U_Topic_Proposals.pdf"), got, info={"Title": "IT:U MSc Thesis Topic Proposals"},
                         text=HANDOUT + "\fReferences\n10.1007/abc\n")
    check(n == "2026-11-19 IT U MSc Thesis Topic Proposals.pdf",
          f"a handout keeps the dated name, whatever its second page cites ({n})")


def vault_twins() -> None:
    vault = TMP / "v1"
    lit = vault / "projects/thesis_itu/literature/pdf"
    lit.mkdir(parents=True)
    (lit / "moser2026identifying.pdf").write_bytes(b"%PDF-1.4 the paper")
    (lit / "other.pdf").write_bytes(b"%PDF-1.4 the pape!")                 # same size, other bytes
    inbox = TMP / "in1"
    inbox.mkdir()
    (inbox / "s44212.pdf").write_bytes(b"%PDF-1.4 the paper")
    (inbox / "new.pdf").write_bytes(b"%PDF-1.4 a new one, longer")
    twin = doclib.in_vault(inbox / "s44212.pdf", vault)
    check(twin is not None and twin.name == "moser2026identifying.pdf",
          "a download the vault holds under another name, anywhere, is found")
    check(doclib.in_vault(inbox / "new.pdf", vault) is None, "a new paper is not")
    hidden = vault / ".trash"
    hidden.mkdir()
    (hidden / "copy.pdf").write_bytes(b"%PDF-1.4 a new one, longer")
    check(doclib.in_vault(inbox / "new.pdf", vault) is None, "a hidden folder's copy does not count")


def folders() -> None:
    vault = TMP / "v2"
    doclib.set_folders([("thesis", "# Master Thesis\n\n- Tag: `#thesis`\n- Docs: `projects/thesis_itu/literature/pdf`\n"),
                        ("hfpi", "# HFPI\n\n- Tag: `#hfpi`\n"),
                        ("bad", "# Bad\n\n- Tag: `#bad`\n- Docs: ../../outside\n")], vault)
    check(doclib.docs_dir(vault, "projects", "thesis") == vault / "projects/thesis_itu/literature/pdf",
          "a project's Docs: line names its documents' folder")
    check(doclib.docs_dir(vault, "projects", "hfpi") == vault / "projects/hfpi/docs", "without one, projects/<tag>/docs")
    check(doclib.docs_dir(vault, "projects", "bad") == vault / "projects/bad/docs", "a folder outside the vault is not taken")
    doclib.set_folders([], vault)
    old = "# Master Thesis\n\n- Tag: `#thesis`\n- Docs: `projects/thesis_itu/literature/pdf`\n- Bernd confirmed.\n"
    new = projlib.keep_identity(old, "# Master Thesis\n\n- Tag: `#thesis`\n- Bernd confirmed.\n- Read Moser.\n", "thesis")
    check("- Docs: `projects/thesis_itu/literature/pdf`" in new and "Read Moser" in new,
          "the agent's rewrite of a project file keeps its Docs: line")
    new = projlib.keep_identity(old, "# Master Thesis\n\n- Tag: `#thesis`\n- Docs: projects/elsewhere\n", "thesis")
    check(new.count("Docs:") == 1 and "thesis_itu" in new, "and cannot move it")


def redate() -> None:
    days = [{"date": day(i)} for i in range(14)]
    boxes = [{"key": "late", "title": "AI literacy", "project": "respro", "due": "2027-01-15 23:59", "when": day(-1),
              "late": True, "priority": 0, "steps_under_it": 0, "age_days": 30, "quiet": False, "kind": "task"},
             {"key": "fresh", "title": "read", "project": "", "due": "", "when": "", "priority": 0,
              "steps_under_it": 0, "age_days": 1, "quiet": False, "kind": "task"}]
    cands = [{"key": "fresh", "title": "read", "project": "", "due": ""}]
    reply = {"proposals": [{"kind": "do-date", "key": "late", "date": day(0), "why": "they asked"}]}
    ledger = {"next": 1, "items": []}
    props, _ = plan.validate(reply, cands, days, ledger, TODAY, boxes, [], plan.autonomy({}), asked=True)
    check(len(props) == 1 and props[0]["was"] == day(-1) and props[0]["date"] == day(0),
          f"asked, a late box gets today, the day it had kept ({props})")
    props2, _ = plan.validate(reply, cands, days, ledger, TODAY, boxes, [], plan.autonomy({}))
    check(props2 == [], "a planning pass still never moves a day already set")
    same = {"proposals": [{"kind": "do-date", "key": "late", "date": day(-1), "why": "same"}]}
    check(plan.validate(same, cands, days, ledger, TODAY, boxes, [], plan.autonomy({}), asked=True)[0] == [],
          "nor proposes the day it has")
    after = {"proposals": [{"kind": "do-date", "key": "late", "date": "2027-02-01", "why": "x"}]}
    check(plan.validate(after, cands, days, ledger, TODAY, boxes, [], plan.autonomy({}), asked=True)[0] == [],
          "nor a day after its due date")
    item = dict(props[0], id=1, status="open", at=TODAY.isoformat())
    led = {"next": 2, "items": [item]}
    tasks = [{"key": "late", "when": day(-1)}]
    plan.settle_moot(led, tasks, dt.datetime.now().isoformat(timespec="seconds"))
    check(led["items"][0]["status"] == "open", "the box still on its old day: the card is still open")
    plan.settle_moot(led, [{"key": "late", "when": day(0)}], dt.datetime.now().isoformat(timespec="seconds"))
    check(led["items"][0]["status"] == "accepted", "on the new day: taken")
    item2 = dict(props[0], id=2, status="open", at=TODAY.isoformat())
    led2 = {"next": 3, "items": [item2]}
    plan.settle_moot(led2, [{"key": "late", "when": day(3)}], dt.datetime.now().isoformat(timespec="seconds"))
    check(led2["items"][0]["status"] == "moot", "on a day of the student's own: moot")
    ob = plan.open_boxes([{"key": "a", "title": "a", "when": day(-2)}, {"key": "b", "title": "b", "when": day(1)}], [], TODAY)
    check([b["late"] for b in ob] == [True, False], "open_boxes says which boxes are late")


def runner() -> None:
    loader = importlib.machinery.SourceFileLoader("longhand_agent_filing", str(AGENT))
    la = importlib.util.module_from_spec(importlib.util.spec_from_loader("longhand_agent_filing", loader))
    loader.exec_module(la)

    # The chip that attached itself is said to be one.
    r = {"date": "2026-11-19", "hash": "h", "text": "- [ ] AI literacy", "kind": "task", "auto": True}
    words = "\n".join(la.refs_parts([r], 0, "2026-11-19"))
    check("Attached by itself" in words, "the automatic chip is told to the agent as one")
    words = "\n".join(la.refs_parts([dict(r, auto=False)], 0, "2026-11-19"))
    check("Attached by itself" not in words, "a chip the student chose is not")

    # Filing asked for in the day's chat: a twin is refused, a paper named.
    vault = TMP / "v3"
    (vault / "Daily").mkdir(parents=True)
    know = vault / "agents/longhand/knowledge/projects"
    know.mkdir(parents=True)
    (know / "thesis.md").write_text("# Master Thesis\n\n- Tag: `#thesis`\n- Docs: `projects/thesis_itu/literature/pdf`\n")
    lit = vault / "projects/thesis_itu/literature/pdf"
    lit.mkdir(parents=True)
    inbox = TMP / "in3"
    inbox.mkdir()
    sys.path.insert(0, str(ROOT / "tests"))
    from test_documents import pdf  # noqa: E402
    pdf(inbox / "s44212-025-00096-6 (1).pdf", "doi 10.1007/s44212 Moser et al. Urban Informatics",
        title="Identifying environmental stress factors in urban cycling")
    (lit / "moser2026identifying.pdf").write_bytes((inbox / "s44212-025-00096-6 (1).pdf").read_bytes())
    pdf(inbox / "ye2018.pdf", "Ye et al. Lecture Notes doi.org/10.1007/978", title="Physical Violence Detection with Movement Sensors")
    pdf(inbox / "Rechnung_2026_4711.pdf", "doi 10.1000/x Invoice total")
    cfg = {"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"}, "agentDir": "agents/longhand",
           "inbox": str(inbox)}
    la.doc_folders(cfg)
    shown = la.downloads_papers(cfg)
    check([x["document"] for x in shown] == ["ye2018"],
          f"the papers shown: new ones only, never one the vault has, never a personal one ({shown})")
    data, _ = la.day_proposable(cfg, TODAY, "I have new papers in my downloads")
    check([x["document"] for x in data.get("papers_in_downloads", [])] == ["ye2018"],
          "a message about downloads carries them")
    data, _ = la.day_proposable(cfg, TODAY, "move my late tasks to today")
    check("papers_in_downloads" not in data, "any other message does not")
    msg = "file /home/x/Downloads/s44212-025-00096-6 (1).pdf"
    filed, refused = la.day_file(cfg, [{"document": "s44212-025-00096-6 (1)", "project": "thesis"},
                                       {"document": "ye2018", "project": "thesis"}], msg, "2026-11-19T11:04:00")
    check(len(refused) == 1 and "already in your vault" in refused[0] and "moser2026identifying.pdf" in refused[0],
          f"a paper the vault holds is not filed, and the copy is named ({refused})")
    check((inbox / "s44212-025-00096-6 (1).pdf").is_file(), "it is left in Downloads")
    check(len(filed) == 1 and filed[0]["name"] == "Ye 2018 Physical Violence Detection with Movement Sensors.pdf",
          f"the paper the agent was shown is filed by its author and year ({filed})")
    check(filed and pathlib.Path(filed[0]["path"]).parent == lit, "into the folder the project's Docs: line names")
    listed = json.loads(json.dumps(doclib.index(vault, "projects", "thesis")))
    check(sorted(x["file"] for x in listed) == ["Ye 2018 Physical Violence Detection with Movement Sensors.pdf",
                                                 "moser2026identifying.pdf"],
          "the project's documents are that folder's")


def main() -> int:
    names()
    vault_twins()
    folders()
    redate()
    runner()
    print(f"\n{failures} failure(s)" if failures else "\nall passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
