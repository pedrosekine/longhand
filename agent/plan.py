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
superseded by a later plan, moot (the box got a date some other way, or
is gone), or expired (left unanswered EXPIRE_DAYS). Acceptance is counted
from it; the next plan is told it.
"""
from __future__ import annotations

import datetime as dt
import fcntl
import hashlib
import json
import os
import tempfile
from pathlib import Path

import re

import lifespan

DAYS = 14                    # the fortnight planned over
WORKDAY = (9 * 60, 18 * 60)  # minutes: the hours a free day is counted in
MAX_PROPOSALS = 5            # of every kind together, a run
MAX_QUESTIONS = 2
MAX_CANDIDATES = 12
MAX_BOXES = 40               # the open boxes the planner sees for the other actions
MAX_STEPS = 5
STEP_CHARS = 100


def short_step(text) -> str:
    """A step as a line the student can tick: one line, at most STEP_CHARS,
    cut at a word with "…" when the model wrote it longer — never in the
    middle of a word, which once left "map … to" in a note."""
    s = re.sub(r"\s+", " ", str(text)).strip()
    if len(s) <= STEP_CHARS:
        return s
    cut = s[:STEP_CHARS - 1].rsplit(" ", 1)[0].rstrip(" ,;:—-")
    return cut + "…"
# What is on the student's screen stays put until they act on it (2026-11-17:
# 118 questions about 10 boxes, one reworded 39 times, each replacing the one
# before; 6 answered). A question or steps left this long unanswered may be
# asked afresh; a do-date stands until its day has gone by.
STANDING_DAYS = 7
# What waits on the student is kept small (2026-11-18, the UX evaluation in
# the vault, projects/longhand: 12–18 proposals a day, 9% acted on, 5% of
# questions answered). Unasked, a course has at most OPEN_PER_COURSE items
# waiting; one over it is not recorded, and comes back when there is room.
# What has waited EXPIRE_DAYS unanswered goes quiet: the agent's word, never
# the student's, so nothing of theirs is lost.
OPEN_PER_COURSE = 3
EXPIRE_DAYS = 14
STALE_DAYS = 14              # a box this old, or gone quiet, may be proposed for dropping

# The kinds of action (docs/agent.md, "Actions, and how far each may go"),
# with the words Settings and the dashboard use. Each has an autonomy the
# person sets: ask me (a proposal), do it and tell me (done, shown, one key
# undoes it), never. Every kind starts at "ask"; only the person raises one.
KINDS = {
    "do-date": "set a do-date",
    "deadline": "add a deadline from your writing",
    "priority": "set a priority",
    "steps": "add steps under a box",
    "drop": "propose dropping a stale box",
    "file": "file a document from the inbox",
    "done": "ask whether a box is done",
    "project": "propose a new project",
    # In a conversation only, where the student asks (2026-11-18, slice 4 of
    # "One conversation": what one message can do from anywhere).
    "task": "add a task you ask for",
    "move": "move a deadline you ask to move",
    "undone": "reopen a ticked box you ask to reopen",
}
ASKED_ONLY = {"task", "move", "undone"}     # never from a planning pass
LEVELS = ("ask", "do", "never")
# Ticking is the person's act, and so is making a project (2026-10-22):
# a question only.
ASK_ONLY = {"done", "project"}
PRIORITY_LEVELS = {2: "high", 1: "medium", -1: "low"}
RAISE_AFTER = 10             # answered proposals of a kind before raising is suggested
RAISE_ACCEPTED = 9          # …of which accepted


# ------------------------------------------------------------------ inputs

def store_deadlines(store: Path, statuses: tuple = ("open",)) -> list[dict]:
    """The store's deadlines with those statuses (open, by default): id, due
    (local datetime), title, project, status, and whether a note holds its
    line."""
    out = []
    try:
        lines = store.read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        f = line.split("\t")
        if len(f) < 4 or not f[0].isdigit() or not f[1].lstrip("-").isdigit():
            continue
        if f[3] not in statuses:
            continue
        out.append({"id": int(f[0]), "due": dt.datetime.fromtimestamp(int(f[1])), "title": f[2], "status": f[3],
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


def candidates(tasks: list[dict], deadlines: list[dict], today: dt.date, limit: int | None = MAX_CANDIDATES) -> list[dict]:
    """The boxes worth planning: open tasks and deadlines with no do-date,
    due after today, and not put away (quiet or shelved). A note box is thinking, not work to
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
        if due and due[:10] <= today.isoformat():
            continue                                  # due today or late: no day before it is left
        out.append({"key": t.get("key") or lifespan.key_of(t), "title": t.get("title") or t.get("text", ""),
                    "project": t.get("project") or "", "where": " › ".join(t.get("path") or []),
                    "due": due, "priority": t.get("priority") or 0, "est": t.get("est") or "",
                    "written": t.get("date", ""), "age_days": t.get("age", 0)})
    out.sort(key=lambda c: (c["due"] or "9999", -c["priority"], -c["age_days"]))
    return out[:limit]


