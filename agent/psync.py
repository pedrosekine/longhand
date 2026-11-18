"""The proposal ledger, the same on every machine (2026-11-18).

Each machine keeps its own ledger (`~/.local/state/longhand/proposals.json`),
read and written as before under its lock. What the agent proposed and what
the student answered travels the way the deadline store does (dsync.py):

- each machine appends what changed in its ledger, item by item, to a log of
  its own: `<vault>/<agentDir>/proposals/<host>.jsonl`. Only that machine
  writes that file, so the sync tool never holds two versions of one file;
- every machine reads every log and brings its ledger to what they say,
  each field its newest value — except an item's state, where the student's
  word (accepted, declined, answered, undone) outranks the machines' own
  (superseded, moot, expired, revised) whenever either was given: an answer
  on one machine is never undone by the other's housekeeping;
- the conversations about a box (`threads`) travel as their turns;
- what is this machine's alone stays out: a document in its Downloads
  (`file`, the folder does not sync), and what it is doing on its own
  (`auto`) until that is settled.

Ids: a machine numbers its items in a slot of its own (`slot`, from its
name: id ≡ slot mod SLOTS), so two machines planning at once never give one
id to two items. Before this, every machine numbered from 1: the first to
take part keeps its ids; one that joins later renumbers each of its items
whose id another machine's log already holds (id × SLOTS + its slot).

What this machine last agreed with the logs is kept beside its ledger
(`proposals.synced.json`), so a difference from it is a change made here.
"""
from __future__ import annotations

import hashlib
import json
import os
import tempfile
from pathlib import Path

import dsync

SLOTS = 1000
LOCAL_KINDS = {"file"}
# An item's state and what goes with it travel together, settled as one.
STATE = ("status", "resolved", "answer", "settled_by", "agreed", "was", "reason", "revised_to", "told_at", "filed")
HUMAN = {"accepted", "declined", "answered", "undone", "kept"}
OPEN = {"open"}


def slot(host: str) -> int:
    """A machine's slot: LONGHAND_SLOT, else from its name."""
    if os.environ.get("LONGHAND_SLOT", "").isdigit():
        return int(os.environ["LONGHAND_SLOT"]) % SLOTS
    return int(hashlib.sha1(host.encode()).hexdigest(), 16) % SLOTS


def shared(x: dict) -> bool:
    return x.get("kind") not in LOCAL_KINDS and not (x.get("auto") and x.get("status") == "open")


def _rank(status) -> int:
    """Whose word an item's state is: the student's over the machines'."""
    return 2 if status in HUMAN else 0 if status in OPEN or status is None else 1


def _turn_id(t: dict) -> str:
    return json.dumps([t.get("at", ""), t.get("role", ""), t.get("text", ""), t.get("about")], ensure_ascii=False)


def merge(events: list[dict]) -> tuple[dict[int, dict], dict[str, dict]]:
    """Every log's events → each item as they say (a field set to None is
    gone), and each conversation's turns."""
    plain: dict[int, dict[str, tuple]] = {}
    state: dict[int, tuple] = {}
    threads: dict[str, dict] = {}
    for ev in events:
        try:
            at, host = float(ev.get("at") or 0), str(ev.get("host") or "")
        except (TypeError, ValueError):
            continue
        if "thread" in ev:
            th = threads.setdefault(str(ev["thread"]), {"title": "", "turns": {}})
            th["title"] = ev.get("title") or th["title"]
            if isinstance(ev.get("turn"), dict):
                th["turns"][_turn_id(ev["turn"])] = ev["turn"]
            continue
        try:
            i = int(ev["id"])
        except (KeyError, TypeError, ValueError):
            continue
        sets = ev.get("set") or {}
        group = {k: sets[k] for k in STATE if k in sets}
        if group:
            key = (_rank(group.get("status")), at, host)
            if i not in state or key > state[i][0]:
                state[i] = (key, group)
        for k, v in sets.items():
            if k in STATE:
                continue
            key = (at, host)
            cur = plain.setdefault(i, {}).get(k)
            if cur is None or key > cur[0]:
                plain[i][k] = (key, v)
    items = {}
    for i in set(plain) | set(state):
        rec = {k: v for k, (_, v) in plain.get(i, {}).items()}
        rec.update(state[i][1] if i in state else {})
        items[i] = rec
    out_threads = {k: {"title": v["title"], "turns": sorted(v["turns"].values(), key=lambda t: str(t.get("at", "")))}
                   for k, v in threads.items()}
    return items, out_threads


def _whole(rec: dict) -> bool:
    return all(rec.get(k) is not None for k in ("kind", "status"))


def _fields(x: dict) -> dict:
    return {k: v for k, v in x.items() if k != "id"}


