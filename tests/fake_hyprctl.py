#!/usr/bin/env python3
"""A stand-in for `hyprctl`, enough for the page's Hyprland keys.

It plays Hyprland over a throwaway config: `binds -j` is a few of
Omarchy's binds (minus any longhand.lua unbinds), every live `o.bind` line
in bindings.lua, and longhand.lua's binds once bindings.lua loads it.
`configerrors -j` reports an error while longhand.lua holds the text in
$FAKE_HYPR_DIR/break, so a write Hyprland would refuse can be replayed.
`reload` and `eval` only log — the sheet's submap never reaches the real
Hyprland, so a test cannot hold the keyboard. With $FAKE_HYPR_REAL set,
anything else (`getoption`, which Omarchy's Style asks) goes to the real
hyprctl. Every call is logged to $FAKE_HYPR_DIR/calls, one per line.

Install it as `hyprctl` on PATH with FAKE_HYPR_DIR set to the hypr folder.
"""
import json
import os
import pathlib
import re
import sys

d = pathlib.Path(os.environ["FAKE_HYPR_DIR"])
args = sys.argv[1:]
with open(d / "calls", "a") as f:
    f.write(" ".join(args) + "\n")

BASE = [("SUPER + ALT + F", "Full width"), ("SUPER + Return", "Terminal"), ("SUPER + ALT + S", "Move window to scratchpad")]
BITS = {"SUPER": 64, "CTRL": 4, "ALT": 8, "SHIFT": 1}


def text(name):
    p = d / name
    return p.read_text() if p.exists() else ""


def live_lines(src):
    return [l for l in src.splitlines() if not l.lstrip().startswith("--")]


def bind(keys, does):
    parts = [p.strip() for p in keys.split("+")]
    mask = sum(BITS.get(p.upper(), 0) for p in parts[:-1])
    return {"modmask": mask, "key": parts[-1], "description": does, "submap": "", "dispatcher": "__lua", "arg": "1"}


if args[:2] == ["binds", "-j"]:
    ours = text("longhand.lua")
    loaded = any("hypr.longhand" in l for l in live_lines(text("bindings.lua")))
    unbound = set(re.findall(r'hl\.unbind\("([^"]+)"\)', ours)) if loaded else set()
    out = [bind(k, n) for k, n in BASE if k not in unbound]
    srcs = [text("bindings.lua")] + ([ours] if loaded else [])
    for src in srcs:
        for l in live_lines(src):
            m = re.match(r'\s*o\.bind\("([^"]+)",\s*"((?:[^"\\]|\\.)*)"', l)
            if m:
                out.append(bind(m.group(1), m.group(2)))
    print(json.dumps(out))
elif args[:2] == ["configerrors", "-j"]:
    brk = text("break").strip()
    print(json.dumps(["longhand.lua: refused"] if brk and brk in text("longhand.lua") else [""]))
elif args[:1] in (["reload"], ["eval"]) or not os.environ.get("FAKE_HYPR_REAL"):
    print("ok")
else:
    os.execv(os.environ["FAKE_HYPR_REAL"], ["hyprctl", *args])
