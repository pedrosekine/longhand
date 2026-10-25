"""A machine of the test's own: a config folder and a Hyprland played by
tests/fake_hyprctl.py over a throwaway hypr folder, so a test never reads
the real ~/.config (the opencode agents, keys.json, Hyprland's binds) or
asks the running Hyprland anything. Returns what to add to the
environment of whatever runs under it.
"""
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# The page's own six, as the student's bindings.lua has them.
BINDINGS = """o.bind("SUPER + ALT + P", "Pomo toggle", "pomo toggle")
o.bind("SUPER + ALT + N", "Pomo skip", "pomo skip")
o.bind("SUPER + ALT + O", "Pomo popup", "omarchy-shell longhand.pomo toggle")
o.bind("SUPER + ALT + D", "Deadlines popup", "omarchy-shell longhand.deadline toggle")
o.bind("SUPER + ALT + equal", "Page (today's note)", "omarchy-shell shell toggle longhand.page '{}'")
o.bind("SUPER + ALT + backslash", "Page alongside", "omarchy-shell shell summon longhand.page '{\\"shape\\":\\"alongside\\"}'")
"""


def machine(tmp: pathlib.Path, config: pathlib.Path | None = None) -> dict:
    config = config or tmp / "config"
    hypr = config / "hypr"
    hypr.mkdir(parents=True, exist_ok=True)
    if not (hypr / "bindings.lua").exists():
        (hypr / "bindings.lua").write_text(BINDINGS)
    bindir = tmp / "fakebin"
    bindir.mkdir(exist_ok=True)
    (bindir / "hyprctl").write_text(f'#!/bin/sh\nexec {sys.executable} "{ROOT}/tests/fake_hyprctl.py" "$@"\n')
    (bindir / "hyprctl").chmod(0o755)
    return {"XDG_CONFIG_HOME": str(config), "FAKE_HYPR_DIR": str(hypr),
            "PATH": f"{bindir}:{os.environ['PATH']}"}
