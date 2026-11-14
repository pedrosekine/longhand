#!/usr/bin/env python3
"""Screenshots of the page, for design reviews: the real page, drawn as it
draws, on a throwaway vault (the same one run.py builds).

It draws in a Hyprland of its own: a second, private Hyprland started inside
yours, with its one window turned off and a headless output to draw on. A
headless output is drawn on its own clock, so the shots come whatever your
session is doing — the Air at home with its lid shut, its panel off and the
session locked (a lock covers every output of the session it locks, a new
one too, and Qt's own grab waits for frames that never come). Nothing shows
in your session, your windows and rules are not touched, and the private
Hyprland is stopped when it is done.

Run: python3 tests/page/shots.py OUT                         every scene
     python3 tests/page/shots.py OUT --scene dashboard        one of: dashboard, note, keys, chat
     python3 tests/page/shots.py OUT --order date             the dashboard's order (ask, course, date)
     python3 tests/page/shots.py OUT --root DIR               draw another checkout (a variant study)
     python3 tests/page/shots.py OUT --env NAME=VALUE         an environment variable for the page
Writes OUT/<scene>-<n>.png, at scale 2. Needs a running Hyprland to start
the private one in (over SSH too: tests/desktop.py finds it).
"""
import argparse
import datetime as dt
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
TITLE = "Page shots"
SIZE = (1100, 850)       # the window, in logical pixels
MODE = "2400x1800"       # the output: 1200x900 logical at scale 2, room for the window
OUTPUT = "SHOT"


def hypr(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10).stdout


def lua(code):
    out = hypr("eval", code).strip()
    if out != "ok":
        raise RuntimeError(f"hyprctl eval: {out}")


def window():
    return next((c for c in json.loads(hypr("clients", "-j") or "[]") if c["title"] == TITLE), None)


class Hyprland:
    """A private Hyprland, nested in the running one, drawing on a headless
    output; this process (and so the page it starts) is pointed at it."""

    def __enter__(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="longhand-shots-"))
        conf = self.dir / "hyprland.lua"
        # Nothing of its own drawn around the window: no border, gap,
        # rounding, shadow or animation.
        conf.write_text("hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true }, "
                        "general = { border_size = 0, gaps_in = 0, gaps_out = 0 }, "
                        "decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } }, "
                        "animations = { enabled = false } })\n")
        env = dict(os.environ, HYPRLAND_NO_SD_NOTIFY="1", XDG_SESSION_TYPE="wayland")
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        self.saved = {k: os.environ.get(k) for k in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE")}
        self.proc = subprocess.Popen(["Hyprland", "--config", str(conf)], env=env, cwd=self.dir,
                                     stdout=open(self.dir / "log", "w"), stderr=subprocess.STDOUT,
                                     start_new_session=True)
        mine = None
        deadline = time.time() + 15
        while time.time() < deadline and not mine:
            time.sleep(0.3)
            inst = json.loads(hypr("instances", "-j") or "[]")
            mine = next((i for i in inst if i.get("pid") == self.proc.pid), None)
        if not mine:
            self.__exit__()
            raise RuntimeError(f"the private Hyprland did not start (log: {self.dir / 'log'})")
        os.environ["WAYLAND_DISPLAY"] = mine["wl_socket"]
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = mine["instance"]
        hypr("output", "create", "headless", OUTPUT)
        lua(f'hl.monitor({{ output = "{OUTPUT}", mode = "{MODE}", scale = 2 }})')
        lua('hl.monitor({ output = "WAYLAND-1", disabled = true })')    # its window in yours: gone
        lua(f'hl.window_rule({{ match = {{ title = "^{TITLE}$" }}, float = true, size = {{ {SIZE[0]}, {SIZE[1]} }} }})')
        return self

    def __exit__(self, *exc):
        self.proc.terminate()
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.dir, ignore_errors=True)


