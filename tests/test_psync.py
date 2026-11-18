"""The proposal ledger, the same on every machine (agent/psync.py).

Run: python3 tests/test_psync.py

Two machines, two ledgers, one vault folder between them:
- the first to take part keeps its ids; one joining later renumbers each item
  whose id the other's log holds, into its own slot, and what refers to it
- after a round each way, both ledgers hold the same shared items and turns
- a document in a machine's Downloads (`file`), and what it is doing on its
  own (`auto`, open), stay that machine's
- the student's word outranks the machines': an answer on one machine is not
  undone by the other's later "expired"
- two machines planning at once never give one id to two items
- a log line cut short mid-sync is skipped
"""
import json
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import plan  # noqa: E402
import psync  # noqa: E402

FAILS = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        FAILS.append(what)


def item(i, kind="do-date", key="k", at="2026-11-01T09:00:00", status="open", **kw):
    return dict({"id": i, "kind": kind, "key": key, "title": key, "project": "thesis", "status": status, "at": at}, **kw)


def shared_view(led):
    return {x["id"]: {k: v for k, v in x.items()} for x in led["items"] if psync.shared(x)}


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="psync-test-"))
    try:
        folder = tmp / "vault" / "agents" / "longhand" / "proposals"
        A, B = "alpha", "beta"
        check(psync.slot(A) != psync.slot(B), "two machines, two slots")

        a = {"next": 4, "items": [item(1, key="essay"), item(2, kind="question", key="paper", question="Which?"),
                                  item(3, kind="file", key="", src="/home/a/Downloads/x.pdf")],
             "threads": {"thesis\t- paper": {"title": "paper", "turns": [
                 {"role": "student", "text": "the first one", "at": "2026-11-01T10:00:00", "about": 2}]}}}
        b = {"next": 3, "items": [item(1, key="poster", at="2026-11-02T09:00:00"),
                                  item(2, kind="steps", key="diary", at="2026-11-02T09:00:00", revises=1)],
             "threads": {"\t- poster": {"title": "poster", "turns": [
                 {"role": "student", "text": "after the paper", "at": "2026-11-02T10:00:00", "about": 1}]}}}
        la = psync.Logs(folder, tmp / "a", host=A)
        lb = psync.Logs(folder, tmp / "b", host=B)

        la.sync(a, 100.0)
        la.save()
        check([x["id"] for x in a["items"]] == [1, 2, 3], "the first to take part keeps its ids")
        lb.sync(b, 101.0)
        lb.save()
        bids = sorted(x["id"] for x in b["items"] if x["key"] in ("poster", "diary"))
        check(bids == [1000 + psync.slot(B), 2000 + psync.slot(B)],
              f"one joining later renumbers its items into its own slot ({bids})")
        diary = next(x for x in b["items"] if x["key"] == "diary")
        check(diary["revises"] == 1000 + psync.slot(B), "…and what refers to them follows")
        check(b["threads"]["\t- poster"]["turns"][0]["about"] == 1000 + psync.slot(B), "…a conversation's turns too")

        la.sync(a, 102.0)
        la.save()
        check(shared_view(a) == shared_view(b) and len(shared_view(a)) == 4,
              f"after a round each way, the same shared items on both ({sorted(shared_view(a))} / {sorted(shared_view(b))})")
        check(set(a["threads"]) == set(b["threads"]) and all(
            len(a["threads"][k]["turns"]) == len(b["threads"][k]["turns"]) == 1 for k in a["threads"]),
            "…and the same conversations")
        check(not any(x["kind"] == "file" for x in b["items"]), "a document in one machine's Downloads stays its own")

        # Planning at once, offline: two new items, never one id.
        na = plan.record(a, [item(0, key="review", at="")], [], "2026-11-03T09:00:00", budget=False)[0]
        nb = plan.record(b, [item(0, key="slides", at="")], [], "2026-11-03T09:00:00", budget=False)[0]
        check(na["id"] != nb["id"] and na["id"] % psync.SLOTS == psync.slot(A) and nb["id"] % psync.SLOTS == psync.slot(B),
              f"two machines planning at once give two ids ({na['id']}, {nb['id']})")

        # The student answers on beta; alpha, not yet told, expires it later.
        q = next(x for x in b["items"] if x["kind"] == "question")
        plan.resolve(b, q["id"], "answered", "2026-11-20T09:00:00", answer="the first")
        lb.sync(b, 200.0)
        lb.save()
        next(x for x in a["items"] if x["id"] == q["id"]).update(status="expired", resolved="2026-11-21T09:00:00")
        la.sync(a, 300.0)
        la.save()
        lb.sync(b, 301.0)
        lb.save()
        qa = next(x for x in a["items"] if x["id"] == q["id"])
        qb = next(x for x in b["items"] if x["id"] == q["id"])
        check(qa["status"] == qb["status"] == "answered" and qa.get("answer") == "the first",
              f"the student's answer outranks the other machine's later 'expired' ({qa['status']}, {qb['status']})")
        check(any(x["id"] == nb["id"] for x in a["items"]) and any(x["id"] == na["id"] for x in b["items"]),
              "what each planned reaches the other")

        # What a machine is doing on its own stays its own until settled.
        auto = plan.record(a, [item(0, key="auto-one", at="", auto=True)], [], "2026-11-04T09:00:00", budget=False)[0]
        la.sync(a, 400.0)
        la.save()
        lb.sync(b, 401.0)
        check(not any(x["id"] == auto["id"] for x in b["items"]), "an item being done on its own is not shared while open")
        auto.update(status="told", told_at="2026-11-04T09:01:00")
        la.sync(a, 402.0)
        lb.sync(b, 403.0)
        check(any(x["id"] == auto["id"] and x["status"] == "told" for x in b["items"]), "…and is, once settled")

        # A line cut short mid-sync.
        with open(folder / f"{A}.jsonl", "a") as f:
            f.write('{"at": 500, "host": "alpha", "id": 1, "set": {"status": "acc')
        before = shared_view(b)
        lb.sync(b, 501.0)
        check(shared_view(b) == before, "a log line cut short is skipped")
    finally:
        shutil.rmtree(tmp)
    print("FAIL" if FAILS else "PASS")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
