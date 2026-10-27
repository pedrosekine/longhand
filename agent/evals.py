"""The eval set: how the agent's behaviour is checked before its
instructions or its model change (docs/agent.md, the improvement loop,
2026-10-18).

A case is a real run's payload — kept in the student's vault
(`agents/longhand/evals/cases/`), never in the public repo, because it holds
their notes — and what a good answer must do there:

- `rules`, checked by code: for the margin, patterns the reply must or must
  not contain, whether silence is acceptable; for the day's conversation,
  the same, and whether it asks to search or read rather than answer, with
  which words, which proposals must survive plan.py's checks and which must
  not, and for a brief how many lines; for a plan, how many do-dates
  must survive plan.py's checks, which questions must be asked, which boxes
  must or must not get a date — and for the other kinds, which deadline
  (with its date and source words), which boxes are asked about as done,
  dropped or given steps, and how few priorities.
- `criteria`, in plain words, graded by a judge model (its own agent, every
  tool denied): "engages with the substance, from something specific in the
  student's context".

A run gives each case to the candidate prompts and models, checks the
rules, asks the judge, and keeps the result — with each prompt's version
and the model — in `evals/results/`, which is the history the weekly review
reads and the gate before a change consults.
"""
from __future__ import annotations

import datetime as dt
import json
import re
from pathlib import Path

import plan as planlib


def cases_dir(agent_dir: Path) -> Path:
    return agent_dir / "evals" / "cases"


def results_dir(agent_dir: Path) -> Path:
    return agent_dir / "evals" / "results"


def load_cases(agent_dir: Path, only: list[str] | None = None) -> list[dict]:
    out = []
    folder = cases_dir(agent_dir)
    for f in sorted(folder.glob("*.json")) if folder.is_dir() else []:
        try:
            c = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        c.setdefault("id", f.stem)
        if only and c["id"] not in only:
            continue
        out.append(c)
    return out


def new_case(job: str, payload: str, source: str, note: str = "", answer: str = "") -> dict:
    """A case to fill in: the payload as it was, the answer that prompted it
    (if any — a reply rated not helpful, a declined proposal), and empty
    rules and criteria for the person to write."""
    if job == "day":
        brief = payload.startswith("# Brief")
        rules = {"must_not_match": [], "must_match_any": [], "silence_ok": False,
                 "search": None, "search_words": [], "read": None,
                 "propose": [], "no_propose": [], "max_proposals": planlib.MAX_PROPOSALS,
                 "brief_lines": [3, 6] if brief else None}
        return {"job": job, "created": dt.date.today().isoformat(), "source": source, "note": note,
                "answer_then": answer, "rules": rules, "criteria": [], "payload": payload}
    if job == "talk":
        # A talk with the planner about one proposal (2026-10-23): it must
        # answer in the talk's shape, never with a plan; `settle` is what it
        # should agree to ("accept", "decline", "" for nothing), or "any".
        rules = {"must_not_match": [], "must_match_any": [], "settle": "any"}
        return {"job": job, "created": dt.date.today().isoformat(), "source": source, "note": note,
                "answer_then": answer, "rules": rules, "criteria": [], "payload": payload}
    rules = ({"must_not_match": [], "must_match_any": [], "silence_ok": False} if job == "margin" else
             {"min_dates": 0, "max_questions": planlib.MAX_QUESTIONS, "ask_about": [], "date_for": [], "no_date_for": [],
              "deadline_for": [], "done_for": [], "drop_for": [], "no_drop_for": [], "steps_for": [], "no_steps_for": [],
              "max_priorities": planlib.MAX_PROPOSALS})
    return {"job": job, "created": dt.date.today().isoformat(), "source": source, "note": note,
            "answer_then": answer, "rules": rules, "criteria": [], "payload": payload}


# ------------------------------------------------------------------ checks

def _plan_data(payload: str) -> dict:
    m = re.search(r"```json\n(.*?)\n```", payload, re.S)
    return json.loads(m.group(1)) if m else {}


def check_margin(case: dict, reply: dict) -> list[dict]:
    r = case.get("rules") or {}
    text = reply.get("reply") or ""
    out = []
    if not text:
        out.append({"check": "says something", "pass": bool(r.get("silence_ok")), "why": "silent"})
        if not r.get("silence_ok"):
            return out
    for pat in r.get("must_not_match") or []:
        hit = re.search(pat, text, re.I)
        out.append({"check": f"never /{pat}/", "pass": not hit, "why": hit.group(0) if hit else ""})
    anyof = r.get("must_match_any") or []
    if anyof:
        hit = next((p for p in anyof if re.search(p, text, re.I)), None)
        out.append({"check": "names one of: " + ", ".join(anyof), "pass": bool(hit), "why": hit or "none found"})
    return out


