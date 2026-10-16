#!/usr/bin/env python3
"""hyprkeys — the six Hyprland keys that reach the page, kept by the page.

The keys sheet lists every key the page answers to. Six of them are not
the page's but Hyprland's: they open the page, the timer and the deadlines
from anywhere. This moves those six, and only those, without the page ever
editing a line the student wrote:

- the keys live in ~/.config/hypr/longhand.lua, a file this writes whole
  and owns (the student may still edit its keys by hand; they are read
  back from it);
- bindings.lua gets one line, once, when the student agrees in the sheet
  (`adopt`): it loads longhand.lua last, through Omarchy's require_optional,
  so deleting the file is never an error. The same step comments out the
  student's own lines for those six commands (a backup is made first, the
  way Omarchy does: bindings.lua.bak.<epoch>), so no key fires twice;
- every write is followed by `hyprctl reload config-only`; if that brings a
  config error that was not there before, both files are put back and
  Hyprland reloaded again.

The file is Lua, so nothing the student types is ever written as text.
The commands and descriptions are the constants below, and a key is built
from a fixed set of modifiers and key names, so a bad one is refused
before anything is written. A key must hold Super: one without could take
a key an app needs (Ctrl+C, everywhere).

Keys travel to and from the page the way Shortcuts.js writes them,
"Alt+Super+=" (Ctrl, Alt, Shift, Super, then the key). Every command
prints the state as JSON on stdout:

  hyprkeys.py state
  hyprkeys.py migrate      (student.lua → longhand.lua; every command does it first)
  hyprkeys.py adopt
  hyprkeys.py set <id> [--add] [--take] <key>...

`set` with no key leaves the action without one. A key some other
Hyprland bind has is not taken unless --take is given; the answer then
says whose it is, for the sheet to ask. A key taken is unbound in
longhand.lua with a note of what it did, and given back (the line dropped)
once none of the six is on it any more.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import time

# id, what the sheet says (also the bind's description, which is how a bind
# is recognised in `hyprctl binds`), the command, its own key.
ACTIONS = [
    ("page", "Page (today's note)", "omarchy-shell shell toggle longhand.page '{}'", "SUPER + ALT + equal"),
    ("alongside", "Page alongside", "omarchy-shell shell summon longhand.page '{\"shape\":\"alongside\"}'", "SUPER + ALT + backslash"),
    ("deadlines", "Deadlines popup", "omarchy-shell longhand.deadline toggle", "SUPER + ALT + D"),
    ("pomoPopup", "Pomo popup", "omarchy-shell longhand.pomo toggle", "SUPER + ALT + O"),
    ("pomoToggle", "Pomo toggle", "pomo toggle", "SUPER + ALT + P"),
    ("pomoSkip", "Pomo skip", "pomo skip", "SUPER + ALT + N"),
]
BY_ID = {a[0]: a for a in ACTIONS}
BY_DOES = {a[1]: a for a in ACTIONS}

# How the student's own line for an action is recognised in bindings.lua:
# by what it runs, backslashes aside (a Lua string may escape its quotes).
# The ids were student.* before the rename to Longhand, so a line from then
# is still the student's own line for the action.
PATTERNS = {
    "page": r"toggle\s+(?:longhand|student)\.page",
    "alongside": r"summon\s+(?:longhand|student)\.page.*alongside",
    "deadlines": r"(?:longhand|student)\.deadline\s+toggle",
    "pomoPopup": r"(?:longhand|student)\.pomo\s+toggle",
    "pomoToggle": r"[\"']pomo\s+toggle[\"']",
    "pomoSkip": r"[\"']pomo\s+skip[\"']",
}

REQUIRE = 'require("default.hypr.require_optional").module("hypr.longhand")'

# ------------------------------------------------------------ keys

# Hyprland's modifier names → the sheet's, in the sheet's order.
MODS = [("CTRL", "Ctrl"), ("ALT", "Alt"), ("SHIFT", "Shift"), ("SUPER", "Super")]
MOD_ALIASES = {"CONTROL": "CTRL", "MOD4": "SUPER", "WIN": "SUPER", "META": "SUPER", "MOD1": "ALT"}
# Keysyms with a name of their own, sheet ↔ Hyprland. A symbol is the one
# on the key without Shift (US layout), so "=" is `equal`; a symbol that
# needs Shift has no keysym of its own a bind can rely on.
NAMED = {
    "=": "equal", "-": "minus", "\\": "backslash", "/": "slash", ",": "comma", ".": "period",
    ";": "semicolon", "'": "apostrophe", "`": "grave", "[": "bracketleft", "]": "bracketright",
    "Plus": "plus", "Space": "space", "Enter": "Return", "Esc": "Escape", "Tab": "Tab",
    "Backspace": "BackSpace", "Del": "Delete", "Ins": "Insert", "Home": "Home", "End": "End",
    "Left": "Left", "Right": "Right", "Up": "Up", "Down": "Down", "PgUp": "Prior", "PgDn": "Next",
}
FROM_SYM = {v.lower(): k for k, v in NAMED.items()}
FROM_SYM.update({"page_up": "PgUp", "page_down": "PgDn", "kp_enter": "Enter", "escape": "Esc", "return": "Enter"})
FKEY = re.compile(r"^F([1-9]|1[0-9]|2[0-4])$", re.I)


def is_symbol(name):
    return name == "Plus" or (len(name) == 1 and not name.isalnum())


def sheet_key(mods, name):
    """The sheet's spelling of a key, from a set of sheet modifiers."""
    if is_symbol(name):
        mods = mods - {"Shift"}
    return "".join(m + "+" for _, m in MODS if m in mods) + name


