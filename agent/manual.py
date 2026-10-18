"""The agent's manual: what Longhand can do, and how (2026-10-18, plan
item "the agent's cheap tiers": self-knowledge, static and auditable).

`agent/manual.md` is written by hand; its `{key:<id>}` are filled in here
with the student's own keys — Shortcuts.js with keys.json applied, and
Hyprland's as they are now (tools/keys_guide.py reads both) — so "press
Ctrl+D" is true for this student even after they moved a key. A run whose
block asks how to do something in Longhand carries the manual whole; every
other run about a block lists it, and the agent can ask to read it (or
search it) like a course document.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANUAL = Path(__file__).resolve().parent / "manual.md"
NAME = "Longhand's manual"

# A block that asks how to do something in the page. Generous on purpose:
# carrying the manual when it was not needed costs a few thousand tokens;
# missing it costs a wrong answer (and the agent can still ask to read it).
HOWTO = re.compile(
    r"\b(how (do|can|to|should) i|how does|is there a (key|way|shortcut)|which key|what key|shortcut|keybind|"
    r"where (is|do|can)|can (longhand|the page|the agent|you)|longhand|the dashboard|the sidebar|the margin|"
    r"settings|do-?date|bind|unbind|reschedul|private)\b", re.I)


def asks_how(text: str) -> bool:
    return "?" in text and bool(HOWTO.search(text))


def keys(config_home: Path | None = None) -> dict[str, list[str]]:
    """Every action's keys as the student has them: id -> ["Ctrl+D", …];
    Hyprland's under "sys:<id>". Empty when they cannot be read (no node)."""
    sys.path.insert(0, str(ROOT / "tools"))
    sys.path.insert(0, str(ROOT / "plugin-page"))
    try:
        import hyprkeys
        import keys_guide
        cfg = config_home or Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
        path = cfg / "longhand" / "keys.json"
        mine = json.loads(path.read_text()) if path.exists() else {}
        # node needs none of the XDG folders, and a version manager's shim
        # can fail when they point somewhere else (a test's state folder).
        d = keys_guide.read(mine, env={k: v for k, v in os.environ.items() if not k.startswith("XDG_")})
    except Exception:  # noqa: BLE001 — a manual without keys still answers, and says where they are
        return {}
    out = {a["id"]: a["keys"] for a in d["actions"]}
    for (aid, *_), h in zip(hyprkeys.ACTIONS, d["hypr"]):
        out["sys:" + aid] = h["keys"]
    return out


def render(text: str, k: dict[str, list[str]]) -> str:
    def one(m):
        ks = k.get(m.group(1))
        if not ks:
            return "(its key: see the keys list)" if k else "(a key: see the keys list, Ctrl+/)"
        return " or ".join(f"`` {x} ``" if "`" in x else f"`{x}`" for x in ks[:2])
    text = re.sub(r"<!--.*?-->\n*", "", text, flags=re.S)
    return re.sub(r"\{key:([\w:]+)\}", one, text)


def text(config_home: Path | None = None) -> str:
    return render(MANUAL.read_text(), keys(config_home))


def pages(config_home: Path | None = None) -> list[str]:
    """The manual cut at its sections, each one "page" — what a search of it
    returns, by section."""
    body = text(config_home)
    parts = re.split(r"\n(?=## )", body)
    return [p.strip() for p in parts if p.strip().startswith("## ")]
