"""Longhand on Windows: a host that stands in for omarchy-shell.

It holds the page (plugin-page/, loaded as it is), opens it when asked, and
stays by the clock with the timer and the next deadline, as the shell's bar
has them. The page imports Quickshell, Quickshell.Io, Quickshell.Wayland,
qs.Commons and qs.Ui; the host gives it each under its own name (shim/,
qs_io.py, qs_wayland.py).

    longhand                      today's note, as a window — and Longhand stays in the tray
    longhand --overlay            the page over everything (again: away)
    longhand --tray               in the tray only, nothing opened (for the start of a session)
    longhand summon ['{json}']    as `omarchy-shell shell summon longhand.page` (or: summon alongside)
    longhand toggle ['{json}']    as `omarchy-shell shell toggle longhand.page`
    longhand quit

One Longhand runs at a time: a second `longhand` tells the first what was
asked and ends. From anywhere, Win+Alt+\\ is the window and Win+Alt+= the
overlay (hotkeys.py).

    longhand --sandbox DIR        a throwaway vault, config and state in DIR
    python windows/longhand_host.py --sandbox DIR --check OUT.json [--shot OUT.png]
                                  type into it, save, read it back, say what happened
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))


def sandbox(root: Path) -> dict:
    """A vault, a config and a state folder of the spike's own."""
    vault = root / "vault"
    (vault / "daily").mkdir(parents=True, exist_ok=True)
    cfg_dir = root / "config" / "longhand"
    cfg_dir.mkdir(parents=True, exist_ok=True)
    (root / "state").mkdir(parents=True, exist_ok=True)
    cfg = {
        "vault": vault.as_posix(),
        "daily": {"dir": "daily", "format": "YYYY-MM-DD"},
        "agentDir": "agents/longhand",
        "runner": (REPO / "agent" / "longhand-agent").as_posix(),
        "read": (REPO / "cli" / "longhand-read").as_posix(),
        # Windows has none of the page's own faces; this is its reading face.
        "font": "Segoe UI Variable Text",
        "languages": ["English"],
        "weekStart": "monday",
    }
    path = cfg_dir / "config.json"
    if not path.exists():
        path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    os.environ["XDG_CONFIG_HOME"] = (root / "config").as_posix()
    os.environ["XDG_STATE_HOME"] = (root / "state").as_posix()
    os.environ["LONGHAND_SILENT"] = "1"
    return {"vault": vault, "state": root / "state", "note": vault / "daily" / f"{datetime.date.today():%Y-%m-%d}.md"}


def instance_name() -> str:
    """One Longhand for each config: a sandbox does not answer for the real one."""
    config = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return "longhand-" + hashlib.md5(os.path.normcase(os.path.abspath(config)).encode()).hexdigest()[:12]


def tell_running(message: dict) -> bool:
    """Hand what was asked to the Longhand already running; False when none is."""
    from PySide6.QtNetwork import QLocalSocket
    sock = QLocalSocket()
    sock.connectToServer(instance_name())
    if not sock.waitForConnected(300):
        return False
    if os.name == "nt":
        import ctypes
        ctypes.windll.user32.AllowSetForegroundWindow(-1)      # it may come to the front: we were asked to
    sock.write((json.dumps(message) + "\n").encode("utf-8"))
    sock.waitForBytesWritten(1000)
    sock.disconnectFromServer()
    return True


