"""The deadline store, the same on every machine (2026-11-17).

Each machine keeps its own store (`~/.local/state/longhand/deadlines.tsv`,
written by `pomo`), and the notes sync between machines. A deadline's line
carries its tick and its date, but not its grade, whether it was hidden,
when it was really done, or a deadline that has no line yet. So the store
travels too, through the vault the notes already sync with:

- each machine appends what changed in its store, field by field, to a log
  of its own: `<vault>/<agentDir>/deadlines/<host>.jsonl`. Only that machine
  writes that file, so the sync tool never has two versions of one file;
- every machine reads every log, and each field of each deadline takes its
  newest value; a machine's store is brought to that (`pomo deadline put`),
  so the stores agree whichever machine wrote last;
- the first time a machine takes part it writes down its whole store as a
  seed, weaker than any change: two seeds that disagree are settled the same
  way on every machine (done over open, the earliest time it was done, a
  grade over none), never by which machine happened to look first.

What this machine last agreed with the logs is kept beside its store
(`deadlines.synced.json`), so a difference from it is a change made here —
by the page, the popup, `pomo`, or the check itself.

Pure functions and one class; the check (`cli/longhand-check`) runs it.
"""
from __future__ import annotations

import json
import os
import re
import socket
import tempfile
from pathlib import Path

FIELDS = ("due", "title", "status", "done_at", "grade", "project", "link")
STATUS_RANK = {"open": 0, "hidden": 1, "cancelled": 2, "done": 3}


def host_name() -> str:
    """This machine's name for its log: LONGHAND_HOST, else its host name."""
    name = os.environ.get("LONGHAND_HOST") or socket.gethostname() or "here"
    return re.sub(r"[^\w.-]", "_", name)


def record_of(d: dict) -> dict:
    """A store row (`pomo deadline list --json`) as the logs carry it."""
    return {"due": int(d.get("due") or 0), "title": d.get("title") or "", "status": d.get("status") or "open",
            "done_at": int(d.get("done_at") or 0), "grade": d.get("grade") or "", "project": d.get("project") or "",
            "link": d.get("link") or ""}


def _rank(field: str, value) -> tuple:
    """How two values written at the same moment are settled (in practice
    two seeds): the same answer on every machine."""
    if field == "status":
        return (STATUS_RANK.get(value, 0), "")
    if field == "done_at":
        return (1, -int(value)) if value else (0, 0)       # the earliest real time
    if field == "grade":
        return (1 if value else 0, str(value))
    if field == "removed":
        return (1 if value else 0, "")
    return (0, json.dumps(value, ensure_ascii=False))


def merge(events: list[dict]) -> dict[int, dict]:
    """Every log's events → each deadline as the newest value of each field
    says; `removed` true for one removed outright."""
    best: dict[int, dict[str, tuple]] = {}
    for ev in events:
        try:
            i, at, host = int(ev["id"]), float(ev.get("at") or 0), str(ev.get("host") or "")
        except (KeyError, TypeError, ValueError):
            continue
        for field, value in (ev.get("set") or {}).items():
            if field not in FIELDS and field != "removed":
                continue
            key = (at, _rank(field, value), host)
            cur = best.setdefault(i, {}).get(field)
            if cur is None or key > cur[0]:
                best[i][field] = (key, value)
    return {i: {f: v for f, (_, v) in fields.items()} for i, fields in best.items()}


def _same(a: dict, b: dict) -> bool:
    """Two births of one number describe the same deadline: the same words,
    or the same line."""
    if (a.get("link") or "") and a.get("link") == b.get("link"):
        return True
    return str(a.get("title") or "").strip().casefold() == str(b.get("title") or "").strip().casefold()


def clashes(events: list[dict]) -> list[dict]:
    """One number given to two different deadlines by two machines, each
    before it had read the other's log (2026-11-24: a third machine's first
    deadline took #1, and the logs folded it into the other machines' #1,
    done and graded). A birth is a machine first writing a deadline down
    whole (`removed: false`, a seed or a new one). The deadline born first
    keeps the number; each other one is to move to a new number.

    Returns [{id, keep: {hosts, since}, move: {hosts, born, after, rec}}]:
    `rec` is the moving deadline as its own machines' events say, and
    `after` the time its machines first changed it (events of the keeping
    machines from then on may carry its values, folded in)."""
    births: dict[int, list[tuple[float, str, dict]]] = {}
    moved: dict[int, list[dict]] = {}
    for ev in events:
        try:
            i, at, host = int(ev["id"]), float(ev.get("at") or 0), str(ev.get("host") or "")
        except (KeyError, TypeError, ValueError):
            continue
        s = ev.get("set") or {}
        if isinstance(s.get("moved"), dict):
            moved.setdefault(i, []).append(s["moved"])
        if s.get("removed") is False and whole(s):
            births.setdefault(i, []).append((at, host, s))
    out = []
    for i, bs in births.items():
        groups: list[list[tuple[float, str, dict]]] = []
        for b in sorted(bs, key=lambda b: (b[0], b[1])):
            for g in groups:
                if _same(g[0][2], b[2]):
                    g.append(b)
                    break
            else:
                groups.append([b])
        groups = [g for g in groups if not any(_same(g[0][2], m) for m in moved.get(i, []))]
        if len(groups) < 2:
            continue
        keep = groups[0]
        keep_hosts = {b[1] for b in keep}
        for g in groups[1:]:
            hosts = {b[1] for b in g} - keep_hosts
            if not hosts:
                continue
            own = [ev for ev in events if str(ev.get("host") or "") in hosts and _int(ev.get("id")) == i]
            rec = merge(own).get(i, {})
            later = [float(ev.get("at") or 0) for ev in own if float(ev.get("at") or 0) > 0]
            out.append({"id": i, "keep": {"hosts": sorted(keep_hosts), "since": keep[0][0]},
                        "move": {"hosts": sorted(hosts), "born": g[0][0], "after": min(later) if later else float("inf"),
                                 "rec": {f: rec[f] for f in FIELDS if f in rec}}})
    return out


