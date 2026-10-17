"""The eval set: how the agent's behaviour is checked before its
instructions or its model change (docs/agent.md, the improvement loop,
2026-10-18).

A case is a real run's payload — kept in the student's vault
(`agents/longhand/evals/cases/`), never in the public repo, because it holds
their notes — and what a good answer must do there:

- `rules`, checked by code: for the margin, patterns the reply must or must
  not contain, whether silence is acceptable; for a plan, how many do-dates
  must survive plan.py's checks, which questions must be asked, which boxes
  must or must not get a date.
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
    rules = ({"must_not_match": [], "must_match_any": [], "silence_ok": False} if job == "margin" else
             {"min_dates": 0, "max_questions": planlib.MAX_QUESTIONS, "ask_about": [], "date_for": [], "no_date_for": []})
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


def check_plan(case: dict, reply: dict) -> tuple[list[dict], dict]:
    """The rules, after plan.py's own checks (what survives them is what the
    student would see)."""
    r = case.get("rules") or {}
    data = _plan_data(case["payload"])
    today = dt.date.fromisoformat(data.get("today") or dt.date.today().isoformat())
    props, qs = planlib.validate(reply, data.get("candidates") or [], data.get("fortnight") or [],
                                 {"next": 1, "items": []}, today)
    out = [{"check": f"at least {r.get('min_dates', 0)} do-dates kept", "pass": len(props) >= r.get("min_dates", 0),
            "why": f"{len(props)} kept of {len(reply.get('proposals') or [])}"},
           {"check": f"at most {r.get('max_questions', planlib.MAX_QUESTIONS)} questions",
            "pass": len(qs) <= r.get("max_questions", planlib.MAX_QUESTIONS), "why": f"{len(qs)}"}]
    asked = " | ".join(q["question"] for q in qs)
    for pat in r.get("ask_about") or []:
        out.append({"check": f"asks about /{pat}/", "pass": bool(re.search(pat, asked, re.I)), "why": asked[:160]})
    dated = " | ".join(p["title"] for p in props)
    for pat in r.get("date_for") or []:
        out.append({"check": f"dates /{pat}/", "pass": bool(re.search(pat, dated, re.I)), "why": dated[:160]})
    for pat in r.get("no_date_for") or []:
        out.append({"check": f"no date for /{pat}/", "pass": not re.search(pat, dated, re.I), "why": dated[:160]})
    return out, {"proposals": props, "questions": qs}


def judge_payload(case: dict, answer: str) -> str:
    """What the judge is given: the job, the criteria, the answer, and the
    payload the answer was made from (so 'grounded in the context' can be
    judged against the context)."""
    crit = "\n".join(f"{i + 1}. {c}" for i, c in enumerate(case.get("criteria") or []))
    return (f"# Job\n{case['job']}\n\n# Criteria\n{crit}\n\n# The answer to grade\n\n{answer}\n\n"
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