def open_boxes(tasks: list[dict], deadlines: list[dict], today: dt.date, limit: int | None = MAX_BOXES) -> list[dict]:
    """Every open box the agent may see, for the actions that are not about a
    day: a priority, steps under it, dropping it, whether it is done. Quiet
    and shelved ones too (`quiet`) — a box gone quiet is what dropping is
    for. Nearest due first, then the oldest."""
    by_anchor = {x["id"]: x for x in deadlines}
    out = []
    for t in tasks:
        if t.get("done") or t.get("cancelled"):
            continue
        due = t.get("due") or ""
        if t.get("anchor") and t["anchor"] in by_anchor:
            due = by_anchor[t["anchor"]]["due"].strftime("%Y-%m-%d %H:%M")
        out.append({"key": t.get("key") or lifespan.key_of(t), "title": t.get("title") or t.get("text", ""),
                    "project": t.get("project") or "", "where": " › ".join(t.get("path") or []),
                    "due": due, "when": t.get("when") or "", "priority": t.get("priority") or 0,
                    "steps_under_it": t.get("details") or 0, "written": t.get("date", ""),
                    "age_days": t.get("age", 0), "quiet": bool(t.get("away")), "kind": t.get("kind") or "task",
                    "deadline": t["anchor"] if t.get("anchor") in by_anchor else 0})
    out.sort(key=lambda b: (b["due"] or "9999", -b["age_days"]))
    return out[:limit]


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


def hold(path: Path):
    """The ledger to one writer at a time, from its reading to its writing.
    The page asks the runner several things at once — the list, an answer,
    a plan, a conversation — each reading the ledger, changing it and
    writing it back, and the last to write won: an answer given while a
    plan ran was lost (2026-10-25). Held until the returned file is closed,
    or the process ends."""
    path.parent.mkdir(parents=True, exist_ok=True)
    f = open(path.parent / f".{path.name}.lock", "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


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
            if x["kind"] == "do-date" and x["status"] in ("declined", "undone")}


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", text or "")).strip().casefold()


STOPWORDS = {"the", "and", "for", "with", "from", "into", "your", "this", "that", "draft", "read", "have", "will"}


def _words(title: str) -> set[str]:
    return {w for w in norm(title).split() if len(w) >= 4 and w not in STOPWORDS}


def same_deadline(title: str, date: str, d: dict) -> bool:
    """Whether a proposed deadline is one the store already has, open or
    closed: the same words; or the same day and a word in common; or most of
    the shorter title's words in common. A model rewording a ticked box
    ("Proposal of version 1 …" → "Proposal v1") must not bring it back.
    Titles numbered alike whose numbers disagree are two of a series
    ("Diary 1", "Diary 2"), whatever words they share; a title with dates
    in its words ("weekly until Feb 4th") is still the series' own."""
    if norm(title) == norm(d["title"]):
        return True
    na, nb = sorted(int(n) for n in re.findall(r"\d+", title)), sorted(int(n) for n in re.findall(r"\d+", d["title"]))
    if na and len(na) == len(nb) and na != nb:
        return False
    a, b = _words(title), _words(d["title"])
    if not a or not b:
        return False
    common = a & b
    if d.get("due") and d["due"].date().isoformat() == date and common:
        return True
    return len(common) >= max(1, round(0.6 * min(len(a), len(b))))


