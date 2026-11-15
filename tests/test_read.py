"""Reading papers (docs/plan.md, item 15): longhand-read against a throwaway
vault, with PDFs made here. The reading note's shape, page order, the two
kinds, a note under a mark, removal, the project's tag, and finding the
words again: loosely, on the pages around, across a page's foot, with
context when a phrase repeats, and never dropping one that cannot be found.

Run: python3 tests/test_read.py
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
READ = ROOT / "cli" / "longhand-read"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def pdf(path: pathlib.Path, pages: list[list[str]], lead: int = 14) -> None:
    """A PDF with these lines on each page, from the top, `lead` pt apart."""
    path.parent.mkdir(parents=True, exist_ok=True)
    kids = " ".join(f"{4 + 2 * i} 0 R" for i in range(len(pages)))
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
            f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>".encode(),
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    for i, lines in enumerate(pages):
        body = f"BT /F1 11 Tf {lead} TL 72 720 Td " + " ".join(f"({t}) Tj T*" for t in lines) + " ET"
        stream = body.encode()
        objs.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents {5 + 2 * i} 0 R "
                    "/Resources << /Font << /F1 3 0 R >> >> >>".encode())
        objs.append(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream")
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
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-read-"))
    vault = tmp / "vault"
    (vault / "human" / "Daily").mkdir(parents=True)
    (tmp / "config.json").write_text(json.dumps({"vault": str(vault), "daily": {"dir": "human/Daily"}}))
    env = dict(os.environ, XDG_STATE_HOME=str(tmp / "state"), LONGHAND_CONFIG=str(tmp / "config.json"))

    def run(*args, ok=True):
        r = subprocess.run([str(READ), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr
            return json.loads(r.stdout)
        return r

    paper = "lit/Smith 2020.pdf"
    pdf(vault / paper, [
        ["Why testing helps", "Retrieval changes the memory it", "retrieves, each recall makes the next", "one easier. Testing is retrieval."],
        ["Spacing compounds the effect.", "Sessions a day apart beat one", "sitting. Testing is retrieval."],
        ["Sleep was not controlled. The psycho-", "logical account waits for section five,", "which closes the"],
        ["argument with a final caveat.", "End."],
    ])
    reading = vault / "human" / "Readings" / "Smith 2020.md"

    s = run("state", "--pdf", paper)
    check(s["note"] == "" and s["marks"] == [] and s["text"] and s["pages"] == 4,
          "a paper never marked has no reading note, and nothing is written for opening it")
    check(not reading.exists(), "…no file either")

    # A highlight across lines, as Qt gives a selection: line breaks as \r\n.
    s = run("mark", "--pdf", paper, "--page", "1", "--text", "memory it\r\nretrieves, each recall", "--day", "2026-11-15")
    check(s["note"] == "human/Readings/Smith 2020.md" and reading.is_file(),
          "the first mark makes the reading note, named after the PDF, in <notes>/Readings")
    text = reading.read_text()
    check(text.startswith('---\npdf: "[[lit/Smith 2020.pdf]]"\n---\n# Smith 2020\n'),
          f"its top links the PDF and names it ({text[:80]!r})")
    check("> memory it retrieves, each recall\n> — [[lit/Smith 2020.pdf#page=1|p. 1]] · 2026-11-15 ^h1" in text,
          "a highlight is the quoted words, one line, then its page link, day and name")
    m = s["marks"][0]
    check(m["placed"] and m["found"] == 1 and len(m["boxes"]) == 1 and m["boxes"][0]["page"] == 0
          and len(m["boxes"][0]["rects"]) == 2,
          f"it is found on its page, one rectangle per line it stands on ({m['boxes']})")
    r1, r2 = m["boxes"][0]["rects"]
    check(r1[1] < r2[1] and r1[2] > 0 and r1[3] > 0, "…in points from the top left, top line first")
    check(r1[1] + r1[3] <= r2[1] + 0.01, "…the lines' boxes never crossing, so nothing is drawn twice")
    check(s["span"] is None, "too few words to tell where the text stands: no span")

    # A question, on a later page, then a highlight on an earlier one: page order.
    s = run("mark", "--pdf", paper, "--page", "2", "--text", "Sessions a day apart", "--kind", "q", "--day", "2026-11-15")
    s = run("mark", "--pdf", paper, "--page", "1", "--text", "Why testing helps", "--day", "2026-11-16")
    ids = [(x["id"], x["kind"], x["page"]) for x in s["marks"]]
    check(ids == [("h3", "h", 1), ("h1", "h", 1), ("h2", "q", 2)],
          f"marks are kept in page order, and down the page within one ({ids})")
    text = reading.read_text()
    check("> [!question]\n> Sessions a day apart\n> — [[lit/Smith 2020.pdf#page=2|p. 2]] · 2026-11-15 ^h2" in text,
          "a question is the same block, opened by [!question]")

    # A phrase twice on its page: the one meant, by where the selection began,
    # and a few words from before it, so it is found again.
    s = run("state", "--pdf", paper)
    rows = {x["id"]: x for x in s["marks"]}
    s = run("mark", "--pdf", paper, "--page", "1", "--text", "retrieval", "--y", "130", "--day", "2026-11-16")
    text = reading.read_text()
    check("> retrieval\n> — [[lit/Smith 2020.pdf#page=1|p. 1]] · 2026-11-16 · after “easier. Testing is” ^h4" in text,
          "a phrase that repeats on its page keeps the words before it")
    h4 = next(x for x in s["marks"] if x["id"] == "h4")
    check(h4["placed"] and h4["boxes"][0]["rects"][0][1] > rows["h1"]["boxes"][0]["rects"][-1][1],
          "…and is drawn where it was selected, not at its first match")
    check(rows["h3"]["boxes"][0]["rects"][0][1] < rows["h1"]["boxes"][0]["rects"][0][1], "(the title stands above)")

    # Loosely: the hyphen a line was broken at, Qt's U+FFFE for it, ligatures.
    s = run("mark", "--pdf", paper, "--page", "3", "--text", "The psycho\ufffelogical account", "--day", "2026-11-16")
    h5 = next(x for x in s["marks"] if x["id"] == "h5")
    check(h5["placed"] and h5["text"] == "The psychological account" and len(h5["boxes"][0]["rects"]) == 2,
          f"a word broken over two lines is matched and written whole ({h5['text']!r})")
    s = run("mark", "--pdf", paper, "--page", "4", "--text", "a  \ufb01nal\u00a0CAVEAT", "--day", "2026-11-16")
    check(all(x["placed"] for x in s["marks"]), "ligatures, spacing and case never stop a match")

    # Across a page's foot: drawn on both pages.
    s = run("mark", "--pdf", paper, "--page", "3", "--text", "which closes the argument with a final caveat", "--day", "2026-11-16")
    h7 = next(x for x in s["marks"] if x["id"] == "h7")
    check(h7["placed"] and [b["page"] for b in h7["boxes"]] == [2, 3],
          f"a quote over a page's foot is drawn on both pages ({[b['page'] for b in h7['boxes']]})")

    # A note under a mark, changed, then gone.
    s = run("note", "--pdf", paper, "--id", "h1", "--text", "core claim for ch. 2")
    check(next(x for x in s["marks"] if x["id"] == "h1")["note"] == "core claim for ch. 2"
          and "^h1\n\ncore claim for ch. 2\n" in reading.read_text(), "a note goes under its quote")
    s = run("note", "--pdf", paper, "--id", "h1", "--text", "the core claim")
    check(next(x for x in s["marks"] if x["id"] == "h1")["note"] == "the core claim" and "core claim for ch. 2" not in reading.read_text(),
          "…a second one replaces it")
    others = {x["id"]: x["note"] for x in s["marks"] if x["id"] != "h1"}
    check(all(v == "" for v in others.values()), f"…and no other mark takes it as its own ({others})")
    s = run("note", "--pdf", paper, "--id", "h1", "--text", "")
    check(next(x for x in s["marks"] if x["id"] == "h1")["note"] == "" and "the core claim" not in reading.read_text(),
          "…and an empty one takes it away")

    # The kind, switched both ways.
    s = run("kind", "--pdf", paper, "--id", "h3", "--kind", "q")
    check(next(x for x in s["marks"] if x["id"] == "h3")["kind"] == "q" and "> [!question]\n> Why testing helps" in reading.read_text(),
          "a highlight becomes a question")
    s = run("kind", "--pdf", paper, "--id", "h3", "--kind", "h")
    check(next(x for x in s["marks"] if x["id"] == "h3")["kind"] == "h" and "[!question]\n> Why testing helps" not in reading.read_text(),
          "…and back")

    # Removed, with its note; the others untouched.
    run("note", "--pdf", paper, "--id", "h5", "--text", "check this")
    before = {x["id"] for x in run("state", "--pdf", paper)["marks"]}
    s = run("remove", "--pdf", paper, "--id", "h5")
    after = {x["id"] for x in s["marks"]}
    check(before - after == {"h5"} and "check this" not in reading.read_text() and "psychological" not in reading.read_text(),
          "a mark removed takes its note with it, and only it")
    check("\n\n\n" not in reading.read_text(), "…leaving no gap of blank lines")
    s = run("mark", "--pdf", paper, "--page", "2", "--text", "Spacing compounds", "--day", "2026-11-16")
    check("h8" in {x["id"] for x in s["marks"]}, "a new mark never takes a name used before in the note")

    # The project's tag, under the title; again is a no-op.
    s = run("tag", "--pdf", paper, "--tag", "thesis")
    s = run("tag", "--pdf", paper, "--tag", "#thesis")
    check(s["tags"] == ["thesis"] and reading.read_text().count("#thesis") == 1 and "# Smith 2020\n\n#thesis\n" in reading.read_text(),
          "a project's tag goes under the title, once")
    s = run("tag", "--pdf", paper, "--tag", "respro")
    check(s["tags"] == ["thesis", "respro"] and "\n#thesis #respro\n" in reading.read_text(), "…and a second beside it")

    # The person's own writing in the note is kept through every change.
    text = reading.read_text().replace("# Smith 2020\n", "# Smith 2020\n\nRead for the methods chapter.\n", 1)
    reading.write_text(text)
    run("mark", "--pdf", paper, "--page", "4", "--text", "End.", "--day", "2026-11-16")
    check("Read for the methods chapter." in reading.read_text(), "words written in the note by hand stay")

    # Not on its page: found on the one beside it (the PDF changed), or
    # reported as not placed — never dropped.
    text = reading.read_text().replace("#page=2|p. 2]] · 2026-11-15 ^h2", "#page=1|p. 1]] · 2026-11-15 ^h2")
    reading.write_text(text)
    s = run("state", "--pdf", paper)
    h2 = next(x for x in s["marks"] if x["id"] == "h2")
    check(h2["placed"] and h2["page"] == 1 and h2["found"] == 2, "a mark moved to the next page is found there")
    reading.write_text(reading.read_text().replace("> Spacing compounds", "> Spacing never compounds"))
    s = run("state", "--pdf", paper)
    lost = [x for x in s["marks"] if not x["placed"]]
    check(len(lost) == 1 and lost[0]["text"] == "Spacing never compounds" and s["unplaced"] == 1,
          "words found nowhere are listed as not placed, not lost")

    # A name taken by another paper's note: the PDF's folder is added.
    other = "other/Smith 2020.pdf"
    pdf(vault / other, [["A different paper."]])
    s = run("mark", "--pdf", other, "--page", "1", "--text", "different paper", "--day", "2026-11-16")
    check(s["note"] == "human/Readings/Smith 2020 (other).md" and len(s["marks"]) == 1,
          f"two papers with one name get two notes ({s['note']})")
    check(len(run("state", "--pdf", paper)["marks"]) > 1, "…and the first is still found by its link, not its name")

    # A `readings` folder in the config.
    cfg = json.loads((tmp / "config.json").read_text())
    cfg["readings"] = "Papers"
    (tmp / "config.json").write_text(json.dumps(cfg))
    s = run("mark", "--pdf", "other/Smith 2020.pdf", "--page", "1", "--text", "A different", "--day", "2026-11-16")
    check(s["note"].startswith("Papers/"), "the config's `readings` names the folder")
    cfg.pop("readings")
    (tmp / "config.json").write_text(json.dumps(cfg))

    # A PDF with no words (scanned): said so, and nothing marked.
    scan = vault / "lit" / "scan.pdf"
    pdf(scan, [[]])
    s = run("state", "--pdf", "lit/scan.pdf")
    check(s["text"] is False, "a PDF with no text says so")
    r = run("mark", "--pdf", "lit/scan.pdf", "--page", "1", "--text", "   ", ok=False)
    check(r.returncode != 0 and not (vault / "human" / "Readings" / "scan.md").exists(), "nothing selected, nothing marked")

    # Lines set closer than their font is tall: their boxes meet halfway.
    tight = vault / "lit" / "tight.pdf"
    pdf(tight, [["word " * 12 + "end"] * 30], lead=8)
    s = run("mark", "--pdf", "lit/tight.pdf", "--page", "1", "--text", "end word word", "--y", "80", "--day", "2026-11-16")
    rs = s["marks"][0]["boxes"][0]["rects"]
    check(len(rs) == 2 and rs[0][1] + rs[0][3] <= rs[1][1] + 0.01, f"boxes of lines set tight meet, not cross ({rs})")
    sp = s["span"]
    check(sp and abs(sp["x0"] - 72) < 1 and sp["w"] == 612 and sp["x1"] > sp["x0"] + 100,
          f"where the text stands across the page, to fit it by its text ({sp})")

    # A private folder: read, never marked (the agent is never given it).
    pdf(vault / "human" / "Personal" / "statement.pdf", [["Account balance and other private lines"] * 30])
    s = run("state", "--pdf", "human/Personal/statement.pdf")
    check(s["private"] is True and s["text"], "a PDF in the Personal folder is private, and still read")
    r = run("mark", "--pdf", "human/Personal/statement.pdf", "--page", "1", "--text", "Account balance", ok=False)
    check(r.returncode != 0 and "private" in r.stderr and not (vault / "human" / "Readings" / "statement.md").exists(),
          "…and takes no marks")
    check(run("state", "--pdf", paper)["private"] is False, "a paper elsewhere is not")
    cfg = json.loads((tmp / "config.json").read_text())
    cfg["private"] = ["lit"]
    (tmp / "config.json").write_text(json.dumps(cfg))
    check(run("state", "--pdf", paper)["private"] is True and run("state", "--pdf", "human/Personal/statement.pdf")["private"] is False,
          "the config's `private` names the folders instead")
    cfg.pop("private")
    (tmp / "config.json").write_text(json.dumps(cfg))

    f = run("find", "--pdf", paper, "--page", "2", "--text", "Sessions a day apart")
    check(f["found"] == 2 and f["boxes"] and f["boxes"][0]["page"] == 1, f"find: quoted words shown where they are ({f})")
    f = run("find", "--pdf", paper, "--page", "1", "--text", "words that are nowhere at all")
    check(f["found"] == 0 and f["boxes"] == [], "…and nothing when they are nowhere")

    # What was read on each day, from the reading notes alone.
    d = subprocess.run([str(READ), "days"], capture_output=True, text=True, env=env)
    days = json.loads(d.stdout)["days"]
    on15 = {r["title"]: r for r in days.get("2026-11-15", [])}
    on16 = {r["title"]: r for r in days.get("2026-11-16", [])}
    check(d.returncode == 0 and "Smith 2020" in on15 and on15["Smith 2020"]["pdf"] == paper and on15["Smith 2020"]["h"] >= 1,
          f"days: each day's papers, from the marks' own days ({days.get('2026-11-15')})")
    check("Smith 2020" in on16 and on16["Smith 2020"]["h"] + on16["Smith 2020"]["q"] >= 3, "…counted as highlights and questions that day")

    # A scan (plan.md item 15, step 5): no words of its own; `ocr` reads it
    # into a copy with a text layer, kept in the state folder, and then it
    # is marked as any paper is. The original is never written.
    import shutil
    if all(shutil.which(x) for x in ("magick", "pdftoppm", "tesseract", "qpdf")):
        src = tmp / "typed.pdf"
        pdf(src, [["Reflexive thematic analysis is a method", "for finding patterns of meaning in data."]])
        subprocess.run(["pdftoppm", "-r", "150", "-png", "-singlefile", str(src), str(tmp / "scanpage")], check=True)
        scan = vault / "lit" / "scanned.pdf"
        subprocess.run(["magick", str(tmp / "scanpage.png"), "-units", "PixelsPerInch", "-density", "150", str(scan)], check=True)
        before = scan.read_bytes()
        s = run("state", "--pdf", "lit/scanned.pdf")
        check(s["scanned"] and not s["text"] and s["ocr"] == "", f"a scan has no words, and no copy yet ({s})")
        r = subprocess.run([str(READ), "ocr", "--pdf", "lit/scanned.pdf"], capture_output=True, text=True, env=env)
        lines = r.stdout.strip().split("\n")
        check(r.returncode == 0 and json.loads(lines[0]).get("ocr", {}).get("pages") == 1,
              f"ocr says how far it is, a line a page ({lines[0] if lines else r.stderr})")
        s = json.loads(lines[-1])
        check(s["scanned"] and s["text"] and s["ocr"].endswith(".pdf") and pathlib.Path(s["ocr"]).is_file()
              and str(tmp / "state") in s["ocr"], f"…then it has words, from a copy in the state folder ({s['ocr']})")
        check(scan.read_bytes() == before, "…and the scan itself is untouched")
        s = run("mark", "--pdf", "lit/scanned.pdf", "--page", "1", "--text", "thematic analysis", "--day", "2026-11-16")
        m = s["marks"][0]
        check(m["placed"] and m["boxes"] and abs(m["boxes"][0]["rects"][0][1] - 70) < 20,
              f"…and is marked as any paper is, where the words are ({m['boxes']})")
        r = subprocess.run([str(READ), "ocr", "--pdf", paper], capture_output=True, text=True, env=env)
        check(r.returncode != 0 and "words already" in r.stderr, "a PDF with words of its own is not read again")
    else:
        print("skip a scan read (magick, pdftoppm, tesseract or qpdf missing)")

    r = run("state", "--pdf", "lit/missing.pdf", ok=False)
    check(r.returncode != 0 and "no PDF" in r.stderr, "a PDF that is not there is refused")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
