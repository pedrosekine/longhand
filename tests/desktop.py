"""The desktop a test draws on, for the few that open a real window
(test_popup.py, page/run.py). A terminal on the desktop already says where
it is (WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE); a shell over SSH —
a Claude session started on the Air from xmg — does not, so the running
Hyprland is asked for them (`hyprctl instances`). With no Hyprland running,
the test says so and stops, instead of failing every check after it.

The screen must be on, too: with the lid closed or the machine idle,
Hyprland powers it off (DPMS), the window gets no frames, and the page
stops answering. So reach() wakes it first. A locked session covers every
output, woken or not; a test that needs more than a few seconds of frames
draws in a Private Hyprland instead, on a headless output of its own.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time


def find() -> dict:
    """What the environment lacks to reach the running Hyprland: nothing
    when it already has it, the newest running instance when not, and
    nothing either when none runs."""
    if os.environ.get("WAYLAND_DISPLAY") and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return {}
    try:
        r = subprocess.run(["hyprctl", "instances", "-j"], capture_output=True, text=True, timeout=5)
        running = [i for i in json.loads(r.stdout or "[]") if i.get("wl_socket") and i.get("instance")]
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}
    if not running:
        return {}
    newest = max(running, key=lambda i: i.get("time", 0))
    found = {"WAYLAND_DISPLAY": newest["wl_socket"], "HYPRLAND_INSTANCE_SIGNATURE": newest["instance"],
             "XDG_SESSION_TYPE": "wayland"}
    return {k: v for k, v in found.items() if not os.environ.get(k)}


def screens_off() -> list[str]:
    """The screens Hyprland has powered off (DPMS): idle, or a closed lid.
    A window on one gets no frames, and a Qt Quick window waiting for one
    stops answering altogether."""
    try:
        r = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5)
        return [m["name"] for m in json.loads(r.stdout or "[]") if not m.get("disabled") and not m.get("dpmsStatus", True)]
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        return []


def wake() -> list[str]:
    """Power the screens back on; the ones that were off. Hyprland's Lua
    config takes the dispatcher as Lua; an older one as words."""
    off = screens_off()
    if off:
        for cmd in (["hyprctl", "eval", 'hl.dispatch(hl.dsp.dpms({ action = "on" }))'], ["hyprctl", "dispatch", "dpms", "on"]):
            try:
                subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                continue
            if not screens_off():
                break
    return off


def reach(what: str, wake_screen: bool = True) -> None:
    """Point this process (and so whatever it starts) at the desktop, with
    its screen on, or stop: `what` is the window the test was going to open.
    A test that draws in a Private Hyprland leaves the screen as it is."""
    os.environ.update(find())
    if not os.environ.get("WAYLAND_DISPLAY"):
        print(f"FAIL no desktop to open {what} on: no WAYLAND_DISPLAY, and no running Hyprland found "
              "(hyprctl instances). Run it on a machine where Hyprland is up.")
        print("1 FAILED")
        sys.exit(1)
    if not wake_screen:
        return
    woken = wake()
    if woken:
        print(f"     the screen was off ({', '.join(woken)}: idle, or the lid closed); woke it to draw {what}", flush=True)
        if screens_off():
            print(f"FAIL the screen stays off ({', '.join(screens_off())}), so {what} cannot draw. Wake it and run again.")
            print("1 FAILED")
            sys.exit(1)


def hypr(*args) -> str:
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10).stdout


def lua(code: str) -> None:
    out = hypr("eval", code).strip()
    if out != "ok":
        raise RuntimeError(f"hyprctl eval: {out}")


class Private:
    """A private Hyprland, nested in the running one, drawing on a headless
    output; this process (and so whatever it starts) is pointed at it, and
    pointed back on the way out.

    A headless output is drawn on its own clock, so a window there gets its
    frames whatever the session is doing: the Air at home with its lid shut,
    its panel off and the session locked (a lock covers every output of the
    session it locks, a new one too). Nothing shows in the session, and its
    windows and rules are not touched. `rules` are Lua lines run once it is up
    (hl.window_rule(...)). Written for tests/page/shots.py (2026-11-14)."""

    OUTPUT = "PRIVATE"

    def __init__(self, mode: str = "2400x1800", scale: int = 2, rules: list[str] = ()):
        self.mode, self.scale, self.rules = mode, scale, list(rules)

    def __enter__(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="longhand-hypr-"))
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
            log = (self.dir / "log").read_text()[-2000:]
            self.__exit__()
            raise RuntimeError(f"the private Hyprland did not start:\n{log}")
        os.environ["WAYLAND_DISPLAY"] = mine["wl_socket"]
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = mine["instance"]
        hypr("output", "create", "headless", self.OUTPUT)
        lua(f'hl.monitor({{ output = "{self.OUTPUT}", mode = "{self.mode}", scale = {self.scale} }})')
        lua('hl.monitor({ output = "WAYLAND-1", disabled = true })')    # its window in the session: gone
        for rule in self.rules:
            lua(rule)
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