def ident(x: dict) -> tuple[str, str]:
    """What one proposal is about: its kind and its box, or, for a deadline
    (which has no box yet), its words; for a project, its tag; for a drop of
    a deadline that has no line, its number; for a document to file, its
    contents (2026-11-17: by its course's name, a second paper for a course
    was "the same" as the one still waiting and never proposed)."""
    if x["kind"] == "file" and x.get("doc"):
        return (x["kind"], x["doc"])
    if x["kind"] == "project":
        return (x["kind"], str(x.get("project") or "").lower())
    if x["kind"] == "move":
        return (x["kind"], f"#{x.get('deadline')}@{x.get('date', '')}")   # each day it is moved to, its own
    if not x.get("key") and x.get("deadline"):
        return (x["kind"], f"#{x['deadline']}")      # a deadline with no line: its number
    return (x["kind"], x.get("key") or norm(x.get("title", "")))


def refused(ledger: dict) -> set[tuple[str, str]]:
    """Every proposal the person said no to, or undid: never proposed again
    (a do-date only on that day; another day may be proposed)."""
    return {ident(x) for x in ledger["items"]
            if x["status"] in ("declined", "undone") and x["kind"] not in {"do-date", "question"} | ASKED_ONLY}


# ---------------------------------------------------------------- autonomy

def autonomy(settings: dict | None) -> dict[str, str]:
    """Each kind's level, from settings.json's `autonomy`; "ask" when unset
    or unknown. A kind that is a question only stays one."""
    got = (settings or {}).get("autonomy") or {}
    out = {}
    for k in KINDS:
        v = got.get(k) if isinstance(got, dict) else None
        out[k] = v if v in LEVELS else "ask"
        if k in ASK_ONLY and out[k] == "do":
            out[k] = "ask"
    return out


def record_of(ledger: dict, kind: str) -> dict:
    """A kind's evidence, for Settings: of its last RAISE_AFTER answered
    proposals, how many were accepted — and whether that is enough to
    suggest "do it and tell me". Undoing what was done counts as a no."""
    answered = [x for x in ledger["items"] if x["kind"] == kind
                and x["status"] in ("accepted", "declined", "undone", "answered")]
    answered.sort(key=lambda x: x.get("resolved") or x.get("at") or "")
    last = answered[-RAISE_AFTER:]
    acc = sum(1 for x in last if x["status"] in ("accepted", "answered"))
    return {"kind": kind, "answered": len(last), "accepted": acc, "all_answered": len(answered),
            "suggest": len(last) >= RAISE_AFTER and acc >= RAISE_ACCEPTED and kind not in ASK_ONLY}