class Logs:
    def __init__(self, folder: Path, state: Path, host: str | None = None):
        self.folder = folder
        self.host = host or dsync.host_name()
        self.slot = slot(self.host)
        self.base_path = state / "proposals.synced.json"
        try:
            b = json.loads(self.base_path.read_text())
            self.base = {int(k): v for k, v in b["items"].items()}
            self.base_turns = set(b.get("turns") or [])
            self.seeded = True
        except (OSError, ValueError, KeyError, AttributeError, TypeError):
            self.base, self.base_turns, self.seeded = {}, set(), False

    def events(self, mine: bool = True) -> list[dict]:
        out = []
        for f in sorted(self.folder.glob("*.jsonl")) if self.folder.is_dir() else []:
            if not mine and f.stem == self.host:
                continue
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
        return out

    def _append(self, evs: list[dict]) -> None:
        if not evs:
            return
        self.folder.mkdir(parents=True, exist_ok=True)
        with open(self.folder / f"{self.host}.jsonl", "a") as f:
            for ev in evs:
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")

    # ------------------------------------------------------------- joining
    def renumber(self, ledger: dict) -> dict[int, int]:
        """The first time this machine takes part: each of its items whose id
        another machine's log already holds for another item gets one of its
        own slot. Returns old → new."""
        theirs, _ = merge(self.events(mine=False))
        moved = {}
        for x in ledger["items"]:
            other = theirs.get(x["id"])
            if other is None or (other.get("at") == x.get("at") and other.get("kind") == x.get("kind")
                                 and other.get("key") == x.get("key")):
                continue                          # not theirs, or the same item
            moved[x["id"]] = x["id"] * SLOTS + self.slot
        if not moved:
            return moved
        for x in ledger["items"]:
            x["id"] = moved.get(x["id"], x["id"])
            for k in ("revises", "revised_to"):
                if x.get(k) in moved:
                    x[k] = moved[x[k]]
        for th in (ledger.get("threads") or {}).values():
            for t in th.get("turns") or []:
                if t.get("about") in moved:
                    t["about"] = moved[t["about"]]
        return moved

    # ------------------------------------------------------------- syncing
    def sync(self, ledger: dict, now: float) -> int:
        """What changed here into this machine's log; what the logs say into
        the ledger (changed in place). Returns how many items or turns of the
        ledger changed."""
        changed = 0
        if not self.seeded and self.renumber(ledger):
            changed += 1
        at = now if self.seeded else 0.0          # a first look is a seed, weaker than any change
        evs = []
        for x in ledger["items"]:
            if not shared(x):
                continue
            was = self.base.get(x["id"])
            rec = _fields(x)
            if was is None:
                sets = dict(rec)
            else:
                sets = {k: v for k, v in rec.items() if was.get(k) != v}
                sets.update({k: None for k in was if k not in rec})
                if any(k in STATE for k in sets):  # the state travels whole
                    sets.update({k: rec.get(k) for k in STATE})
            if sets:
                evs.append({"at": at, "host": self.host, "id": x["id"], "set": sets})
        for key, th in (ledger.get("threads") or {}).items():
            for t in th.get("turns") or []:
                tid = _turn_id(t)
                if tid not in self.base_turns:
                    evs.append({"at": at, "host": self.host, "thread": key, "title": th.get("title", ""), "turn": t})
                    self.base_turns.add(tid)
        self._append(evs)

        items, threads = merge(self.events())
        local = {x["id"]: x for x in ledger["items"]}
        for i, want in sorted(items.items()):
            rec = {k: v for k, v in want.items() if v is not None}
            here = local.get(i)
            if here is not None and not shared(here):
                continue                          # this machine's own, never another's
            if here is None:
                if not _whole(rec):
                    continue
                ledger["items"].append(dict(rec, id=i))
                changed += 1
            elif _fields(here) != rec:
                here.clear()
                here.update(dict(rec, id=i))
                changed += 1
            self.base[i] = rec
        led_threads = ledger.setdefault("threads", {})
        for key, th in threads.items():
            mine = led_threads.setdefault(key, {"title": th["title"], "turns": []})
            have = {_turn_id(t) for t in mine.get("turns") or []}
            new = [t for t in th["turns"] if _turn_id(t) not in have]
            if new:
                mine["turns"] = sorted((mine.get("turns") or []) + new, key=lambda t: str(t.get("at", "")))
                mine["title"] = mine.get("title") or th["title"]
                changed += 1
            self.base_turns |= {_turn_id(t) for t in th["turns"]}
        # This machine's next ids, in its own slot, above every id known.
        top = max([x["id"] for x in ledger["items"]] + [0])
        ledger["stride"] = SLOTS
        ledger["next"] = (top // SLOTS + 1) * SLOTS + self.slot
        self.seeded = True
        return changed

    def save(self) -> None:
        self.base_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".proposals.synced.", dir=self.base_path.parent)
        with os.fdopen(fd, "w") as f:
            json.dump({"items": {str(k): v for k, v in sorted(self.base.items())},
                       "turns": sorted(self.base_turns)}, f, ensure_ascii=False)
        os.replace(tmp, self.base_path)