def load_run(root: pathlib.Path):
    sys.argv = ["run.py"]
    spec = importlib.util.spec_from_file_location("pagerun", root / "tests" / "page" / "run.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def page(m, order):
    """run.py's Page, retitled for the shots window, the dashboard in `order`
    and the pointer left where it is (it would follow the selection, and a
    hint would open under it)."""
    real = m.subprocess.Popen

    class Popen(real):
        def __init__(self, args, **kw):
            if args and args[0] == "quickshell" and "ipc" not in args:
                shell = pathlib.Path(args[2])
                qml = shell / "shell.qml"
                qml.write_text(qml.read_text().replace('windowTitle: "Page scratch"', f'windowTitle: "{TITLE}"'))
                tmp = shell.parent
                (tmp / "state" / "longhand" / "page.json").write_text(json.dumps({"dashOrder": order}))
                (tmp / "config" / "longhand" / "settings.json").write_text(json.dumps({"pointer": "off"}))
            super().__init__(args, **kw)

    m.subprocess.Popen = Popen
    try:
        return m.Page()
    finally:
        m.subprocess.Popen = real


def fixture(m, p):
    """Three boxes — one the agent answered (unread), one talked about and
    read, one never — and a question the agent asks about the first."""
    d0 = dt.date.today()
    d1 = d0 + dt.timedelta(days=1)
    lines = [f"- [ ] Revise Themenvorschlag based on Bernd's feedback and send the updated version #thesis ⏳ {d0} 📅 {d0}",
             f"- [ ] Reflective research diary 2 #studio 📅 {d0}",
             f"- [ ] read ch. 4-5 and take notes on the reforms #history 📅 {d1}"]
    h0 = m.blocks.split(lines[0])[0]["hash"]
    h1 = m.blocks.split(lines[1])[0]["hash"]
    (p.vault / "agents" / "longhand" / "daily").mkdir(parents=True, exist_ok=True)
    (p.vault / "agents" / "longhand" / "daily" / f"{m.TODAY}.json").write_text(json.dumps({"blocks": {
        h0: {"state": "reply", "reply": "It first appears in your 10 November note; 13 November is its due date.",
             "read": False, "head": lines[0],
             "chat": [{"role": "student", "text": "when did I write this?"},
                      {"role": "agent", "text": "It first appears in your 10 November note; 13 November is its due date."}]},
        h1: {"state": "reply", "reply": "The template is in the course folder.", "read": True, "head": lines[1],
             "chat": [{"role": "agent", "text": "The template is in the course folder."},
                      {"role": "student", "text": "which questions does this one ask?"}]}}}))
    # The agent's key for a box: its project, a tab, its words (agent/lifespan.py).
    key = "thesis\t- Revise Themenvorschlag based on Bernd's feedback and send the updated version #thesis"
    (p.state / "longhand" / "proposals.json").write_text(json.dumps({"items": [
        {"kind": "question", "id": 1, "key": key, "status": "open", "at": f"{d0}T09:00:00",
         "question": "Does the draft clinic require a half-page submission or a longer one?",
         "recommended": "A half-page building block using the current thesis draft, not a new text."}]}))
    (p.daily / f"{m.TODAY}.md").write_text(m.header(m.TODAY) + "Plans for the day.\n\n" + "\n\n".join(lines) + "\n")


def grab(path):
    # The private Hyprland's own notice (it was started without
    # start-hyprland, as a throwaway one is) sits on top of the window.
    hypr("dismissnotify")
    time.sleep(0.2)
    w = window()
    (x, y), (wd, ht) = w["at"], w["size"]
    subprocess.run(["grim", "-g", f"{x},{y} {wd}x{ht}", str(path)], timeout=15, check=True)


def scenes(m, p, out, which):
    shots = []

    def shot(name):
        time.sleep(0.6)
        path = out / f"{name}.png"
        grab(path)
        shots.append(path)

    if which in ("all", "dashboard"):
        p.call("dash")
        p.wait(lambda: sum(r.get("kind") == "task" for r in json.loads(p.call("dashRows"))) >= 3, 8)
        time.sleep(1)
        rows = json.loads(p.call("dashRows"))
        acts = [i for i, r in enumerate(rows) if r.get("kind") in ("task", "deadline", "question", "proposal")]
        for n, i in enumerate(acts):
            p.call("dashFocus", i)
            shot(f"dashboard-{n}")
        p.call("dash")
    if which in ("all", "chat"):
        p.call("dash")
        p.wait(lambda: any(r.get("kind") == "task" for r in json.loads(p.call("dashRows"))), 8)
        rows = json.loads(p.call("dashRows"))
        p.call("dashFocus", next(i for i, r in enumerate(rows) if r.get("kind") == "task"))
        p.call("dashKey", 0x43, 0)          # C: its chat, beside
        shot("chat-0")
        p.call("closePanes")
        p.call("dash")
    if which in ("all", "note"):
        p.open_fresh()
        p.call("cursorLine", 2)
        shot("note-0")
    if which in ("all", "keys"):
        p.call("keys")
        shot("keys-0")
        p.call("keys")
    return shots


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--scene", default="all", choices=["all", "dashboard", "note", "keys", "chat"])
    ap.add_argument("--order", default="ask", choices=["ask", "course", "date"])
    ap.add_argument("--root", type=pathlib.Path, default=HERE.parent.parent)
    ap.add_argument("--env", action="append", default=[])
    a = ap.parse_args()
    sys.path.insert(0, str(HERE.parent))
    import desktop
    desktop.reach("the page")
    for kv in a.env:
        k, _, v = kv.partition("=")
        os.environ[k] = v
    a.out.mkdir(parents=True, exist_ok=True)
    m = load_run(a.root.resolve())
    with Hyprland():
        p = page(m, a.order)
        try:
            fixture(m, p)
            p.open_fresh()
            for path in scenes(m, p, a.out, a.scene):
                print(path)
        finally:
            p.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