def validate(reply: dict, cands: list[dict], days: list[dict], ledger: dict, today: dt.date,
             boxes: list[dict] | None = None, deadlines: list[dict] | None = None,
             allowed: dict[str, str] | None = None, closed: list[dict] | None = None,
             projects: list[str] | None = None, asked: bool = False,
             ticked: list[dict] | None = None) -> tuple[list[dict], list[dict]]:
    """What the model said, kept only where it holds: every kind checked
    against what it was shown, against what the person already refused, and
    against what the person allows ("never" drops it). At most
    MAX_PROPOSALS of all kinds, in the model's order, and MAX_QUESTIONS.
    `asked`: a conversation, where the person is there and talking — a
    drop they ask for (a duplicate, a box no longer wanted) is offered
    whatever its age or due date, with its reason (2026-10-27); and so is a
    drop of a deadline the store holds with no line (`deadline`, its
    number), which has no box to name (2026-11-15: the margin's own card
    had added one, and nothing could take it away).

    A conversation may also add a task, move a deadline (`move`: its
    number, a new date) and reopen a ticked box (`undone`, among `ticked`,
    the boxes ticked lately) — only when the student asks, never from a
    plan. A box ticked, or reopened, because the student asked
    (`"asked": true`) is done at once and told, as at "do it and tell me":
    one key undoes it."""
    by_key = {c["key"]: c for c in cands}
    by_box = {b["key"]: b for b in boxes or []}
    window = {d["date"] for d in days}
    no_day, no = declined(ledger), refused(ledger)
    # Done on its own and told, or about to be: not proposed again.
    busy = {ident(x) for x in ledger["items"] if x["status"] == "told" or (x["status"] == "open" and x.get("auto"))}
    level = allowed or {}
    known = {norm(x["title"]) for x in deadlines or []} | {norm(b["title"]) for b in boxes or []}
    tags = {t.lower() for t in projects or []}
    props, seen = [], set()
    for p in reply.get("proposals") or []:
        if len(props) >= MAX_PROPOSALS:
            break
        if not isinstance(p, dict):
            continue
        kind = p.get("kind")
        if kind == "deadline" and p.get("moves") not in (None, "", 0):
            kind, p = "move", dict(p, kind="move", deadline=p.get("moves"))      # the older way of saying a move
        if kind not in KINDS or kind == "file" or level.get(kind) == "never" or (kind in ASKED_ONLY and not asked):
            continue
        key, why = str(p.get("key") or ""), str(p.get("why") or "").strip()[:300]
        item = None
        if kind == "do-date":
            date = str(p.get("date") or "")[:10]
            c = by_key.get(key)
            if not c or date not in window or (key, date) in no_day:
                continue
            if c["due"] and date >= c["due"][:10]:
                # Never on or after its own due date: a do-date on the due
                # day only repeats the date the dashboard already shows
                # (2026-11-14: six such, accepted, had planned nothing).
                continue
            item = {"kind": kind, "key": key, "date": date, "why": why, "title": c["title"], "project": c["project"]}
        elif kind == "deadline":
            title = re.sub(r"\s+", " ", str(p.get("title") or "")).strip()[:120]
            date = str(p.get("date") or "")[:10]
            try:
                when = dt.date.fromisoformat(date)
            except ValueError:
                continue
            if not title or not (today <= when <= today + dt.timedelta(days=366)) or norm(title) in known:
                continue
            # Already in the store — open, done or cancelled: a ticked box
            # (deadlines and open boxes show only what is open) must not
            # come back as a new deadline.
            if any(same_deadline(title, date, d) for d in list(deadlines or []) + list(closed or [])
                   if isinstance(d.get("due"), dt.datetime)):
                continue
            project = str(p.get("project") or "").lstrip("#")
            project = project if re.fullmatch(r"[\w/-]{1,40}", project) else ""
            item = {"kind": kind, "key": "", "title": title, "date": date, "project": project, "why": why,
                    "source": str(p.get("source") or "")[:200]}
        elif kind == "project":
            # A project the person keeps writing about but has not made:
            # never one whose tag exists, and never without a reason.
            tag = str(p.get("tag") or "").strip().lstrip("#")
            name = re.sub(r"\s+", " ", str(p.get("name") or "")).strip()[:80]
            if not re.fullmatch(r"[\w/-]{1,40}", tag) or tag.lower() in tags or not name or not why:
                continue
            item = {"kind": kind, "key": "", "title": name, "project": tag, "why": why}
        elif kind == "task":
            # A box the student asks for: its words and its course, written
            # into today's note under the course by the page. Not one that
            # is already open.
            title = re.sub(r"\s+", " ", str(p.get("title") or "")).strip().lstrip("-[] ")[:160]
            project = str(p.get("project") or "").lstrip("#")
            project = project if re.fullmatch(r"[\w/-]{1,40}", project) else ""
            if not title or norm(title) in {norm(b["title"]) for b in boxes or []}:
                continue
            item = {"kind": kind, "key": "", "title": title, "project": project, "why": why}
        elif kind == "move":
            try:
                num = int(str(p.get("deadline") or "").lstrip("#"))
            except ValueError:
                continue
            date = str(p.get("date") or "")[:10]
            try:
                when = dt.date.fromisoformat(date)
            except ValueError:
                continue
            d = next((d for d in deadlines or [] if d["id"] == num), None)
            if d is None or not (today <= when <= today + dt.timedelta(days=366)) \
                    or not isinstance(d.get("due"), dt.datetime) or d["due"].date() == when:
                continue
            b = next((b for b in boxes or [] if b.get("deadline") == num), None)
            item = {"kind": kind, "key": b["key"] if b else "", "deadline": num, "title": d["title"],
                    "project": d.get("project") or "", "date": date, "was": d["due"].strftime("%Y-%m-%d %H:%M"),
                    "why": why}
        elif kind == "undone":
            b = next((b for b in ticked or [] if b["key"] == key), None)
            if b is None:
                continue
            item = {"kind": kind, "key": key, "title": b["title"], "project": b.get("project") or "", "why": why,
                    "auto": True}
        elif kind == "drop" and not key and asked:
            try:
                num = int(str(p.get("deadline") or "").lstrip("#"))
            except ValueError:
                continue
            # One with a line is dropped through its box, as any box is.
            b = next((b for b in boxes or [] if num and b.get("deadline") == num), None)
            d = next((d for d in deadlines or [] if d["id"] == num and not d.get("linked")), None)
            if not why or (b is None and d is None):
                continue
            item = {"kind": kind, "key": b["key"], "why": why, "title": b["title"], "project": b["project"]} if b else \
                {"kind": kind, "key": "", "deadline": num, "title": d["title"], "project": d.get("project") or "", "why": why}
        else:
            b = by_box.get(key)
            if not b:
                continue
            base = {"kind": kind, "key": key, "why": why, "title": b["title"], "project": b["project"]}
            if kind == "priority":
                try:
                    lv = int(p.get("priority"))
                except (TypeError, ValueError):
                    continue
                if lv not in PRIORITY_LEVELS or lv == b["priority"]:
                    continue
                item = dict(base, priority=lv, was=b["priority"])
            elif kind == "steps":
                steps = [short_step(x) for x in (p.get("steps") or []) if str(x).strip()]
                if not steps or b["steps_under_it"]:
                    continue
                item = dict(base, steps=steps[:MAX_STEPS])
            elif kind == "drop":
                if asked:
                    if not why:
                        continue
                elif not (b["quiet"] or b["age_days"] >= STALE_DAYS) or (b["due"] and b["due"][:10] >= today.isoformat()):
                    continue
                item = base
            elif kind == "done":
                if asked and p.get("asked"):
                    item = dict(base, auto=True)      # the student asked to tick it: done, and told
                elif not why:
                    continue                          # "it looks done" must say why
                else:
                    item = base
        if item is None or ident(item) in seen or ident(item) in busy \
                or (ident(item) in no and not item.get("auto")):
            continue
        if level.get(kind) == "do" and kind not in ASK_ONLY:
            item["auto"] = True                       # done by the page, then told
        seen.add(ident(item))
        props.append(item)
    qs = []
    for q in reply.get("questions") or []:
        if not isinstance(q, dict):
            continue
        text, rec = str(q.get("question") or "").strip(), str(q.get("recommended") or "").strip()
        key = str(q.get("key") or "")
        if not text or not rec or (key and key not in by_key and key not in by_box):
            continue
        about = by_key.get(key) or by_box.get(key) or {}
        qs.append({"kind": "question", "key": key, "question": text[:300], "recommended": rec[:200],
                   "title": about.get("title", ""), "project": about.get("project", "")})
        if len(qs) >= MAX_QUESTIONS:
            break
    return props, qs


