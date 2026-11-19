"""The names a paper and a note are shown by (agent/names.py, 2026-11-19,
the student at the `@` list: "can we have the meaningful names instead of
the file names in there?"): a paper named by its BibTeX key by the nearest
bibliography that has it, a note by its heading, a paper's reading notes by
the paper, a private note by its file's name; and the same name from every
command that gives one (`conversation --files`, `longhand-read state`,
`days`, `papers`).

Run: python3 tests/test_names.py
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
sys.path.insert(0, str(ROOT / "tests"))
import names  # noqa: E402
from test_read import pdf  # noqa: E402

AGENT = ROOT / "agent" / "longhand-agent"
READ = ROOT / "cli" / "longhand-read"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


BIB = """@article{moser2023individual,
  author = {Moser, Martin Karl and Resch, Bernd and Ehrhart, Maximilian},
  title = {An {Individual-Oriented} Algorithm for Stress Detection},
  year = {2023},
}
@inproceedings{lee2020two,
  author = "Lee, Ann and Park, Bo",
  title = "Two of Us",
  date = {2020-05-01},
}
@book{solo2019,
  author = {Jane Solo},
  title = {Alone},
  year = 2019,
}
"""


def rules(tmp: pathlib.Path) -> None:
    got = names.entries(BIB)
    check(names.label(got["moser2023individual"]) == "Moser et al. 2023"
          and got["moser2023individual"]["title"] == "An Individual-Oriented Algorithm for Stress Detection",
          "a bibliography's entry: its first author, et al., the year; the title without its braces")
    check(names.label(got["lee2020two"]) == "Lee and Park 2020" and names.label(got["solo2019"]) == "Solo 2019",
          "…two authors by both names, a year from its date or bare")

    vault = tmp / "nearest"
    for rel, key, who in (("projects/a/refs.bib", "kim2021", "Kim, A"), ("projects/b/refs.bib", "kim2021", "Kimura, B"),
                          ("projects/b/archive/old.bib", "old2000", "Old, C"), ("projects/b/.hidden/h.bib", "hid2000", "Hid, D")):
        (vault / rel).parent.mkdir(parents=True, exist_ok=True)
        (vault / rel).write_text(f"@article{{{key}, author = {{{who}}}, title = {{T}}, year = {{2021}}}}\n")
    b = names.Bibs(vault)
    check(b.paper("projects/b/lit/kim2021.pdf") == ("Kimura 2021", "T") and b.paper("projects/a/kim2021.pdf")[0] == "Kim 2021",
          "a key in two bibliographies: the nearest one's, by the folders they share")
    check(b.paper("elsewhere/kim2021.pdf", near="projects/a")[0] == "Kim 2021",
          "…or the one nearest a project's folder, when it is asked for")
    check(b.paper("projects/b/old2000.pdf") == ("old2000", "") and b.paper("projects/b/hid2000.pdf")[0] == "hid2000"
          and b.paper("projects/b/Smith 2020 Testing.pdf") == ("Smith 2020 Testing", ""),
          "archived and hidden bibliographies are not read; a paper no bibliography has keeps its file's name")

    check(names.note("---\ntags: x\n---\n\n# Meeting with [[people/Ann|Ann]] — **2026-10-28**\n\nbody", "m/2026-10-28_ann.md")
          == "Meeting with Ann — 2026-10-28", "a note: its first heading, past its frontmatter, links and emphasis off")
    check(names.note("Some words first.\n# Later\n", "n/plain.md") == "plain" and names.note("", "n/empty.md") == "empty",
          "…its file's name when it does not begin with one")
    check(names.note("---\nagent: false\n---\n# Diary of mine\n", "n/closed.md") == "closed",
          "…a private note always its file's name: nothing it says is carried")
    reading = '---\npdf: "[[projects/b/lit/kim2021.pdf]]"\npdf-path: "projects/b/lit/kim2021.pdf"\n---\n# kim2021\n'
    check(names.note(reading, "human/Readings/kim2021.md", b) == "Kimura 2021 — reading notes",
          "…a paper's reading notes by the paper")


def commands(tmp: pathlib.Path) -> None:
    vault = tmp / "vault"
    (vault / "human" / "Daily").mkdir(parents=True)
    (vault / "human" / "Studies" / "refs.bib").parent.mkdir(parents=True)
    (vault / "human" / "Studies" / "refs.bib").write_text(BIB)
    paper = "human/Studies/lit/moser2023individual.pdf"
    pdf(vault / paper, [["Stress is measured on the skin."] + ["filler"] * 8])
    plain = "human/Studies/lit/Smith 2020 Testing.pdf"
    pdf(vault / plain, [["Testing is retrieval."] + ["filler"] * 8])
    (vault / "human" / "Studies" / "2026-10-28_moser.md").write_text("# Meeting with Martin Moser\n\nNotes.\n")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m",
                               "searchFolders": {"human/Readings": True}}))
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir))

    def run(*argv):
        r = subprocess.run([sys.executable, *map(str, argv)], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)

    files = {f["rel"]: f for f in run(AGENT, "conversation", "--files")["files"]}
    check(files.get(paper, {}).get("name") == "Moser et al. 2023"
          and files[paper]["title"] == "An Individual-Oriented Algorithm for Stress Detection",
          f"@ offers a paper by its bibliography's name, its title beside it ({files.get(paper)})")
    check(files.get(plain, {}).get("name") == "Smith 2020 Testing"
          and files.get("human/Studies/2026-10-28_moser.md", {}).get("name") == "Meeting with Martin Moser",
          "…another paper by its file's name, a note by its heading")
    st = run(READ, "state", "--pdf", paper)
    check(st.get("name") == "Moser et al. 2023", f"the paper's own header says the same name ({st.get('name')})")
    run(READ, "mark", "--pdf", paper, "--page", "1", "--text", "measured on the skin", "--kind", "h", "--day", "2026-11-18")
    day = run(READ, "days")["days"].get("2026-11-18") or []
    check([r.get("name") for r in day] == ["Moser et al. 2023"], f"…and the day's READ list ({[r.get('name') for r in day]})")
    rows = run(READ, "papers", "--tag", "thesis", "--dir", "human/Studies")["papers"]
    row = next((r for r in rows if r["pdf"] == paper), {})
    check(row.get("name") == "Moser et al. 2023" and row.get("cite", {}).get("authors") == "Moser et al.",
          f"…and the project's papers ({row.get('name')}, {row.get('cite')})")
    files = {f["rel"]: f for f in run(AGENT, "conversation", "--files")["files"]}
    notes = [f["name"] for f in files.values() if f["kind"] == "note" and "Readings" in f["rel"]]
    check(notes == ["Moser et al. 2023 — reading notes"], f"…and its reading notes, by the paper ({notes})")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="longhand-names-") as t:
        tmp = pathlib.Path(t)
        rules(tmp)
        commands(tmp)
    print("PASS" if not failures else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
