"""The one conversation (docs/agent.md, "One conversation"; slice 1, 2026-11-18).

The student talks to the agent in several places — a block's margin, the
day's chat, a note's, a paper's, the planner's about a proposal — and each
kept what was said in a store of its own, on one machine or in one file
both machines wrote. What each saw of the others was uneven, so the agent
forgot: said in one place, unknown in the next.

This is the one store those turns go to as well, and the one memory read
from it:

- every turn, wherever it was said, is a line in this machine's log in the
  vault, `<agentDir>/conversation/<host>.jsonl`. Only this machine writes
  that file, so the sync tool never holds two versions of it; every machine
  reads every log, merged by time (as the proposals do, psync.py);
- a turn says where it was said (`where`, and `thread`: that place's own
  conversation) and what it is about (`subjects`: a task, a block, a day,
  a note, a paper), with a name for each, so the page can show it;
- a turn's id is made from where, when, who and the words. A turn written
  twice — by the place that said it and again from that place's old store,
  or by two machines merging the same old store — is one turn;
- memory follows the subject: with a message, the agent is given what was
  said elsewhere about that message's subjects (the last PER_SUBJECT each)
  and what was said elsewhere today, whatever the place, the day or the
  machine. What a session was given already (`carried`) is not given again.

A turn marked `closed` was said about something shown for that conversation
only (a private note the student asked about): it is kept, and never
carried anywhere else.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
from pathlib import Path

FOLDER = "conversation"
PER_SUBJECT = 12      # a subject's last turns carried with a message
TODAY = 24            # today's turns elsewhere carried with a message
CARRIED = 400         # the ids a session remembers having been given
SAID = 600            # characters of a turn carried

KINDS = {"task": "the task", "block": "the block", "day": "the day", "note": "the note", "paper": "the paper"}


def turn_id(thread: str, at: str, role: str, text: str) -> str:
    return hashlib.sha1("\x1f".join((thread, at, role, text)).encode("utf-8", "replace")).hexdigest()[:16]


def turn(where: str, thread: str, role: str, text: str, at: str, subjects: list[str],
         names: dict | None = None, **more) -> dict:
    """One turn, as it is kept. `more`: `error`, `closed`, `about` (a
    proposal's number), whatever the place wants kept with it."""
    t = {"id": turn_id(thread, at, role, text), "at": at, "role": role, "text": text, "where": where,
         "thread": thread, "subjects": list(dict.fromkeys(s for s in subjects if s))}
    t["names"] = {s: str((names or {}).get(s) or "")[:120] for s in t["subjects"] if (names or {}).get(s)}
    t.update({k: v for k, v in more.items() if v})
    return t


def kind_of(subject: str) -> str:
    return subject.split(":", 1)[0]


class Log:
    def __init__(self, folder: Path, host: str):
        self.folder = Path(folder)
        self.host = host
        self.mine = self.folder / f"{host}.jsonl"

    def read(self) -> list[dict]:
        """Every machine's turns, each once, in the order they were said. A
        line cut short mid-sync is passed over."""
        rows = []
        for f in sorted(self.folder.glob("*.jsonl")) if self.folder.is_dir() else []:
            try:
                lines = f.read_text(errors="replace").splitlines()
            except OSError:
                continue
            for n, line in enumerate(lines):
                try:
                    t = json.loads(line)
                except ValueError:
                    continue
                if isinstance(t, dict) and t.get("id") and t.get("thread") and t.get("role") in ("student", "agent"):
                    rows.append((str(t.get("at") or ""), t["role"] == "agent", f.stem, n, t))
        rows.sort(key=lambda r: r[:4])
        out, seen = [], set()
        for r in rows:
            if r[4]["id"] not in seen:
                seen.add(r[4]["id"])
                out.append(dict(r[4], host=r[4].get("host") or r[2]))
        return out

    def append(self, turns: list[dict], known: set | None = None) -> list[dict]:
        """Add what is not there yet (on any machine); returns what was
        added."""
        if known is None:
            known = {t["id"] for t in self.read()}
        new = []
        for t in turns:
            if t["id"] not in known:
                known.add(t["id"])
                new.append(dict(t, host=self.host))
        if not new:
            return []
        self.folder.mkdir(parents=True, exist_ok=True)
        try:
            cut = self.mine.is_file() and not self.mine.read_bytes().endswith(b"\n") and self.mine.stat().st_size > 0
        except OSError:
            cut = False
        with open(self.mine, "a") as f:
            f.write(("\n" if cut else "") + "".join(json.dumps(t, ensure_ascii=False) + "\n" for t in new))
        return new


def name_of(turns: list[dict], subject: str) -> str:
    """A subject's name, as it was last said; else what its key says."""
    for t in reversed(turns):
        n = (t.get("names") or {}).get(subject)
        if n:
            return n
    rest = subject.split(":", 1)[-1]
    return rest.split("\t")[-1].lstrip("- ").strip() or rest


def memory(turns: list[dict], subjects: list[str], thread: str, today: str,
           carried: list[str] | None = None) -> tuple[list[tuple[str, list[dict]]], list[dict]]:
    """What a message carries from the rest of the conversation: per
    subject, its last turns said elsewhere; and today's turns elsewhere.
    Never this place's own turns (its session, or its own history, has
    them), never a closed one, never what was carried before."""
    had = set(carried or [])
    usable = [t for t in turns if t.get("thread") != thread and not t.get("closed")
              and str(t.get("text") or "").strip()]
    used: set = set()
    groups = []
    for s in dict.fromkeys(subjects):
        ts = [t for t in usable if s in (t.get("subjects") or [])][-PER_SUBJECT:]
        ts = [t for t in ts if t["id"] not in had and t["id"] not in used]
        used |= {t["id"] for t in ts}
        if ts:
            groups.append((s, ts))
    rest = [t for t in usable if str(t.get("at") or "")[:10] == today][-TODAY:]
    rest = [t for t in rest if t["id"] not in had and t["id"] not in used]
    return groups, rest


def ids(groups: list[tuple[str, list[dict]]], rest: list[dict]) -> list[str]:
    return [t["id"] for _, ts in groups for t in ts] + [t["id"] for t in rest]


def carry(carried: list[str] | None, new: list[str]) -> list[str]:
    return (list(carried or []) + [i for i in new if i not in set(carried or [])])[-CARRIED:]


def place(t: dict, turns: list[dict]) -> str:
    """Where a turn was said, in words."""
    w, th = t.get("where"), str(t.get("thread") or "")
    if w == "margin":
        s = next((x for x in t.get("subjects") or [] if kind_of(x) in ("task", "block")), "")
        return "in the margin, about “" + name_of(turns, s)[:60] + "”" if s else "in the margin"
    if w == "day":
        return "in the day's chat"
    if w == "open":
        return "said on opening the page"
    if w == "planner":
        return "with the planner"
    if w in ("note", "paper"):
        return f"in the chat about the {w} `{th.split(':', 1)[-1]}`"
    return "elsewhere"


def _when(at: str, today: str) -> str:
    try:
        d = dt.datetime.fromisoformat(at)
    except ValueError:
        return at
    return d.strftime("%H:%M") if at[:10] == today else d.strftime("%a %d %b %H:%M")


def _line(t: dict, turns: list[dict], today: str) -> str:
    text = " ".join(str(t.get("text") or "").split())
    if len(text) > SAID:
        text = text[:SAID].rstrip() + " …"
    return f"- [{_when(str(t.get('at') or ''), today)}, {place(t, turns)}] " \
           f"{'Longhand' if t['role'] == 'agent' else 'student'}: {text}"


def lines(turns: list[dict], groups: list[tuple[str, list[dict]]], rest: list[dict], today: str,
          again: bool = False) -> list[str]:
    """The payload's section. Empty when there is nothing to carry."""
    if not groups and not rest:
        return []
    out = ["", "# " + ("Since then, elsewhere in your one conversation with the student (read-only)" if again else
                       "Elsewhere in your one conversation with the student (read-only)"), "",
           "Longhand and the student have one conversation, held in several places (a block's margin, the day's "
           "chat, a note's, a paper's, about a proposal) and on more than one machine. Local code picked what was "
           "said elsewhere about what this message is about, and what was said elsewhere today. It is part of what "
           "you both know: use it, refer to it, do not make the student say it again, and do not answer it here."]
    for s, ts in groups:
        out += ["", f"## About {KINDS.get(kind_of(s), 'this')} “{name_of(turns, s)}”", ""]
        out += [_line(t, turns, today) for t in ts]
    if rest:
        out += ["", "## Elsewhere today", ""] + [_line(t, turns, today) for t in rest]
    return out


def stats(turns: list[dict]) -> dict:
    by: dict[str, int] = {}
    hosts: dict[str, int] = {}
    subjects = set()
    for t in turns:
        by[t.get("where", "")] = by.get(t.get("where", ""), 0) + 1
        hosts[t.get("host", "")] = hosts.get(t.get("host", ""), 0) + 1
        subjects |= set(t.get("subjects") or [])
    return {"turns": len(turns), "student": sum(1 for t in turns if t["role"] == "student"),
            "where": by, "hosts": hosts, "subjects": len(subjects),
            "first": turns[0]["at"] if turns else "", "last": turns[-1]["at"] if turns else ""}
