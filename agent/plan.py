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

import re

import lifespan

DAYS = 14                    # the fortnight planned over
WORKDAY = (9 * 60, 18 * 60)  # minutes: the hours a free day is counted in
MAX_PROPOSALS = 5            # of every kind together, a run
MAX_QUESTIONS = 2
MAX_CANDIDATES = 12
MAX_BOXES = 40               # the open boxes the planner sees for the other actions
MAX_STEPS = 5
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
}
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


def open_boxes(tasks: list[dict], deadlines: list[dict], today: dt.date) -> list[dict]:
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
                    "age_days": t.get("age", 0), "quiet": bool(t.get("away")), "kind": t.get("kind") or "task"})
    out.sort(key=lambda b: (b["due"] or "9999", -b["age_days"]))
    return out[:MAX_BOXES]


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
    ("Proposal of version 1 …" → "Proposal v1") must not bring it back."""
    if norm(title) == norm(d["title"]):
        return True
    a, b = _words(title), _words(d["title"])
    if not a or not b:
        return False
    common = a & b
    if d.get("due") and d["due"].date().isoformat() == date and common:
        return True
    return len(common) >= max(1, round(0.6 * min(len(a), len(b))))


def ident(x: dict) -> tuple[str, str]:
    """What one proposal is about: its kind and its box, or, for a deadline
    (which has no box yet), its words; for a project, its tag."""
    if x["kind"] == "project":
        return (x["kind"], str(x.get("project") or "").lower())
    return (x["kind"], x.get("key") or norm(x.get("title", "")))


def refused(ledger: dict) -> set[tuple[str, str]]:
    """Every proposal the person said no to, or undid: never proposed again
    (a do-date only on that day; another day may be proposed)."""
    return {ident(x) for x in ledger["items"]
            if x["status"] in ("declined", "undone") and x["kind"] not in ("do-date", "question")}


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
             projects: list[str] | None = None) -> tuple[list[dict], list[dict]]:
    """What the model said, kept only where it holds: every kind checked
    against what it was shown, against what the person already refused, and
    against what the person allows ("never" drops it). At most
    MAX_PROPOSALS of all kinds, in the model's order, and MAX_QUESTIONS."""
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
        if kind not in KINDS or kind == "file" or level.get(kind) == "never":
            continue
        key, why = str(p.get("key") or ""), str(p.get("why") or "").strip()[:300]
        item = None
        if kind == "do-date":
            date = str(p.get("date") or "")[:10]
            c = by_key.get(key)
            if not c or date not in window or (key, date) in no_day:
                continue
            if c["due"] and date > c["due"][:10]:
                continue                                  # never after its own due date
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
                steps = [re.sub(r"\s+", " ", str(x)).strip()[:100] for x in (p.get("steps") or []) if str(x).strip()]
                if not steps or b["steps_under_it"]:
                    continue
                item = dict(base, steps=steps[:MAX_STEPS])
            elif kind == "drop":
                if not (b["quiet"] or b["age_days"] >= STALE_DAYS) or (b["due"] and b["due"][:10] >= today.isoformat()):
                    continue
                item = base
            elif kind == "done":
                if not why:
                    continue                          # "it looks done" must say why
                item = base
        if item is None or ident(item) in no or ident(item) in seen or ident(item) in busy:
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


def record(ledger: dict, props: list[dict], qs: list[dict], at: str) -> list[dict]:
    """A new plan: what it proposes replaces what an earlier one left open
    about the same boxes (superseded); the rest of the earlier ones stand."""
    # A proposal the same as one still open keeps the one on screen (its row
    # and id stay put); a different one about the same thing replaces it.
    standing = {ident(x): x for x in open_items(ledger) if x["kind"] != "question"}
    props = [p for p in props if not _same(standing.get(ident(p)), p)]
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
        ledger["next"] += 1
        ledger["items"].append(item)
        new.append(item)
    return new


def _same(old: dict | None, new: dict) -> bool:
    return old is not None and all(old.get(k) == new.get(k) for k in ("date", "priority", "steps", "title"))


def settle_moot(ledger: dict, tasks: list[dict], at: str) -> int:
    """An open do-date whose box has a date now, is done, or is gone, no
    longer asks anything: moot. Nor does a do-date or a deadline whose day
    has passed (2026-10-23: a do-date for the 20th was still there to
    accept on the 23rd, and accepting it put a past day on the line)."""
    live = {(t.get("key") or lifespan.key_of(t)): t for t in tasks}
    n = 0
    for x in open_items(ledger):
        if x["kind"] in ("do-date", "deadline") and not x.get("auto") and (x.get("date") or "9999") < at[:10]:
            x["status"], x["resolved"] = "moot", at
            n += 1
            continue
        if x["kind"] in ("question", "deadline", "file") or not x.get("key") or x.get("auto"):
            continue
        t = live.get(x["key"])
        gone = t is None or t.get("done") or t.get("cancelled")
        if gone or (x["kind"] == "do-date" and t.get("when")) \
                or (x["kind"] == "priority" and (t.get("priority") or 0) == x.get("priority")) \
                or (x["kind"] == "steps" and t.get("details")):
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
    ledger["next"] += 1
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
