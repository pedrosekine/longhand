"""How long an open box is carried before it goes quiet (2026-10-15/17).

A box written and never touched again stops being carried into the
dashboard: 7 days of silence for a note box, 30 for a task, none for a
deadline, which is judged by its date. The rule is Fizzy's entropy, with one
change that makes it fit here: **the decay is in the view, never in the
file.** A daily note is history, so nothing is rewritten; a quiet box stays
where it was written, findable through its project, and comes back the
moment it is touched.

Silence is reset by any touch:
- the words written or changed (a box the clock has not met before is new
  as of the last time it looked, or of its note, whichever is later);
- the same words written again in a later note;
- a do-date (⏳) — the clock runs from that day, not before;
- kept on purpose from the dashboard (`keep`).

`shelve` is "not now" by hand: the box goes where quiet ones go, until it
is touched again. Nothing goes without first being shown as about to: a
box counts down through the last quarter of its life, and on the clock's
first day every box already past its life starts in that quarter instead
(as Fizzy touches every card when its setting changes).

The clock lives in the layer (`silence.json` beside the deadline store),
keyed by a box's project and words, never in the note.
"""
import datetime as dt
import json
import math
import os
from pathlib import Path

import task as tasklib

LIFE = {"note": 7, "task": 30}


def quarter(life: int) -> int:
    return math.ceil(life / 4)


def key_of(box: dict) -> str:
    return (box.get("project") or "") + "\t" + tasklib.identity("- " + box.get("text", ""))


def _day(s: str) -> dt.date | None:
    try:
        return dt.date.fromisoformat(s[:10])
    except (TypeError, ValueError):
        return None


def load(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or not isinstance(data.get("boxes"), dict):
        return None
    return data


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
    os.replace(tmp, path)


def apply(rows: list[dict], path: Path, today: dt.date | None = None) -> list[dict]:
    """Annotate open boxes with their clock, and bring the clock up to date.

    Each row gains `key`, `life` (days, 0 for none), `left` (days of life
    left), `warn` (in its last quarter) and `away` ("" while carried,
    "quiet" when its silence ran out, "shelved" when put aside by hand).
    """
    today = today or dt.date.today()
    data = load(path)
    first = data is None
    last = (_day(data.get("checked", "")) if data else None) or today
    boxes = data["boxes"] if data else {}

    # The latest any note names it, and the longest life any copy has.
    newest: dict[str, dt.date] = {}
    life_of: dict[str, int] = {}
    for r in rows:
        # A box done (today: it is still listed) has no silence to count.
        life = 0 if r.get("done") else LIFE.get(r.get("kind", ""), 0)
        r["key"] = key_of(r)
        r["life"] = life
        if not life:
            continue
        written = today - dt.timedelta(days=r.get("age", 0))
        k = r["key"]
        newest[k] = max(newest.get(k, written), written)
        life_of[k] = max(life_of.get(k, 0), life)

    kept: dict[str, dict] = {}
    for k, written in newest.items():
        rec = dict(boxes.get(k) or {})
        touched = _day(rec.get("touched", ""))
        if touched is None:
            touched = written if first else max(written, min(last, today))
            if first:
                life = life_of[k]
                touched = max(touched, today - dt.timedelta(days=life - quarter(life)))
        touched = max(touched, written)
        rec["touched"] = touched.isoformat()
        kept[k] = rec

    for r in rows:
        r["left"], r["warn"], r["away"] = 0, False, ""
        if not r["life"]:
            continue
        rec = kept[r["key"]]
        touched = _day(rec["touched"])
        shelved = _day(rec.get("shelved", ""))
        when = _day(r.get("when", ""))
        r["left"] = r["life"] - (today - max(touched, when or touched)).days
        if shelved and shelved >= touched:
            r["away"] = "shelved"
        elif r["left"] <= 0:
            r["away"] = "quiet"
        else:
            r["warn"] = r["left"] <= quarter(r["life"])

    new = {"checked": today.isoformat(), "boxes": kept}
    if new != data:
        save(path, new)
    return rows


def touch(path: Path, key: str, how: str, today: dt.date | None = None) -> bool:
    """`keep`: its clock starts again today, and it comes back if it was
    away. `shelve`: not now — it goes where quiet boxes go."""
    today = today or dt.date.today()
    data = load(path) or {"checked": today.isoformat(), "boxes": {}}
    rec = data["boxes"].setdefault(key, {})
    if how == "keep":
        rec["touched"] = today.isoformat()
        rec.pop("shelved", None)
    elif how == "shelve":
        rec.setdefault("touched", today.isoformat())
        rec["shelved"] = today.isoformat()
    else:
        return False
    save(path, data)
    return True