def talk_kind(payload: str) -> str:
    """The kind of the proposal a talk's payload is about, from its own block."""
    m = re.search(r"# The proposal the student wants to talk about\n\n```json\n(.*?)\n```", payload, re.S)
    try:
        return str(json.loads(m.group(1)).get("kind") or "") if m else ""
    except ValueError:
        return ""


def check_talk(case: dict, reply: dict) -> list[dict]:
    """A talk answers: in its own shape, never empty, and agreeing only to
    what the case says it should."""
    r = case.get("rules") or {}
    out = [{"check": "answers the student, not with a plan", "pass": bool(reply.get("reply")) and not reply.get("plan"),
            "why": "a plan" if reply.get("plan") else "" if reply.get("reply") else "empty"}]
    if not out[0]["pass"]:
        return out
    out += check_margin(dict(case, rules=dict(r, silence_ok=False)), reply)
    want = r.get("settle", "any")
    if want != "any":
        got = reply.get("settle") or ""
        out.append({"check": f"settles: {want or 'nothing'}", "pass": got == want, "why": got or "nothing"})
    return out


def check_plan(case: dict, reply: dict) -> tuple[list[dict], dict]:
    """The rules, after plan.py's own checks (what survives them is what the
    student would see)."""
    r = case.get("rules") or {}
    data = _plan_data(case["payload"])
    today = dt.date.fromisoformat(data.get("today") or dt.date.today().isoformat())
    may = data.get("you_may")
    allowed = {k: ("ask" if may is None or k in may else "never") for k in planlib.KINDS}
    # The store's deadlines, as plan.py checks them: the open ones, and the
    # closed ones (from the payload since 2026-10-20, else the case's own
    # `closed`), so a ticked box proposed again is refused here as it is live.
    def store(rows):
        out = []
        for x in rows or []:
            try:
                out.append(dict(x, due=dt.datetime.strptime(str(x["due"])[:16], "%Y-%m-%d %H:%M")))
            except (KeyError, ValueError):
                continue
        return out
    props, qs = planlib.validate(reply, data.get("candidates") or [], data.get("fortnight") or [],
                                 {"next": 1, "items": []}, today, data.get("open_boxes") or [],
                                 store(data.get("deadlines")), allowed,
                                 store(data.get("closed_deadlines") or case.get("closed")))
    dates = [p for p in props if p["kind"] == "do-date"]
    out = [{"check": f"at least {r.get('min_dates', 0)} do-dates kept", "pass": len(dates) >= r.get("min_dates", 0),
            "why": f"{len(dates)} kept of {sum(1 for p in reply.get('proposals') or [] if p.get('kind') == 'do-date')}"},
           {"check": f"at most {r.get('max_questions', planlib.MAX_QUESTIONS)} questions",
            "pass": len(qs) <= r.get("max_questions", planlib.MAX_QUESTIONS), "why": f"{len(qs)}"}]
    asked = " | ".join(q["question"] for q in qs)
    for pat in r.get("ask_about") or []:
        out.append({"check": f"asks about /{pat}/", "pass": bool(re.search(pat, asked, re.I)), "why": asked[:160]})
    dated = " | ".join(p["title"] for p in dates)
    for pat in r.get("date_for") or []:
        out.append({"check": f"dates /{pat}/", "pass": bool(re.search(pat, dated, re.I)), "why": dated[:160]})
    for pat in r.get("no_date_for") or []:
        out.append({"check": f"no date for /{pat}/", "pass": not re.search(pat, dated, re.I), "why": dated[:160]})
    out += _check_kinds(r, props, case["payload"])
    return out, {"proposals": props, "questions": qs}


def _day_data(payload: str) -> dict:
    """What the day's payload gave it to propose about — the last time it
    was given (a later message carries it again only when it changed)."""
    found = re.findall(r"# What you may propose[^\n]*\n\n[^\n]*\n\n```json\n(.*?)\n```", payload, re.S)
    try:
        return json.loads(found[-1]) if found else {}
    except ValueError:
        return {}


def _matches(spec: str, props: list[dict]) -> bool:
    """`kind` or `kind:pattern` (the pattern on the box's title)."""
    kind, _, pat = spec.partition(":")
    return any(p["kind"] == kind and (not pat or re.search(pat, p.get("title") or "", re.I)) for p in props)