def main() -> int:
    ap = argparse.ArgumentParser(prog="longhand", description="Longhand's page on Windows")
    ap.add_argument("command", nargs="?", choices=("summon", "toggle", "quit"), help="what to ask of Longhand")
    ap.add_argument("payload", nargs="?", default="", help='for summon and toggle: {"shape":"alongside"}, {"goto":"…"}')
    ap.add_argument("--overlay", action="store_true", help="the page over everything, instead of as a window")
    ap.add_argument("--tray", action="store_true", help="start in the tray, nothing opened")
    ap.add_argument("--sandbox", type=Path, help="use a throwaway vault, config and state in this folder")
    ap.add_argument("--check", type=Path, help="drive the page and write what happened to this JSON file")
    ap.add_argument("--shot", type=Path, help="with --check: save a picture of the window here")
    args = ap.parse_args()

    box = sandbox(args.sandbox.resolve()) if args.sandbox else None
    if args.check and not box:
        ap.error("--check needs --sandbox: it types into the note")

    # What was asked, as the running Longhand (this one, or one already there) takes it.
    if args.command == "quit":
        asked = {"do": "quit"}
    elif args.command in ("summon", "toggle"):
        # JSON's quotes are hard to get through a Windows command line whole:
        # a bare word is taken for the shape (`longhand summon alongside`).
        payload = args.payload.strip() or "{}"
        asked = {"do": args.command, "payload": payload if payload.startswith("{") else json.dumps({"shape": payload})}
    elif args.tray:
        asked = None
    elif args.overlay:
        asked = {"do": "toggle", "payload": "{}"}
    else:
        asked = {"do": "summon", "payload": '{"shape":"alongside"}'}

    # The page restyles its controls; the native Windows style refuses that.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

    from PySide6.QtCore import QTimer, QUrl
    from PySide6.QtGui import QGuiApplication, QIcon
    from PySide6.QtNetwork import QLocalServer
    from PySide6.QtQml import QQmlAbstractUrlInterceptor, QQmlApplicationEngine
    from PySide6.QtQuick import QQuickWindow

    QQuickWindow.setDefaultAlphaBuffer(True)
    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("Longhand")
    app.setQuitOnLastWindowClosed(False)       # the page put away is not Longhand gone
    resident = not args.check

    if resident and asked is not None and tell_running(asked):
        return 0
    if asked == {"do": "quit"}:
        return 0                                # none was running

    import host_api                            # registers LonghandHost
    import qs_io  # noqa: F401                  (registers Quickshell.Io)
    import qs_wayland  # noqa: F401             (registers Quickshell.Wayland)
    bridge = host_api.BRIDGE
    icon = REPO / "launcher" / "longhand.svg"
    if icon.is_file():
        app.setWindowIcon(QIcon(str(icon)))

    class Shared(QQmlAbstractUrlInterceptor):
        """plugin-deadline reads plugin-page's Store.js: tools/install-plugins
        puts a copy beside it on Omarchy; here it is found where it is kept."""

        def intercept(self, url, kind):
            if url.isLocalFile() and url.fileName() == "Store.js" and "/plugin-deadline/" in url.path():
                return QUrl.fromLocalFile(str(REPO / "plugin-page" / "Store.js"))
            return url

    warnings: list[str] = []
    engine = QQmlApplicationEngine()
    shared = Shared()
    engine.addUrlInterceptor(shared)
    engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
    engine.addImportPath(str(HERE / "shim"))
    ctx = engine.rootContext()
    ctx.setContextProperty("hostBridge", bridge)
    ctx.setContextProperty("hostResident", resident)
    ctx.setContextProperty("hostKeepAlive", bool(args.check))
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        print("longhand-host: the page did not load", file=sys.stderr)
        for w in warnings:
            print("  " + w, file=sys.stderr)
        if args.check:
            args.check.write_text(json.dumps({"loaded": False, "warnings": warnings}, indent=2), encoding="utf-8")
        return 1
    roots = engine.rootObjects()               # held: let go of, PySide deletes the page with them

    def come_forward() -> None:
        """The page's window to the front: Hyprland does this for the page there."""
        for w in app.allWindows():
            if w.isVisible() and w.title():
                w.raise_()
                w.requestActivate()

    def act(message: dict) -> None:
        do, payload = message.get("do"), str(message.get("payload") or "{}")
        if do == "summon":
            bridge.summonRequested.emit(payload)
            QTimer.singleShot(200, come_forward)
        elif do == "toggle":
            bridge.toggleRequested.emit(payload)
        elif do == "quit":
            bridge.quitRequested.emit()

    keys = None
    server = None
    if resident:
        server = QLocalServer()
        QLocalServer.removeServer(instance_name())

        def heard() -> None:
            sock = server.nextPendingConnection()
            if sock is None:
                return

            def read() -> None:
                for line in bytes(sock.readAll()).decode("utf-8", "replace").splitlines():
                    try:
                        act(json.loads(line))
                    except ValueError:
                        pass
            sock.readyRead.connect(read)
            sock.disconnected.connect(sock.deleteLater)
            read()
        server.newConnection.connect(heard)
        server.listen(instance_name())

        if os.name == "nt":
            import hotkeys

            def pressed(action: str) -> None:
                bridge.act(action)
                if action == "alongside":
                    QTimer.singleShot(200, come_forward)
            keys = hotkeys.Keys(pressed)
            app.installNativeEventFilter(keys)
            keys.register()
            bridge.keys, bridge.problems = dict(keys.held), dict(keys.problems)
            bridge.keysChanged.emit()
            for why in keys.problems.values():
                print("longhand: " + why, file=sys.stderr)

    if args.check:
        import spike_check
        spike_check.run(app, engine, box, args, warnings)
    if asked is not None:
        QTimer.singleShot(0, lambda: act(asked))

    code = app.exec()
    if keys is not None:
        keys.release()
    if server is not None:
        server.close()
    if not args.check:
        for w in warnings:
            print(w, file=sys.stderr)
    del roots
    return code


if __name__ == "__main__":
    sys.exit(main())