def stays(x: dict, today: dt.date) -> bool:
    """Whether an open item keeps its place against a later plan's word on
    the same box: a question or steps for STANDING_DAYS, a do-date while
    its day is still to come. The other kinds give way to a different
    proposal, as before."""
    if x.get("auto"):
        return False
    if x["kind"] in ("question", "steps"):
        try:
            return (today - dt.date.fromisoformat(str(x.get("at", ""))[:10])).days < STANDING_DAYS
        except ValueError:
            return False
    if x["kind"] == "do-date":
        return str(x.get("date", "")) >= today.isoformat()
    return False


def waiting(ledger: dict, today: dt.date) -> list[dict]:
    """What is on the student's screen and keeps its place: for the
    planner, so it asks and proposes about other boxes instead."""
    out = []
    for x in open_items(ledger):
        if stays(x, today):
            item = {"kind": x["kind"], "key": x.get("key", ""), "title": x.get("title", "")}
            if x["kind"] == "question":
                item["question"] = x.get("question", "")
            if x.get("date"):
                item["date"] = x["date"]
            out.append(item)
    return out


def record(ledger: dict, props: list[dict], qs: list[dict], at: str, budget: bool = True) -> list[dict]:
    """A new plan: what it proposes replaces what an earlier one left open
    about the same boxes (superseded) — unless that one keeps its place
    (`stays`): then the new word on it is dropped. The rest stand, within
    the course's budget (`within_budget`) unless the student asked for it
    in a conversation (`budget` False)."""
    today = dt.date.fromisoformat(at[:10])
    # A proposal the same as one still open keeps the one on screen (its row
    # and id stay put); a different one about the same thing replaces it,
    # unless the one on screen is still waiting for the student.
    standing = {ident(x): x for x in open_items(ledger) if x["kind"] != "question"}
    props = [p for p in props if not _same(standing.get(ident(p)), p)
             and not (ident(p) in standing and stays(standing[ident(p)], today))]
    # The same goes for a question asked again in the same words: one with
    # no box was recorded once a plan, and the dashboard asked it twice. And
    # a box with a question still waiting is not asked about again, in any
    # words, until the student answers or it has waited STANDING_DAYS.
    still = {norm(x.get("question", "")) for x in open_items(ledger) if x["kind"] == "question"}
    pending = {x["key"] for x in open_items(ledger) if x["kind"] == "question" and x.get("key") and stays(x, today)}
    qs = [q for q in qs if norm(q.get("question", "")) not in still and not (q.get("key") and q["key"] in pending)]
    if budget:
        props, qs = within_budget(ledger, props, qs)
    about = {ident(p) for p in props}
    asked = {q["key"] for q in qs if q["key"]}
    for x in open_items(ledger):
        if x.get("auto"):
            continue                                  # being done: the page settles it
        if (x["kind"] != "question" and ident(x) in about) or (x["kind"] == "question" and x["key"] and x["key"] in asked):
            x["status"], x["resolved"] = "superseded", at
    new = []
    for item in props + qs:
        item = dict(item, id=ledger["next"], status="open", at=at)
        ledger["next"] += ledger.get("stride", 1)   # psync: each machine in its own slot
        ledger["items"].append(item)
        new.append(item)
    return new