def from_hypr(s):
    """'SUPER + ALT + equal' → 'Alt+Super+='; '' when it is not a key."""
    parts = [p for p in re.split(r"\s*\+\s*|\s+", str(s).strip()) if p]
    if not parts:
        return ""
    mods = set()
    for p in parts[:-1]:
        u = MOD_ALIASES.get(p.upper(), p.upper())
        m = dict(MODS).get(u)
        if not m:
            return ""
        mods.add(m)
    last = parts[-1]
    if len(last) == 1 and last.isalnum():
        name = last.upper()
    elif FKEY.match(last):
        name = last.upper()
    elif last.lower() in FROM_SYM:
        name = FROM_SYM[last.lower()]
    else:
        return ""
    return sheet_key(mods, name)


def to_hypr(key):
    """'Alt+Super+=' → ('SUPER + ALT + equal', '') or ('', why not)."""
    parts = str(key).split("+")
    if len(parts) > 1 and parts[-1] == "":           # "Super++": the key is the plus
        parts = parts[:-2] + ["Plus"]
    mods, name = set(parts[:-1]), parts[-1]
    known = {m for _, m in MODS}
    if not name or not mods <= known:
        return "", "not a key"
    if "Super" not in mods:
        return "", "a Hyprland key holds Super, so it never takes a key an app needs"
    if len(name) == 1 and name.isalnum():
        sym = name.upper()
    elif FKEY.match(name):
        sym = name.upper()
    elif name in NAMED:
        sym = NAMED[name]
    else:
        return "", f"Hyprland finds {name} by the key under it, which differs between layouts — pick a letter, a digit, an F-key or one of = - \\ / , . ; ' ` [ ]"
    order = [h for h, m in MODS if m in mods]
    order.sort(key=lambda h: ["SUPER", "CTRL", "ALT", "SHIFT"].index(h))   # Omarchy's own order
    if is_symbol(name):
        order = [h for h in order if h != "SHIFT"]
    return " + ".join(order + [sym]), ""


def lua(s):
    """A Lua string literal for a constant of ours."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

# ------------------------------------------------------------ files


def config_home():
    return pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")


def hypr_dir():
    return config_home() / "hypr"


def bindings_path():
    return hypr_dir() / "bindings.lua"


def ours_path():
    return hypr_dir() / "longhand.lua"


def old_path():
    """The file's name before the rename to Longhand (2026-10-16)."""
    return hypr_dir() / "student.lua"


def read(p):
    try:
        return p.read_text()
    except OSError:
        return None


def write(p, text):
    tmp = p.with_name("." + p.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, p)


def wired(text):
    return text is not None and any(
        "hypr.longhand" in l and not l.lstrip().startswith("--") for l in text.splitlines())


BIND_LINE = re.compile(r'^\s*o\.bind\(\s*"([^"]*)"\s*,\s*"((?:[^"\\]|\\.)*)"')
UNBIND_LINE = re.compile(r'^\s*hl\.unbind\(\s*"([^"]*)"\s*\)\s*(?:--\s*was:\s*(.*))?$')


def parse_ours(text):
    """longhand.lua, read back: {id: [sheet keys]} and {sheet key: what it was}."""
    keys = {a[0]: [] for a in ACTIONS}
    taken = {}
    for line in (text or "").splitlines():
        m = BIND_LINE.match(line)
        if m:
            does = m.group(2).replace('\\"', '"').replace("\\\\", "\\")
            k = from_hypr(m.group(1))
            if does in BY_DOES and k and k not in keys[BY_DOES[does][0]]:
                keys[BY_DOES[does][0]].append(k)
            continue
        m = UNBIND_LINE.match(line)
        if m and from_hypr(m.group(1)):
            taken[from_hypr(m.group(1))] = (m.group(2) or "").strip()
    return keys, taken


