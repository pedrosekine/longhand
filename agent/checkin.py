"""How Longhand feels, once a week (2026-11-18, the UX evaluation's F7).

Five weeks of use had two helpful / not helpful ratings, so nothing said
whether the student was satisfied, only what they used. The check-in is
the short User Experience Questionnaire (UEQ-S; Schrepp, Hinderks &
Thomaschewski, 2017): eight pairs of words, each answered on seven steps.
The first four make its pragmatic quality ("practical": supportive, easy,
efficient, clear), the last four its hedonic quality ("pleasant": exciting,
interesting, inventive, leading edge). A step is kept as 1..7 and scored as
-3..+3, the questionnaire's own way; a week's two scores are the means.

Asked at most once an ISO week, never as a pop-up: the dashboard says it
is due, and a key or a click opens it; skipping counts as the week's
answer. Each machine appends its answers to a log of its own in the vault
(`<agentDir>/checkins/<host>.jsonl`), as the proposals do, so the two
machines agree on whether the week is answered and nothing is written to
one file from two places. The trend sits beside the agent's share of its
proposals the student acted on, that week — the evaluation's measure for
the agent's volume (F1).
"""
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

ITEMS = [("obstructive", "supportive"), ("complicated", "easy"), ("inefficient", "efficient"),
         ("confusing", "clear"), ("boring", "exciting"), ("not interesting", "interesting"),
         ("conventional", "inventive"), ("usual", "leading edge")]
PRAGMATIC = range(0, 4)
HEDONIC = range(4, 8)
ACTED = {"accepted", "declined", "answered", "undone"}


def week_of(day: dt.date) -> str:
    y, w, _ = day.isocalendar()
    return f"{y}-W{w:02d}"


def entries(folder: Path) -> list[dict]:
    out = []
    for f in sorted(folder.glob("*.jsonl")) if folder.is_dir() else []:
        try:
            lines = f.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                e = json.loads(line)
            except ValueError:
                continue                          # a line cut short mid-sync
            if isinstance(e, dict) and isinstance(e.get("week"), str):
                out.append(e)
    return sorted(out, key=lambda e: str(e.get("at", "")))


def valid(answers) -> bool:
    return isinstance(answers, list) and len(answers) == len(ITEMS) \
        and all(isinstance(a, int) and 1 <= a <= 7 for a in answers)


def scores(answers: list[int]) -> dict:
    s = [a - 4 for a in answers]
    mean = lambda idx: round(sum(s[i] for i in idx) / len(idx), 2)  # noqa: E731
    return {"pragmatic": mean(PRAGMATIC), "hedonic": mean(HEDONIC), "overall": mean(range(len(ITEMS)))}


def acted_share(ledger_items: list[dict], week: str) -> dict:
    """Of what the agent proposed that week (not a document filed from
    Downloads, not what it did on its own), how much the student settled."""
    made = [x for x in ledger_items if x.get("kind") != "file" and not x.get("auto")
            and _week_of_iso(x.get("at", "")) == week]
    acted = sum(1 for x in made if x.get("status") in ACTED)
    return {"made": len(made), "acted": acted, "share": round(acted / len(made), 2) if made else None}


def _week_of_iso(at: str) -> str:
    try:
        return week_of(dt.date.fromisoformat(str(at)[:10]))
    except ValueError:
        return ""


def status(folder: Path, today: dt.date, ledger_items: list[dict]) -> dict:
    """Whether this week is due, and every week answered, with the agent's
    acted-on share beside it (also for weeks skipped)."""
    week = week_of(today)
    es = entries(folder)
    by_week: dict[str, dict] = {}
    for e in es:
        by_week[e["week"]] = e                    # the last word on a week wins
    weeks = []
    for w in sorted(by_week):
        e = by_week[w]
        row = {"week": w, "skipped": bool(e.get("skipped")), "acted": acted_share(ledger_items, w)}
        if not row["skipped"] and valid(e.get("answers")):
            row.update(scores(e["answers"]), answers=e["answers"])
        weeks.append(row)
    return {"week": week, "due": week not in by_week, "items": [list(p) for p in ITEMS],
            "weeks": weeks, "acted_now": acted_share(ledger_items, week)}


def save(folder: Path, host: str, today: dt.date, at: str, answers: list[int] | None, skipped: bool) -> dict:
    if not skipped and not valid(answers):
        raise ValueError(f"{len(ITEMS)} answers, each 1..7")
    e = {"week": week_of(today), "at": at, "host": host, "skipped": skipped}
    if not skipped:
        e["answers"] = answers
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / f"{host}.jsonl", "a") as f:
        f.write(json.dumps(e, ensure_ascii=False) + "\n")
    return e
