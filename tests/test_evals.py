"""The plan eval's rules for the actions that are not do-dates
(agent/evals.py): a stated deadline with its date and source words, done,
drop and steps matched on the box, priorities counted — and the answer the
judge reads, with every kind rendered.

Run: python3 tests/test_evals.py
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import evals  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def box(key, title, age=40, steps=0, priority=0, due=""):
    return {"key": key, "title": title, "project": "intsem", "age_days": age, "quiet": False,
            "priority": priority, "steps_under_it": steps, "due": due}


DATA = {
    "today": "2026-10-18",
    "fortnight": [{"date": "2026-10-19", "weekday": "Mon", "weekend": False, "on": [], "free_hours": 5.0,
                   "due": [], "planned": 0}],
    "candidates": [],
    "deadlines": [],
    "open_boxes": [box("b1", "this is a checkbox"), box("b2", "Initial paper", due="2026-11-30 23:59"),
                   box("b3", "call the dentist"), box("b4", "ISAB follow-up"), box("b5", "final paper")],
    "you_may": ["deadline", "do-date", "done", "drop", "priority", "steps"],
}
PAYLOAD = ("# Plan\n\n```json\n" + json.dumps(DATA) + "\n```\n\n## 2026-10-16\n\n"
           "The extended abstract is due   on the 6th\nof November. Called the dentist, all fine.\n")
RULES = {"min_dates": 0, "deadline_for": [{"title": "abstract", "date": "2026-11-06"}],
         "done_for": ["dentist"], "drop_for": ["checkbox"], "no_drop_for": ["ISAB"],
         "steps_for": ["initial paper"], "no_steps_for": ["final paper"], "max_priorities": 1}


def run(proposals):
    case = {"job": "plan", "payload": PAYLOAD, "rules": RULES}
    rules, kept = evals.check_plan(case, {"proposals": proposals, "questions": []})
    return {r["check"]: r["pass"] for r in rules}, kept


def main() -> int:
    good = [
        {"kind": "deadline", "title": "Extended abstract", "date": "2026-11-06", "project": "intsem",
         "source": "The extended abstract is due on the 6th of November", "why": "stated in the seminar notes"},
        {"kind": "done", "key": "b3", "why": "“Called the dentist, all fine.”"},
        {"kind": "drop", "key": "b1", "why": "a test line from trying the page"},
        {"kind": "steps", "key": "b2", "steps": ["Reread the project notes", "Outline the sections"], "why": "big"},
        {"kind": "priority", "key": "b2", "priority": 2, "why": "first graded paper"},
    ]
    got, kept = run(good)
    check(all(got.values()) and len(got) == 9, f"a good answer passes every per-kind rule ({len(got)} checks)")

    got, _ = run([dict(good[0], date="2026-11-07")])
    check(not got["deadline /abstract/ on 2026-11-06, with words from the notes"], "a deadline on the wrong date fails")
    got, _ = run([dict(good[0], source="the abstract is due early November")])
    check(not got["deadline /abstract/ on 2026-11-06, with words from the notes"],
          "…and one whose source words are not in the notes (spacing and case aside, they must be)")
    got, _ = run([dict(good[0], source="")])
    check(not got["deadline /abstract/ on 2026-11-06, with words from the notes"], "…and one with no source")

    got, _ = run([{"kind": "drop", "key": "b4", "why": "old"}, {"kind": "steps", "key": "b5", "steps": ["x"], "why": "y"}])
    check(not got["no drop for /ISAB/"] and not got["no steps for /final paper/"], "dropping a real box, or steps under the wrong one, fails")
    check(not got["drop for /checkbox/"] and not got["done for /dentist/"] and not got["steps for /initial paper/"],
          "…and what was wanted but not proposed fails too")

    got, _ = run([{"kind": "priority", "key": k, "priority": 2, "why": "w"} for k in ("b2", "b4")])
    check(not got["at most 1 priorities"], "two priorities where one is allowed fails")

    text = evals.render_plan(kept)
    check("deadline 2026-11-06 · Extended abstract #intsem — source: “The extended abstract is due on the 6th of November”" in text
          and "done? · call the dentist" in text and "drop · this is a checkbox" in text
          and "steps · Initial paper: 1) Reread the project notes; 2) Outline the sections" in text
          and "priority 0 → 2 · Initial paper" in text, "the judge reads every kind with what makes it that kind")
    check(evals.render_plan({"proposals": [], "questions": []}) == "(nothing)", "…and (nothing) for an empty plan")

    old = {"job": "plan", "payload": PAYLOAD, "rules": {"min_dates": 0, "ask_about": [], "date_for": [], "no_date_for": []}}
    rules, _ = evals.check_plan(old, {"proposals": good, "questions": []})
    check(len(rules) == 2, "a case without the new rules checks what it checked before")
    new = evals.new_case("plan", PAYLOAD, "x-plan.md")["rules"]
    check({"deadline_for", "done_for", "drop_for", "no_drop_for", "steps_for", "no_steps_for", "max_priorities"} <= set(new),
          "a new plan case lists the per-kind rules to fill in")

    # A deadline the store has closed is refused here as it is live
    # (2026-10-20): from the payload's closed_deadlines, or the case's own
    # `closed` for payloads written before that.
    ticked = [{"kind": "deadline", "title": "Proposal v1 reviewed", "date": "2026-12-18", "source": "Proposal v1",
               "why": "w"}]
    closed = [{"title": "Proposal of version 1, read by supervisor and 2 fellow students",
               "due": "2026-12-18 23:59", "status": "done"}]
    with_closed = PAYLOAD.replace(json.dumps(DATA), json.dumps(dict(DATA, closed_deadlines=closed)))
    _, kept = evals.check_plan({"job": "plan", "payload": with_closed, "rules": {}}, {"proposals": ticked, "questions": []})
    check(kept["proposals"] == [], "a ticked deadline proposed again is refused, from the payload's closed_deadlines")
    _, kept = evals.check_plan({"job": "plan", "payload": PAYLOAD, "rules": {}, "closed": closed},
                               {"proposals": ticked, "questions": []})
    check(kept["proposals"] == [], "…or from the case's own `closed`, for older payloads")
    _, kept = evals.check_plan({"job": "plan", "payload": PAYLOAD, "rules": {}}, {"proposals": ticked, "questions": []})
    check(len(kept["proposals"]) == 1, "…and kept when nothing says it was closed")

    # A talk (2026-10-23): answered in its own shape, never with a plan.
    talk = dict(evals.new_case("talk", "# The proposal the student wants to talk about\n\n```json\n"
                                       '{"kind": "question", "id": 4}\n```\n', "x-talk-4.md"),
                rules={"must_not_match": [r"\bI (have|'ve) (moved|changed)"], "must_match_any": [r"\bT\b"], "settle": ""})
    check(evals.talk_kind(talk["payload"]) == "question", "a talk case knows the kind of proposal it is about")
    rules = evals.check_talk(talk, {"reply": "", "plan": True})
    check(len(rules) == 1 and not rules[0]["pass"] and rules[0]["why"] == "a plan", "a plan for an answer fails, and says so")
    rules = evals.check_talk(talk, {"reply": "Press T on its row to move it.", "settle": None})
    check(all(r["pass"] for r in rules) and len(rules) == 4, f"a reply naming the key, settling nothing, passes ({rules})")
    rules = evals.check_talk(talk, {"reply": "I have moved it to today.", "settle": "accept"})
    check(sum(not r["pass"] for r in rules) == 3, "claiming the move, without the key, and settling, fails all three")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