def own_lines(text):
    """The student's lines in bindings.lua for the six: [(index, id, sheet key)]."""
    out = []
    for i, line in enumerate((text or "").splitlines()):
        s = line.strip()
        if s.startswith("--") or not re.match(r"^(o|hl)\.bind\(", s):
            continue
        plain = s.replace("\\", "")
        for aid, pat in PATTERNS.items():
            if re.search(pat, plain):
                m = re.match(r'^(?:o|hl)\.bind\(\s*["\']([^"\']*)["\']', s)
                out.append((i, aid, from_hypr(m.group(1)) if m else ""))
                break
    return out


def render(keys, taken):
    out = [
        "-- Longhand's Hyprland keys: the page, the timer, the deadlines.",
        "-- Written by the page's keys sheet (Ctrl+/ in the page) and loaded by the",
        "-- last lines of bindings.lua. The keys may be edited here by hand; the sheet",
        "-- reads them back. Delete this file to drop them all.",
        "",
    ]
    used = {k for ks in keys.values() for k in ks}
    gone = [k for k in taken if k in used]
    if gone:
        out.append("-- Keys these took from another bind; the bind comes back once none of")
        out.append("-- the keys below is on it.")
        for k in gone:
            h, _ = to_hypr(k)
            was = re.sub(r"[\x00-\x1f]+", " ", taken[k]).strip()   # a comment ends at a newline
            out.append(f"hl.unbind({lua(h)})" + (f"  -- was: {was}" if was else ""))
        out.append("")
    for aid, does, cmd, _ in ACTIONS:
        for k in keys[aid]:
            h, _ = to_hypr(k)
            if h:
                out.append(f"o.bind({lua(h)}, {lua(does)}, {lua(cmd)})")
    return "\n".join(out) + "\n"

# ------------------------------------------------------------ Hyprland


