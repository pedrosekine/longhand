"""A notification, as `notify-send TITLE BODY` gives one on Omarchy.

`pomo` says a session ran out this way. With Longhand running (in the
tray), Longhand says it, from the tray, as it says everything else; without
it — `pomo` in a terminal, nothing in the tray — Windows says it itself, a
toast from PowerShell's WinRT bridge, under Longhand's name when the Start
menu has Longhand (`longhand install`), else under PowerShell's. Windows
keeps either quiet under Do Not Disturb.

    notify.py TITLE BODY
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

# PowerShell's own AppUserModelID: a toast needs a name Windows knows.
POWERSHELL_ID = r"{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"


def instance_name() -> str:
    """The running Longhand's name for itself (longhand_host.instance_name)."""
    config = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return "longhand-" + hashlib.md5(os.path.normcase(os.path.abspath(config)).encode()).hexdigest()[:12]


def to_longhand(title: str, body: str) -> bool:
    """Said by the running Longhand; False when none is running. Qt's local
    server is a named pipe on Windows."""
    if os.name != "nt":
        return False
    try:
        with open(r"\\.\pipe" + "\\" + instance_name(), "wb", buffering=0) as pipe:
            pipe.write((json.dumps({"do": "notify", "title": title, "body": body}) + "\n").encode("utf-8"))
        return True
    except OSError:
        return False


def app_id() -> str:
    """Longhand's name, when the Start menu has its shortcut."""
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import shortcuts
        if shortcuts.shortcut_path().exists():
            return shortcuts.APP_ID
    except Exception:  # noqa: BLE001 — PowerShell's name will do
        pass
    return POWERSHELL_ID


def script(title: str, body: str, aumid: str) -> str:
    """The toast, in PowerShell; every word passed as base64, so nothing
    said is ever read as code."""
    def b64(s: str) -> str:
        return base64.b64encode(s.encode("utf-8")).decode("ascii")

    def text(s: str) -> str:
        return f"[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{b64(s)}'))"
    return (
        "$ErrorActionPreference='Stop';"
        "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;"
        "$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
        "$t = $x.GetElementsByTagName('text');"
        f"$t.Item(0).AppendChild($x.CreateTextNode({text(title)})) > $null;"
        f"$t.Item(1).AppendChild($x.CreateTextNode({text(body)})) > $null;"
        f"[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier({text(aumid)})"
        ".Show([Windows.UI.Notifications.ToastNotification]::new($x))"
    )


def toast(title: str, body: str) -> bool:
    if os.name != "nt":
        return False
    encoded = base64.b64encode(script(title, body, app_id()).encode("utf-16-le")).decode("ascii")
    try:
        r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
                            "-EncodedCommand", encoded], stdin=subprocess.DEVNULL, capture_output=True,
                           timeout=20, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def notify(title: str, body: str) -> bool:
    return to_longhand(title, body) or toast(title, body)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    return 0 if notify(argv[0], argv[1]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