def check_day(case: dict, reply: dict) -> tuple[list[dict], str]:
    """The day's conversation: what it said, whether it asked to search or
    read instead of answering, and what it proposed — after plan.py's own
    checks, against the data the payload gave it. A brief: its lines.
    Returns the checks and the answer as the judge reads it."""
    r = case.get("rules") or {}
    text = reply.get("reply") or ""
    asked = [str(q.get("words") or "") for q in reply.get("search") or []]
    reads = [str(q.get("file") or q.get("document") or "") for q in reply.get("read") or []]
    data = _day_data(case["payload"])
    props = []
    if data and reply.get("proposals"):
        days = data.get("fortnight") or []
        today = dt.date.fromisoformat(days[0]["date"]) if days else dt.date.today()
        may = data.get("you_may")
        allowed = {k: ("ask" if may is None or k in may else "never") for k in planlib.KINDS}
        props, _ = planlib.validate({"proposals": reply["proposals"], "questions": []}, data.get("candidates") or [],
                                    days, {"next": 1, "items": []}, today, data.get("open_boxes") or [], [], allowed,
                                    asked=True)
    out = []
    fetching = bool(asked or reads)
    if r.get("search") is not None:
        out.append({"check": "asks to search" if r["search"] else "answers without searching",
                    "pass": bool(asked) == bool(r["search"]), "why": " | ".join(asked) or "no search"})
    for pat in r.get("search_words") or []:
        out.append({"check": f"searches for /{pat}/", "pass": any(re.search(pat, w, re.I) for w in asked),
                    "why": " | ".join(asked)[:160] or "no search"})
    if r.get("read") is not None:
        out.append({"check": "asks to read" if r["read"] else "reads nothing", "pass": bool(reads) == bool(r["read"]),
                    "why": " | ".join(reads) or "nothing"})
    if not fetching:
        if not text:
            out.append({"check": "says something", "pass": bool(r.get("silence_ok")), "why": "silent"})
        else:
            for pat in r.get("must_not_match") or []:
                hit = re.search(pat, text, re.I)
                out.append({"check": f"never /{pat}/", "pass": not hit, "why": hit.group(0) if hit else ""})
            anyof = r.get("must_match_any") or []
            if anyof:
                hit = next((p for p in anyof if re.search(p, text, re.I)), None)
                out.append({"check": "names one of: " + ", ".join(anyof), "pass": bool(hit), "why": hit or "none found"})
    kept = " | ".join(f"{p['kind']}: {p.get('title', '')}" for p in props)
    for spec in r.get("propose") or []:
        out.append({"check": f"proposes {spec}", "pass": _matches(spec, props), "why": kept or "nothing kept"})
    for spec in r.get("no_propose") or []:
        out.append({"check": f"does not propose {spec}", "pass": not _matches(spec, props), "why": kept or "nothing kept"})
    if len(props) > r.get("max_proposals", planlib.MAX_PROPOSALS):
        out.append({"check": f"at most {r['max_proposals']} proposals", "pass": False, "why": f"{len(props)}"})
    if r.get("brief_lines"):
        lo, hi = r["brief_lines"]
        lines = [l for l in text.split("\n") if l.strip()]
        out.append({"check": f"a brief of {lo}–{hi} lines, each `- `",
                    "pass": lo <= len(lines) <= hi and all(l.lstrip().startswith("- ") for l in lines),
                    "why": f"{len(lines)} lines" + ("" if all(l.lstrip().startswith("- ") for l in lines) else ", not all `- `")})
    answer = text or "(silence)"
    if fetching:
        answer = "(asks first: " + " | ".join([f"search “{w}”" for w in asked] + [f"read {x}" for x in reads]) + ")"
    if props:
        answer += "\n\nCards (what it proposed, as the student sees them after the checks):\n" + "\n".join(
            f"◇ {p['kind']}: {p.get('title', '')} {p.get('date') or p.get('priority') or ' · '.join(p.get('steps') or [])} — {p.get('why', '')}"
            for p in props)
    return out, answer