def hyprctl(*args):
    try:
        r = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10)
        return r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def live_binds():
    """Every bind Hyprland has outside a submap: [{key, does}], sheet keys."""
    try:
        binds = json.loads(hyprctl("binds", "-j") or "[]")
    except json.JSONDecodeError:
        return []
    out = []
    for b in binds:
        if b.get("submap"):
            continue
        m = b.get("modmask", 0)
        mods = {n for bit, n in ((64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift")) if m & bit}
        k = from_hypr(" + ".join([*mods, b["key"]])) if b.get("key") else ""
        if k:
            out.append({"key": k, "does": b.get("description") or b.get("dispatcher", "")})
    return out


def config_errors():
    try:
        return [e for e in json.loads(hyprctl("configerrors", "-j") or "[]") if e]
    except json.JSONDecodeError:
        return []


def apply(changes):
    """Write {path: text} (None: remove), reload Hyprland, and put every file
    back if the reload brought a new error. Returns the new errors."""
    before = set(config_errors())
    old = {p: read(p) for p in changes}
    for p, text in changes.items():
        if text is None:
            p.unlink(missing_ok=True)
        else:
            write(p, text)
    hyprctl("reload", "config-only")
    errors = [e for e in config_errors() if e not in before]
    if errors:
        for p, text in old.items():
            if text is None:
                p.unlink(missing_ok=True)
            else:
                write(p, text)
        hyprctl("reload", "config-only")
    return errors

# ------------------------------------------------------------ commands


def state(note="", **extra):
    b = read(bindings_path())
    ours = read(ours_path())
    owned = wired(b) and ours is not None
    live = live_binds()
    if owned:
        keys, taken = parse_ours(ours)
    else:
        keys, taken = {a[0]: [] for a in ACTIONS}, {}
        for _, aid, k in own_lines(b):
            if k and k not in keys[aid]:
                keys[aid].append(k)
        for x in live:                                   # bound somewhere else, by its description
            a = BY_DOES.get(x["does"])
            if a and x["key"] not in keys[a[0]]:
                keys[a[0]].append(x["key"])
    return {
        "owned": owned,
        "wired": wired(b),
        "file": str(ours_path()),
        "bindings": str(bindings_path()) if b is not None else "",
        "lines": len(own_lines(b)),
        "actions": [{"id": aid, "does": does, "keys": keys[aid], "own": [from_hypr(own)]}
                    for aid, does, _, own in ACTIONS],
        "taken": taken,
        "others": [x for x in live if x["does"] not in BY_DOES],
        "note": note,
        **extra,
    }


def adopt():
    b = read(bindings_path())
    if b is None:
        return state(error=f"no {bindings_path()} to load the keys from")
    current = state()
    if current["owned"]:
        return state("the page keeps these keys already")
    keys = {a["id"]: a["keys"] for a in current["actions"]}
    taken_by = {x["key"]: x["does"] for x in current["others"]}
    missing = []
    for aid, does, _, own in ACTIONS:                    # one never bound gets its own key, if free
        if not keys[aid]:
            k = from_hypr(own)
            if k in taken_by or any(k in ks for ks in keys.values()):
                missing.append(does)
            else:
                keys[aid] = [k]
    lines = b.splitlines()
    stamp = time.strftime("%Y-%m-%d")
    for i, _, _ in own_lines(b):
        lines[i] = "-- " + lines[i] + f"  -- moved to hypr/longhand.lua by the page, {stamp}"
    text = "\n".join(lines).rstrip("\n") + "\n"
    if not wired(text):
        text += ("\n-- Longhand's keys (the page, the timer, the deadlines) live in\n"
                 "-- hypr/longhand.lua, written by the page's keys sheet (Ctrl+/). Delete this\n"
                 "-- line to drop them; the lines above that it moved stay commented out.\n"
                 + REQUIRE + "\n")
    backup = bindings_path().with_name(f"bindings.lua.bak.{int(time.time())}")
    write(backup, b)
    errors = apply({bindings_path(): text, ours_path(): render(keys, {})})
    if errors:
        return state(error="Hyprland refused it, nothing changed: " + errors[0])
    note = f"the page keeps these keys now ({ours_path()}); bindings.lua was backed up to {backup.name}"
    if missing:
        note += f"; no free key for “{'”, “'.join(missing)}”, Enter on it to give it one"
    return state(note)


def migrate():
    """Once, from before the rename to Longhand: student.lua becomes
    longhand.lua with the same keys (their commands now name longhand.*), and
    the line in bindings.lua that loaded it loads the new one, bindings.lua
    backed up first. "" when there is nothing to move; an error is put back."""
    old = read(old_path())
    if old is None or read(ours_path()) is not None:
        return ""
    keys, taken = parse_ours(old)
    changes = {ours_path(): render(keys, taken), old_path(): None}
    b = read(bindings_path())
    if b is not None and "hypr.student" in b:
        backup = bindings_path().with_name(f"bindings.lua.bak.{int(time.time())}")
        write(backup, b)
        changes[bindings_path()] = (b.replace("hypr.student", "hypr.longhand")
                                    .replace("hypr/student.lua", "hypr/longhand.lua")
                                    .replace("omarchy-student's", "Longhand's"))
    errors = apply(changes)
    if errors:
        return "error: Hyprland refused the move to longhand.lua, nothing changed: " + errors[0]
    return f"the keys moved from {old_path().name} to {ours_path().name}"


def set_keys(aid, new, add=False, take=False):
    if aid not in BY_ID:
        return state(error=f"no action {aid}")
    current = state()
    if not current["owned"]:
        return state(error="the page does not keep these keys yet")
    for k in new:
        h, why = to_hypr(k)
        if not h:
            return state(error=why, key=k)
    keys = {a["id"]: list(a["keys"]) for a in current["actions"]}
    taken = dict(current["taken"])
    others = {}
    for x in current["others"]:
        others.setdefault(x["key"], []).append(x["does"])
    outside = [k for k in new if k in others and k not in taken]
    if outside and not take:
        return state(asks={"key": outside[0], "does": others[outside[0]][0]})
    moved_from = []
    for k in new:
        for o in keys:
            if o != aid and k in keys[o]:
                keys[o].remove(k)
                moved_from.append(BY_ID[o][1])
        if k in others and k not in taken:
            taken[k] = others[k][0]
    keys[aid] = [k for k in keys[aid] if k not in new] + list(new) if add else list(new)
    errors = apply({ours_path(): render(keys, taken)})
    if errors:
        return state(error="Hyprland refused it, nothing changed: " + errors[0])
    note = ""
    if moved_from:
        note = f"moved here from “{'”, “'.join(moved_from)}”"
    took = [k for k in new if k in others and k not in current["taken"]]
    if took:
        note = (note + "; " if note else "") + f"taken from Hyprland's “{others[took[0]][0]}”, which gets it back when you move off it"
    return state(note)


def main(argv):
    moved = migrate()
    if moved.startswith("error: "):
        out = state(error=moved[len("error: "):])
    elif not argv or argv[0] in ("state", "migrate"):
        out = state(moved)
    elif argv[0] == "adopt":
        out = adopt()
    elif argv[0] == "set" and len(argv) >= 2:
        flags = {a for a in argv[2:] if a in ("--add", "--take")}
        out = set_keys(argv[1], [a for a in argv[2:] if a not in flags], "--add" in flags, "--take" in flags)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(out))
    return 1 if out.get("error") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
