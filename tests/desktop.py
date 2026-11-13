"""The desktop a test draws on, for the few that open a real window
(test_popup.py, page/run.py). A terminal on the desktop already says where
it is (WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE); a shell over SSH —
a Claude session started on the Air from xmg — does not, so the running
Hyprland is asked for them (`hyprctl instances`). With no Hyprland running,
the test says so and stops, instead of failing every check after it.
"""
import json
import os
import subprocess
import sys


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


def reach(what: str) -> None:
    """Point this process (and so whatever it starts) at the desktop, or
    stop: `what` is the window the test was going to open."""
    os.environ.update(find())
    if not os.environ.get("WAYLAND_DISPLAY"):
        print(f"FAIL no desktop to open {what} on: no WAYLAND_DISPLAY, and no running Hyprland found "
              "(hyprctl instances). Run it on a machine where Hyprland is up.")
        print("1 FAILED")
        sys.exit(1)
