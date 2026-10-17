"""The planning job's local half (docs/agent.md, slice 2, 2026-10-17).

The model brings judgement — which free day, whether something is missing,
what a box means. Everything that can be computed is computed here, and
handed to it as data: the fortnight day by day (classes and events, the
free hours of a working day, what is due, what is already planned), the
workload per project, and the boxes worth planning. What it answers is
checked here too, before anything reaches the person: a do-date only for a
box that was offered, on a day of the fortnight, never after the box's own
due date, never one the person already declined; at most two questions.

The ledger (proposals.json, beside the deadline store) keeps every proposal
and question and what came of it — accepted, declined, answered,
superseded by a later plan, or moot (the box got a date some other way, or
is gone). Acceptance is counted from it; the next plan is told it.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import tempfile
from pathlib import Path

import lifespan

DAYS = 14                    # the fortnight planned over
WORKDAY = (9 * 60, 18 * 60)  # minutes: the hours a free day is counted in
MAX_PROPOSALS = 5
MAX_QUESTIONS = 2
MAX_CANDIDATES = 12


# ------------------------------------------------------------------ inputs

def store_deadlines(store: Path) -> list[dict]:
    """The open deadlines of the store: id, due (local datetime), title,
    project, and whether a note holds its line."""
    out = []
    try:
        lines = store.read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        f = line.split("\t")
        if len(f) < 4 or not f[0].isdigit() or not f[1].lstrip("-").isdigit():
            continue
        if f[3] != "open":
            continue
        out.append({"id": int(f[0]), "due": dt.datetime.fromtimestamp(int(f[1])), "title": f[2],
                    "project": f[6] if len(f) > 6 else "", "linked": len(f) > 7 and "#^d" in f[7]})
    return out


def _minutes(a: dt.datetime, b: dt.datetime, day: dt.date) -> int:
    """How much of [a, b) falls inside the working day of `day`."""
    lo = dt.datetime.combine(day, dt.time()) + dt.timedelta(minutes=WORKDAY[0])
    hi = dt.datetime.combine(day, dt.time()) + dt.timedelta(minutes=WORKDAY[1])
    s, e = max(a, lo), min(b, hi)
    return max(0, int((e - s).total_seconds() // 60))


def fortnight(today: dt.date, events: list[dict], deadlines: list[dict], tasks: list[dict]) -> list[dict]:
    """The next two weeks, day by day: what is on (classes and the events
    the agent may see), how much of a working day is left free, what is due,
    and how many boxes already have the day as their do-date."""
    days = []
    for i in range(DAYS):
        d = today + dt.timedelta(days=i)
        on = [e for e in events if e["start"].date() == d]
        busy = sum(_minutes(e["start"], e["end"], d) for e in on)
        days.append({
            "date": d.isoformat(), "weekday": d.strftime("%a"), "weekend": d.weekday() >= 5,
            "on": [f"{e['start']:%H:%M}–{e['end']:%H:%M} {e.get('label') or e['summary']}" for e in on],
            "free_hours": round(max(0, (WORKDAY[1] - WORKDAY[0]) - busy) / 60, 1),
            "due": [x["title"] for x in deadlines if x["due"].date() == d],
            "planned": sum(1 for t in tasks if (t.get("when") or "")[:10] == d.isoformat()),
        })
    return days


def workload(tasks: list[dict], deadlines: list[dict], today: dt.date) -> list[dict]:
    """Per project: open tasks, deadlines inside the fortnight, the nearest."""
    horizon = today + dt.timedelta(days=DAYS)
    out: dict[str, dict] = {}
    for t in tasks:
        if t.get("kind") == "note":
            continue
        p = out.setdefault(t.get("project") or "", {"project": t.get("project") or "", "open_tasks": 0,
                                                     "deadlines": 0, "next_due": ""})
        p["open_tasks"] += 1
    for x in deadlines:
        if x["due"].date() > horizon:
            continue
        p = out.setdefault(x["project"] or "", {"project": x["project"] or "", "open_tasks": 0,
                                                 "deadlines": 0, "next_due": ""})
        p["deadlines"] += 1
        due = x["due"].date().isoformat()
        if not p["next_due"] or due < p["next_due"]:
            p["next_due"] = due
    return sorted(out.values(), key=lambda p: (p["next_due"] or "9999", p["project"]))


def candidates(tasks: list[dict], deadlines: list[dict], today: dt.date) -> list[dict]:
    """The boxes worth planning: open tasks and deadlines with no do-date,
    and not put away (quiet or shelved). A note box is thinking, not work to
    schedule, and is left alone. Nearest due date first, then priority, then
    the oldest."""
    by_anchor = {x["id"]: x for x in deadlines}
    out = []
    for t in tasks:
        if t.get("done") or t.get("cancelled") or t.get("when") or t.get("away"):
            continue
        if t.get("kind") == "note":
            continue
        due = t.get("due") or ""
        if t.get("anchor") and t["anchor"] in by_anchor:
            due = by_anchor[t["anchor"]]["due"].strftime("%Y-%m-%d %H:%M")
        if due and due[:10] < today.isoformat():
            continue                                  # already late: a do-date cannot help
        out.append({"key": t.get("key") or lifespan.key_of(t), "title": t.get("title") or t.get("text", ""),
                    "project": t.get("project") or "", "where": " › ".join(t.get("path") or []),
                    "due": due, "priority": t.get("priority") or 0, "est": t.get("est") or "",
                    "written": t.get("date", ""), "age_days": t.get("age", 0)})
    out.sort(key=lambda c: (c["due"] or "9999", -c["priority"], -c["age_days"]))
    return out[:MAX_CANDIDATES]


def inputs_hash(cands: list[dict], days: list[dict]) -> str:
    """What a plan rests on: when it has not changed, planning again the same
    day would only say the same thing."""
    blob = json.dumps({"c": [(c["key"], c["due"], c["priority"]) for c in cands],
                       "d": [(d["date"], d["on"], d["due"], d["planned"]) for d in days]}, sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


# ------------------------------------------------------------------ the ledger

def _write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w") as f:
        f.write(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def load_ledger(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            return data
    except (OSError, ValueError):
        pass
    return {"next": 1, "items": []}


def save_ledger(path: Path, data: dict) -> None:
    _write(path, data)


def open_items(ledger: dict) -> list[dict]:
    return [x for x in ledger["items"] if x.get("status") == "open"]


def summary(ledger: dict) -> dict:
    """Per kind: how many proposed, and what came of them."""
    out: dict[str, dict] = {}
    for x in ledger["items"]:
        k = out.setdefault(x["kind"], {})
        k[x["status"]] = k.get(x["status"], 0) + 1
    return out


def declined(ledger: dict) -> set[tuple[str, str]]:
    return {(x["key"], x.get("date", "")) for x in ledger["items"]
            if x["kind"] == "do-date" and x["status"] == "declined"}


def validate(reply: dict, cands: list[dict], days: list[dict], ledger: dict, today: dt.date) -> tuple[list[dict], list[dict]]:
    """What the model said, kept only where it holds."""
    by_key = {c["key"]: c for c in cands}
    window = {d["date"] for d in days}
    no = declined(ledger)
    props, seen = [], set()
    for p in reply.get("proposals") or []:
        if not isinstance(p, dict) or p.get("kind") != "do-date":
            continue
        key, date = str(p.get("key") or ""), str(p.get("date") or "")[:10]
        c = by_key.get(key)
        if not c or date not in window or key in seen or (key, date) in no:
            continue
        if c["due"] and date > c["due"][:10]:
            continue                                  # never after its own due date
        seen.add(key)
        props.append({"kind": "do-date", "key": key, "date": date, "why": str(p.get("why") or "").strip()[:300],
                      "title": c["title"], "project": c["project"]})
        if len(props) >= MAX_PROPOSALS:
            break
    qs = []
    for q in reply.get("questions") or []:
        if not isinstance(q, dict):
            continue
        text, rec = str(q.get("question") or "").strip(), str(q.get("recommended") or "").strip()
        key = str(q.get("key") or "")
        if not text or not rec or (key and key not in by_key):
            continue
        qs.append({"kind": "question", "key": key, "question": text[:300], "recommended": rec[:200],
                   "title": by_key[key]["title"] if key else "", "project": by_key[key]["project"] if key else ""})
        if len(qs) >= MAX_QUESTIONS:
            break
    return props, qs


def record(ledger: dict, props: list[dict], qs: list[dict], at: str) -> list[dict]:
    """A new plan: what it proposes replaces what an earlier one left open
    about the same boxes (superseded); the rest of the earlier ones stand."""
    keys = {p["key"] for p in props}
    asked = {q["key"] for q in qs if q["key"]}
    for x in open_items(ledger):
        if (x["kind"] == "do-date" and x["key"] in keys) or (x["kind"] == "question" and x["key"] and x["key"] in asked):
            x["status"], x["resolved"] = "superseded", at
    new = []
    for item in props + qs:
        item = dict(item, id=ledger["next"], status="open", at=at)
        ledger["next"] += 1
        ledger["items"].append(item)
        new.append(item)
    return new


def settle_moot(ledger: dict, tasks: list[dict], at: str) -> int:
    """An open do-date whose box has a date now, is done, or is gone, no
    longer asks anything: moot."""
    live = {(t.get("key") or lifespan.key_of(t)): t for t in tasks}
    n = 0
    for x in open_items(ledger):
        if x["kind"] != "do-date":
            continue
        t = live.get(x["key"])
        if t is None or t.get("when") or t.get("done") or t.get("cancelled"):
            x["status"], x["resolved"] = "moot", at
            n += 1
    return n


def resolve(ledger: dict, item_id: int, status: str, at: str, answer: str = "") -> dict | None:
    for x in ledger["items"]:
        if x["id"] == item_id and x["status"] == "open":
            x["status"], x["resolved"] = status, at
            if answer:
                x["answer"] = answer
            return x
    return None