def within_budget(ledger: dict, props: list[dict], qs: list[dict]) -> tuple[list[dict], list[dict]]:
    """Of a plan's proposals and questions, in its order, those that fit:
    one that takes the place of an item already open about the same box
    adds nothing; any other needs room in its course (OPEN_PER_COURSE)."""
    waiting = [x for x in open_items(ledger) if not x.get("auto")]
    count: dict[str, int] = {}
    for x in waiting:
        count[x.get("project") or ""] = count.get(x.get("project") or "", 0) + 1
    standing = {ident(x) for x in waiting if x["kind"] != "question"}
    asking = {x["key"] for x in waiting if x["kind"] == "question" and x.get("key")}
    keep_p, keep_q = [], []
    for item, keep in [(p, keep_p) for p in props] + [(q, keep_q) for q in qs]:
        replaces = (item["kind"] != "question" and ident(item) in standing) or \
            (item["kind"] == "question" and item.get("key") and item["key"] in asking)
        course = item.get("project") or ""
        if not replaces:
            if count.get(course, 0) >= OPEN_PER_COURSE:
                continue
            count[course] = count.get(course, 0) + 1
        keep.append(item)
    return keep_p, keep_q


def expire(ledger: dict, at: str) -> int:
    """What has waited EXPIRE_DAYS without an answer goes quiet: expired.
    Not what the agent did on its own (told), which the page settles."""
    today = dt.date.fromisoformat(at[:10])
    n = 0
    for x in open_items(ledger):
        if x.get("auto"):
            continue
        try:
            age = (today - dt.date.fromisoformat(str(x.get("at", ""))[:10])).days
        except ValueError:
            continue
        if age >= EXPIRE_DAYS:
            x["status"], x["resolved"] = "expired", at
            n += 1
    return n