def _squash(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip().lower()


def _check_kinds(r: dict, props: list[dict], payload: str) -> list[dict]:
    """The rules for the actions that are not do-dates. A deadline must
    carry the date the writing states and `source` words that are in the
    payload; done, drop and steps are matched on the box's title; priorities
    are counted (sparingly)."""
    out = []
    of = {k: [p for p in props if p["kind"] == k] for k in ("deadline", "done", "drop", "steps", "priority")}
    text = _squash(payload)
    found = " | ".join(f"{p['date']} {p['title']} «{p['source']}»" for p in of["deadline"])
    for want in r.get("deadline_for") or []:
        hit = [p for p in of["deadline"] if re.search(want["title"], p["title"], re.I)
               and (not want.get("date") or p["date"] == want["date"])]
        quoted = [p for p in hit if p["source"].strip() and _squash(p["source"]) in text]
        out.append({"check": f"deadline /{want['title']}/ on {want.get('date') or 'its date'}, with words from the notes",
                    "pass": bool(quoted), "why": found[:200] or "no deadline kept"})
    for rule, kind, want in (("done_for", "done", True), ("drop_for", "drop", True), ("no_drop_for", "drop", False),
                             ("steps_for", "steps", True), ("no_steps_for", "steps", False)):
        titles = " | ".join(p["title"] for p in of[kind])
        for pat in r.get(rule) or []:
            hit = bool(re.search(pat, titles, re.I))
            out.append({"check": f"{'' if want else 'no '}{kind} for /{pat}/", "pass": hit == want, "why": titles[:160]})
    if "max_priorities" in r:
        n = len(of["priority"])
        out.append({"check": f"at most {r['max_priorities']} priorities", "pass": n <= r["max_priorities"],
                    "why": " | ".join(f"{p['priority']} {p['title']}" for p in of["priority"])[:160] or "0"})
    return out


def render_plan(kept: dict) -> str:
    """A plan's kept answer as the judge reads it: each kind with what makes
    it that kind (a deadline's source words, the steps themselves)."""
    lines = []
    for p in kept["proposals"]:
        k = p["kind"]
        if k == "do-date":
            lines.append(f"do {p['date']} · {p['title']} — {p['why']}")
        elif k == "deadline":
            tag = f" #{p['project']}" if p.get("project") else ""
            lines.append(f"deadline {p['date']} · {p['title']}{tag} — source: “{p['source']}” — {p['why']}")
        elif k == "priority":
            lines.append(f"priority {p['was']} → {p['priority']} · {p['title']} — {p['why']}")
        elif k == "steps":
            steps = "; ".join(f"{i + 1}) {s}" for i, s in enumerate(p["steps"]))
            lines.append(f"steps · {p['title']}: {steps} — {p['why']}")
        elif k == "drop":
            lines.append(f"drop · {p['title']} — {p['why']}")
        elif k == "done":
            lines.append(f"done? · {p['title']} — {p['why']}")
    lines += [f"? {q['question']} (recommended: {q['recommended']})" for q in kept["questions"]]
    return "\n".join(lines) or "(nothing)"


def judge_payload(case: dict, answer: str) -> str:
    """What the judge is given: the job, the criteria, the answer, and the
    payload the answer was made from (so 'grounded in the context' can be
    judged against the context)."""
    crit = "\n".join(f"{i + 1}. {c}" for i, c in enumerate(case.get("criteria") or []))
    limits = (f"\n\n# Limits\nA plan makes at most {planlib.MAX_PROPOSALS} proposals of every kind together "
              f"(do-dates, deadlines, priorities, steps, drops, done-questions) and asks at most "
              f"{planlib.MAX_QUESTIONS} questions; with more candidates than that, the rest wait for a later plan."
              if case["job"] == "plan" else "")
    return (f"# Job\n{case['job']}{limits}\n\n# Criteria\n{crit}\n\n# The answer to grade\n\n{answer}\n\n"
            f"# The payload the answer was made from\n\n{case['payload']}\n")


def parse_judge(text: str, n: int) -> list[dict]:
    m = None
    for m in re.finditer(r"```(?:json)?\s*\n(.*?)\n```", text, re.S):
        pass
    for c in ([m.group(1)] if m else []) + [text.strip()]:
        try:
            obj = json.loads(c)
        except json.JSONDecodeError:
            continue
        res = obj.get("results") if isinstance(obj, dict) else None
        if isinstance(res, list):
            out = []
            for i in range(n):
                x = res[i] if i < len(res) and isinstance(res[i], dict) else {}
                out.append({"pass": bool(x.get("pass")), "why": str(x.get("why") or "")[:300]})
            return out
    return [{"pass": False, "why": "the judge gave no usable verdict"} for _ in range(n)]


# ------------------------------------------------------------------ history

def save_result(agent_dir: Path, result: dict) -> Path:
    folder = results_dir(agent_dir)
    folder.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    f = folder / f"{stamp}.json"
    f.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
    return f


def history(agent_dir: Path) -> list[dict]:
    out = []
    folder = results_dir(agent_dir)
    for f in sorted(folder.glob("*.json")) if folder.is_dir() else []:
        try:
            r = json.loads(f.read_text())
            r["file"] = f.name
            out.append(r)
        except (OSError, ValueError):
            continue
    return out


def passed(agent_dir: Path, job: str, prompt: str, model: str) -> bool | None:
    """Has this job's prompt version, on this model, passed every case of
    its job in a run? None when it was never run; False when its last run
    did not pass."""
    last = None
    for r in history(agent_dir):
        for j in r.get("jobs") or []:
            if j["job"] == job and j["prompt"] == prompt and j["model"] == model:
                last = j
    if last is None:
        return None
    return last["cases"] > 0 and last["passed"] == last["cases"]
