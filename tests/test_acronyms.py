"""Hover a paper to have it explained (docs/plan.md, item 18): `longhand-read
acronyms` against a throwaway vault, with PDFs made here. What a paper
spells out is found with no model (Schwartz–Hearst: "Long Form (LF)" and
"LF (Long Form)", plurals, a word broken across lines, a list of
abbreviations); what is not an acronym is left alone (a year, initials, a
heading in capitals, a word in capitals that is also written small, names
in the references, a German sentence before a parenthesis); every place
each is written is given to be hovered; it is kept by the file, and nothing
is written in the vault.

Run: python3 tests/test_acronyms.py
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
READ = ROOT / "cli" / "longhand-read"
sys.path.insert(0, str(ROOT / "tests"))
from test_read import pdf  # noqa: E402  (a PDF with these lines on each page)

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def pdf_at(path: pathlib.Path, items: list[tuple[float, float, str]]) -> None:
    """A one-page PDF with each text at (x, y from the top)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    body = " ".join(f"BT /F1 11 Tf 1 0 0 1 {x} {792 - y} Tm ({t}) Tj ET" for x, y, t in items).encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R /Resources << /Font << /F1 3 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(body) + body + b"\nendstream"]
    out = bytearray(b"%PDF-1.4\n")
    offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offs)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    path.write_bytes(bytes(out))


def main() -> int:
    if not shutil.which("pdftotext"):
        print("skip: pdftotext is not installed")
        return 0
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-acronyms-"))
    vault = tmp / "vault"
    (vault / "human" / "Daily").mkdir(parents=True)
    (tmp / "config.json").write_text(json.dumps({"vault": str(vault), "daily": {"dir": "human/Daily"}}))
    env = dict(os.environ, XDG_STATE_HOME=str(tmp / "state"), LONGHAND_CONFIG=str(tmp / "config.json"))

    def run(*args):
        r = subprocess.run([str(READ), *args], capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)

    paper = "lit/Stress 2024.pdf"
    pdf(vault / paper, [
        ["INTRODUCTION",
         "We measured heart rate variability (HRV) on bikes,",
         "with large language models (LLMs) reading notes.",
         "The WHO (World Health Organization) agrees.",
         "A Convolutional Neu-",
         "ral Network (CNN) saw the street (2020).",
         "Written by (J.M.) and checked (see Fig. 2).",
         "Der Umstieg auf das Fahrrad funktioniert nur (DStGB)."],
        ["HRV fell, and each LLM read it; CNN-based maps.",
         "The GPU ran it; another GPU ran too. Once: the TPU.",
         "STRESS rose. We call it stress here.",
         "The LLMs and the HRV agree."],
        ["The end."],
        ["References",
         "SMITH, J. A paper. SMITH, K. Another one."],
    ])

    a = run("acronyms", "--pdf", paper)
    defs = {x["short"]: x for x in a["acronyms"]}
    check(a["pdf"] == paper, "it says which paper it read")
    check(defs.get("HRV", {}).get("long") == "heart rate variability" and defs["HRV"]["page"] == 1,
          f"“Long Form (LF)”: the long form and its page ({defs.get('HRV')})")
    check(defs.get("LLM", {}).get("long") == "large language models",
          "a plural short form is kept without its s: LLMs → LLM")
    check(defs.get("WHO", {}).get("long") == "World Health Organization",
          "“LF (Long Form)”: the long form in the parenthesis")
    check(defs.get("CNN", {}).get("long") == "Convolutional Neural Network",
          f"a word broken across lines is joined again ({defs.get('CNN', {}).get('long')!r})")
    check(not ({"J.M", "J.M.", "JM", "Fig", "DStGB"} & set(defs)),
          f"a year, initials, a figure and a German sentence are not acronyms ({sorted(defs)})")
    r = defs["HRV"]["rects"]
    check(len(r) == 1 and r[0][2] > 100 and r[0][1] > 0,
          f"where it is spelled out: the long form and its short form, one rectangle on its line ({r})")

    spots = a["spots"]
    on2 = [s["a"] for s in spots.get("1", [])]
    check(on2.count("HRV") == 2 and on2.count("LLM") == 2 and "CNN" in on2,
          f"every place it is written is given, plurals too ({on2})")
    cnn = next(s for s in spots["1"] if s["a"] == "CNN")
    hrv = next(s for s in spots["1"] if s["a"] == "HRV")
    check(cnn["r"][2] < hrv["r"][2] * 1.2 and cnn["r"][2] > 0,
          "in “CNN-based” only the acronym's share of the word is hovered")
    check(any(s["a"] == "HRV" for s in spots.get("0", [])), "…and the place it is spelled out")

    und = {x["short"]: x for x in a["undefined"]}
    check(und.get("GPU", {}).get("count") == 2 and und["GPU"]["page"] == 2,
          f"one never spelled out, written twice, is listed as such ({a['undefined']})")
    check("TPU" not in und, "…never one written once")
    check("INTRODUCTION" not in und and "STRESS" not in und,
          "…never a heading in capitals, nor a word also written small")
    check("SMITH" not in und, "…nor a name in the references")
    check(any(s["a"] == "GPU" for s in spots.get("1", [])), "one never spelled out can be hovered too")

    # A list of abbreviations: the short form alone, its long form beside it.
    table = "lit/IEEE 2023.pdf"
    pdf_at(vault / table, [(72, 100, "Abbreviations used in this paper are below."),
                           (72, 130, "HR"), (130, 130, "Heart rate."),
                           (72, 145, "PPG"), (130, 145, "Photoplethysmography."),
                           (72, 160, "SD"), (130, 160, "Some unrelated words."),
                           (72, 200, "The HR and PPG were read; HR again.")])
    t = {x["short"]: x["long"] for x in run("acronyms", "--pdf", table)["acronyms"]}
    check(t.get("HR") == "Heart rate" and t.get("PPG") == "Photoplethysmography",
          f"a list of abbreviations is read, the short form beside its long form ({t})")
    check("SD" not in t, "…never words beside it that do not spell it")

    # Kept by the file: read again, the same; the file changed, read anew.
    kept = list((tmp / "state" / "longhand" / "reading" / "acronyms").glob("*.json"))
    check(len(kept) == 2, f"each paper's acronyms are kept in the state folder ({len(kept)})")
    check(run("acronyms", "--pdf", paper) == a, "read again, the same")
    pdf(vault / paper, [["We used heart rate variability (HRV) and the BPM (beats per minute)."]])
    b = {x["short"] for x in run("acronyms", "--pdf", paper)["acronyms"]}
    check(b == {"HRV", "BPM"}, f"the PDF changed: read anew ({b})")
    check(not (vault / "human" / "Readings").exists(), "nothing is written in the vault")

    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{'all passed' if failures == 0 else f'{failures} failed'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