def kept(events: list[dict], clash: dict) -> dict:
    """The deadline that keeps the number, as its own machines said it before
    the other one's values could reach them."""
    hosts = set(clash["keep"]["hosts"])
    own = [ev for ev in events if str(ev.get("host") or "") in hosts and _int(ev.get("id")) == clash["id"]
           and float(ev.get("at") or 0) < clash["move"]["after"]]
    rec = merge(own).get(clash["id"], {})
    return {f: rec[f] for f in FIELDS if f in rec}


def _int(v) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return -1


def whole(rec: dict) -> bool:
    return all(f in rec for f in FIELDS)


class Logs:
    def __init__(self, folder: Path, state: Path, host: str | None = None, dry: bool = False):
        self.folder = folder
        self.host = host or host_name()
        self.base_path = state / "deadlines.synced.json"
        self.dry = dry
        self.pending: list[dict] = []
        try:
            self.base = {int(k): v for k, v in json.loads(self.base_path.read_text()).items()}
            self.seeded = True
        except (OSError, ValueError, AttributeError):
            self.base, self.seeded = {}, False

    # ---------------------------------------------------------------- reading
    def events(self) -> list[dict]:
        out = []
        for f in sorted(self.folder.glob("*.jsonl")) if self.folder.is_dir() else []:
            try:
                lines = f.read_text(errors="replace").splitlines()
            except OSError:
                continue
            for line in lines:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue                      # a line cut short mid-sync
                if isinstance(ev, dict):
                    out.append(ev)
        return out + self.pending

    # ---------------------------------------------------------------- writing
    def note_changes(self, items: list[dict], now: float) -> int:
        """What changed here since this machine last agreed with the logs,
        field by field, into its own log. The first time: the whole store,
        as a seed (at 0, weaker than any change). Returns how many events."""
        at = now if self.seeded else 0.0
        here = {int(d["id"]): record_of(d) for d in items}
        evs = []
        for i, rec in here.items():
            was = self.base.get(i)
            if was is None or was.get("removed"):
                changed = dict(rec, removed=False)
            else:
                changed = {f: rec[f] for f in FIELDS if was.get(f) != rec[f]}
            if changed:
                evs.append({"at": at, "host": self.host, "id": i, "set": changed})
        for i, was in self.base.items():
            if i not in here and not was.get("removed"):
                evs.append({"at": at, "host": self.host, "id": i, "set": {"removed": True}})
        self._append(evs)
        for i, rec in here.items():
            self.base[i] = rec
        for i in list(self.base):
            if i not in here:
                self.base[i] = {"removed": True}
        self.seeded = True
        return len(evs)

    def _append(self, evs: list[dict]) -> None:
        if not evs:
            return
        self.pending += evs
        if self.dry:
            return
        self.folder.mkdir(parents=True, exist_ok=True)
        with open(self.folder / f"{self.host}.jsonl", "a") as f:
            for ev in evs:
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")
        self.pending = []

    def save(self) -> None:
        if self.dry:
            return
        self.base_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".deadlines.synced.", dir=self.base_path.parent)
        with os.fdopen(fd, "w") as f:
            json.dump({str(k): v for k, v in sorted(self.base.items())}, f, ensure_ascii=False)
        os.replace(tmp, self.base_path)

    # --------------------------------------------------------------- applying
    def plan(self, items: list[dict]) -> list[tuple[int, dict | None]]:
        """What this store must become, as the logs say: (id, record) to put,
        (id, None) to remove. Only where it differs from the store now."""
        here = {int(d["id"]): record_of(d) for d in items}
        out = []
        for i, want in sorted(merge(self.events()).items()):
            if want.get("removed"):
                if i in here:
                    out.append((i, None))
                continue
            rec = {f: want[f] for f in FIELDS if f in want}
            if not whole(rec):
                continue                          # never seen whole: nothing to make of it
            if here.get(i) != rec:
                out.append((i, rec))
        return out

    def agreed(self, i: int, rec: dict | None) -> None:
        """A change taken from the logs: this machine agrees with it, so it
        is not written down again as this machine's own."""
        self.base[i] = rec if rec is not None else {"removed": True}

    def top(self) -> int:
        return max([int(ev.get("id") or 0) for ev in self.events()] or [0])