def trim_to_budget(ledger: dict, at: str) -> int:
    """What waits above the cap (OPEN_PER_COURSE a course), from before the
    cap was set or after it was lowered, goes quiet as an expiry does: the
    newest stay (2026-11-18: the re-run of the UX evaluation found 11
    waiting for one course and 9 for another, under a cap of 3). Only what
    the planning pass made: never a document to file (its own rule), what a
    conversation proposed (the student asked), or what it is doing on its
    own. Returns how many went."""
    by_course: dict[str, list[dict]] = {}
    for x in open_items(ledger):
        if x.get("auto") or x.get("from") or x["kind"] == "file":
            continue
        by_course.setdefault(x.get("project") or "", []).append(x)
    n = 0
    for xs in by_course.values():
        xs.sort(key=lambda x: (str(x.get("at") or ""), x.get("id", 0)), reverse=True)
        for x in xs[OPEN_PER_COURSE:]:
            x.update(status="expired", resolved=at, over_cap=True)
            n += 1
    return n


def _same(old: dict | None, new: dict) -> bool:
    return old is not None and all(old.get(k) == new.get(k) for k in ("date", "priority", "steps", "title"))


def settle_moot(ledger: dict, tasks: list[dict], at: str, open_ids: set[int] | None = None) -> int:
    """An open do-date whose box has a date now, is done, or is gone, no
    longer asks anything: moot. Nor does a do-date or a deadline whose day
    has passed (2026-10-23: a do-date for the 20th was still there to
    accept on the 23rd, and accepting it put a past day on the line); nor
    a drop of a deadline with no line that is no longer open (`open_ids`,
    the store's open deadlines, when known)."""
    live = {(t.get("key") or lifespan.key_of(t)): t for t in tasks}
    n = 0
    for x in open_items(ledger):
        if x["kind"] == "drop" and not x.get("key") and x.get("deadline") and open_ids is not None \
                and not x.get("auto") and x["deadline"] not in open_ids:
            x["status"], x["resolved"] = "moot", at
            n += 1
            continue
        if x["kind"] in ("do-date", "deadline") and not x.get("auto") and (x.get("date") or "9999") < at[:10]:
            x["status"], x["resolved"] = "moot", at
            n += 1
            continue
        if x["kind"] in ("question", "deadline", "file") or not x.get("key") or x.get("auto"):
            continue
        t = live.get(x["key"])
        gone = t is None or t.get("done") or t.get("cancelled")
        # The box carries just what was proposed: it was taken, not made
        # moot. The page writes the line before it records the accept, and
        # a list read in between settled accepted do-dates as moot
        # (2026-10-25); so did a person typing the proposed day themselves.
        taken = not gone and ((x["kind"] == "do-date" and t.get("when") == x.get("date"))
                              or (x["kind"] == "priority" and (t.get("priority") or 0) == x.get("priority")))
        if taken:
            x["status"], x["resolved"] = "accepted", at
            words = last_words(ledger, x)
            if words:
                x["reason"] = words
            n += 1
        elif gone or (x["kind"] == "do-date" and t.get("when")) or (x["kind"] == "steps" and t.get("details")):
            x["status"], x["resolved"] = "moot", at
            n += 1
    return n


def settle_projects(ledger: dict, tags: list[str], at: str) -> int:
    """A proposed project whose tag exists now — the person made it some
    other way — no longer asks anything: moot."""
    have = {t.lower() for t in tags}
    n = 0
    for x in open_items(ledger):
        if x["kind"] == "project" and str(x.get("project") or "").lower() in have:
            x["status"], x["resolved"] = "moot", at
            n += 1
    return n


def told(ledger: dict) -> list[dict]:
    """What the agent did on its own (do it and tell me), not yet seen."""
    return [x for x in ledger["items"] if x.get("status") == "told"]


def resolve(ledger: dict, item_id: int, status: str, at: str, answer: str = "") -> dict | None:
    for x in ledger["items"]:
        if x["id"] == item_id and x["status"] == "open":
            x["status"], x["resolved"] = status, at
            if answer:
                x["answer"] = answer
            return x
    return None


# ------------------------------------------------------------ conversations

