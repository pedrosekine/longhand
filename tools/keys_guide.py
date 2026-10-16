#!/usr/bin/env python3
"""keys_guide — docs/keys.md, written from the keys themselves.

The page's keys live in one list, plugin-page/Shortcuts.js; Hyprland's six
in plugin-page/hyprkeys.py. The keys sheet in the page (Ctrl+/) draws the
first; this draws both as markdown, so the written guide cannot drift from
what the keys do either. A key added or moved in Shortcuts.js reaches the
guide by running this again, and tests/test_keys_guide.py fails until it
is run.

  python3 tools/keys_guide.py            # rewrite docs/keys.md
  python3 tools/keys_guide.py --check    # exit 1 if docs/keys.md is stale
  python3 tools/keys_guide.py --mine     # the guide with your keys.json, on stdout

Needs node on PATH (as tests/test_blocks.py does) to read Shortcuts.js.
"""
import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHORTCUTS = ROOT / "plugin-page" / "Shortcuts.js"
GUIDE = ROOT / "docs" / "keys.md"
sys.path.insert(0, str(ROOT / "plugin-page"))
import hyprkeys  # noqa: E402

# Shortcuts.js is a QML library; plain JS once its pragma is gone.
JS = """
const fs = require('fs');
const src = fs.readFileSync(process.argv[1], 'utf8').replace('.pragma library', '');
const m = {};
new Function('m', src + `
  m.groups = groups; m.places = places; m.actions = actions; m.fixed = fixed;
  m.load = load; m.keysOf = keysOf; m.show = show; m.canonical = canonical; m.isChanged = isChanged;`)(m);
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
if (input.mine) m.load(input.mine);
process.stdout.write(JSON.stringify({
  groups: m.groups,
  places: m.places,
  actions: m.actions.map(a => ({ id: a.id, group: a.group, does: a.does, places: a.places,
                                  keys: m.keysOf(a.id).map(m.show), changed: m.isChanged(a.id) })),
  fixed: m.fixed.filter(f => f.show.length > 0).map(f => ({ group: f.group, does: f.does, keys: f.show.map(m.show) })),
  hypr: input.hypr.map(h => ({ does: h.does, keys: h.keys.map(k => m.show(m.canonical(k))), changed: h.changed })),
}));
"""


def read(mine=None):
    if mine is None:
        hypr = [{"does": does, "keys": [hyprkeys.from_hypr(key)], "changed": False} for _id, does, _cmd, key in hyprkeys.ACTIONS]
    else:
        # Yours: as Hyprland has them now (longhand.lua once the page keeps
        # them, bindings.lua before). Only read, never written.
        hypr = [{"does": a["does"], "keys": a["keys"], "changed": a["keys"] != a["own"]} for a in hyprkeys.state()["actions"]]
    out = subprocess.run(["node", "-e", JS, str(SHORTCUTS)], input=json.dumps({"mine": mine, "hypr": hypr}),
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def code(k):
    # A key with a backtick in it needs the longer fence.
    return f"`` {k} ``" if "`" in k else f"`{k}`"


def render(d, mine=False):
    lines = [
        "# Keys",
        "",
        "<!-- Written by tools/keys_guide.py from plugin-page/Shortcuts.js and",
        "     plugin-page/hyprkeys.py. Do not edit: change the keys there and run it. -->",
        "",
        ("Every key the page answers to, with **your** keys from `keys.json` (moved ones marked •)."
         if mine else
         "Every key the page answers to, as it starts. Any of them can be moved in the page: "
         "`Ctrl+/` (or **keys** in the header) opens the same list, Enter on a row and the new key "
         "moves it. The keys you move are kept in `~/.config/longhand/keys.json`; "
         "`python3 tools/keys_guide.py --mine` prints this guide with them."),
        "",
        "Where a row has two keys, either works: the second is usually the one another app "
        "taught (Notion, Todoist, vim) or one a laptop reaches without Fn.",
    ]
    for g in d["groups"]:
        acts = [a for a in d["actions"] if a["group"] == g["id"]]
        fixed = [f for f in d["fixed"] if f["group"] == g["id"]]
        hypr = d["hypr"] if g["id"] == "system" else []
        if not (acts or fixed or hypr):
            continue
        lines += ["", f"## {g['title']}", "", "| | Keys | Works |", "|---|---|---|"]
        for a in acts:
            keys = " · ".join(code(k) for k in a["keys"]) or "no key"
            mark = " •" if mine and a["changed"] else ""
            lines.append(f"| {a['does']}{mark} | {keys} | {', '.join(d['places'][p] for p in a['places'])} |")
        for f in fixed:
            lines.append(f"| {f['does']} | {' · '.join(code(k) for k in f['keys'])} | |")
        for h in hypr:
            mark = " •" if mine and h["changed"] else ""
            keys = " · ".join(code(k) for k in h["keys"]) or "no key"
            lines.append(f"| {h['does']}{mark} | {keys} | everywhere (Hyprland) |")
    return "\n".join(lines) + "\n"


def main(argv):
    if "--mine" in argv:
        cfg = pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")
        path = cfg / "longhand" / "keys.json"
        mine = json.loads(path.read_text()) if path.exists() else {}
        sys.stdout.write(render(read(mine), mine=True))
        return 0
    text = render(read())
    if "--check" in argv:
        if GUIDE.exists() and GUIDE.read_text() == text:
            return 0
        print(f"{GUIDE.relative_to(ROOT)} is out of date: run python3 tools/keys_guide.py", file=sys.stderr)
        return 1
    GUIDE.write_text(text)
    print(f"wrote {GUIDE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