# Talking about a proposal (2026-10-20): each box has one conversation,
# kept in the ledger beside its proposals, which every proposal about the
# box or about any box under it shares — so what was said about a do-date
# is still known when a priority is proposed for it next week. A deadline
# found in the writing has no box yet: its conversation is filed under its
# words. The planner answers in it, given the plan it made; what it may do
# there is answer, revise its proposal (checked here like any other), and
# settle it when the person's words and its own agree.
TALK_TURNS = 24              # the turns of a conversation carried into a talk
PLAN_TURNS = 6               # …and into the next plan, per box
PLAN_TALKS = 8               # the boxes whose conversation the next plan sees
SETTLE = ("accept", "decline")


def root_key(key: str, tasks: list[dict]) -> str:
    """The key of the box a box is under, all the way up in its note (its
    own, when it is under none): the box whose conversation it shares."""
    by_key = {(t.get("key") or lifespan.key_of(t)): t for t in tasks}
    t = by_key.get(key)
    if t is None:
        return key
    by_line = {(x.get("date"), x.get("line")): x for x in tasks}
    seen = set()
    while t.get("parent", -1) >= 0 and (t.get("date"), t["parent"]) in by_line and id(t) not in seen:
        seen.add(id(t))
        t = by_line[(t.get("date"), t["parent"])]
    return t.get("key") or lifespan.key_of(t)


def thread_key(x: dict, tasks: list[dict]) -> str:
    """A box's conversation; for a question about no box, the question's
    own; for a deadline with no box yet, its words'."""
    if x.get("key"):
        return root_key(x["key"], tasks)
    if x["kind"] == "question":
        return "?" + norm(x.get("question", ""))
    return "~" + norm(x.get("title", ""))


def thread(ledger: dict, key: str) -> dict:
    return (ledger.get("threads") or {}).get(key) or {"turns": []}


def add_turns(ledger: dict, key: str, title: str, turns: list[dict]) -> dict:
    th = ledger.setdefault("threads", {}).setdefault(key, {"title": title, "turns": []})
    th["title"] = title or th.get("title", "")
    th["turns"].extend(turns)
    return th


def last_words(ledger: dict, x: dict) -> str:
    """What the person last said about this proposal, or about the one it
    revised, if they talked about it: the reason kept with their answer."""
    by_id = {y["id"]: y for y in ledger["items"]}
    ids, y = set(), x
    while y is not None and y["id"] not in ids:
        ids.add(y["id"])
        y = by_id.get(y.get("revises"))
    for th in (ledger.get("threads") or {}).values():
        for turn in reversed(th.get("turns") or []):
            if turn.get("role") == "student" and turn.get("about") in ids:
                return turn.get("text", "")
    return ""


def revise(ledger: dict, old: dict, new: dict, at: str) -> dict:
    """The proposal changed in a conversation: the old one is settled as
    revised, and the new one takes its place, open, with a new id."""
    old["status"], old["resolved"] = "revised", at
    item = dict(new, id=ledger["next"], status="open", at=at, revises=old["id"])
    for k in ("prompt", "model", "payload"):
        if k in old and k not in item:
            item[k] = old[k]
    ledger["next"] += ledger.get("stride", 1)   # psync: each machine in its own slot
    old["revised_to"] = item["id"]
    ledger["items"].append(item)
    return item


def check_revision(old: dict, rev: dict | None, kept: list[dict]) -> dict | None:
    """A revision stands only if it is about the same thing — the same kind,
    the same box — and survived the plan's own checks (`kept` is what
    `validate` let through), and if it changes something."""
    if not isinstance(rev, dict) or not kept:
        return None
    new = kept[0]
    if new["kind"] != old["kind"] or (old.get("key") or "") != (new.get("key") or ""):
        return None
    if _same(old, new):
        return None
    return new


def plan_talks(ledger: dict, keys: set[str]) -> list[dict]:
    """The conversations the next plan should know of: the boxes it plans
    over, newest conversation first, each with its last few turns."""
    out = []
    for k, th in (ledger.get("threads") or {}).items():
        turns = th.get("turns") or []
        if k not in keys or not turns:
            continue
        out.append({"key": k, "title": th.get("title", ""), "last": turns[-1].get("at", ""),
                    "turns": [{"who": "you" if t["role"] == "agent" else "student", "said": t["text"][:400]}
                              for t in turns[-PLAN_TURNS:]]})
    out.sort(key=lambda x: x["last"], reverse=True)
    return out[:PLAN_TALKS]
