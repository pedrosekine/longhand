"""Longhand's page on Windows, held by a host that stands in for omarchy-shell.

A spike (2026-11-23): does plugin-page/Page.qml load, draw and take keys on
Windows with nothing in it changed? The host gives the page the modules it
imports — Quickshell, Quickshell.Io, Quickshell.Wayland, qs.Commons, qs.Ui —
under their own names (shim/, qs_io.py, qs_wayland.py).

    python windows/longhand_host.py                    the page, pinned, on your own config
    python windows/longhand_host.py --overlay          the overlay shape
    python windows/longhand_host.py --sandbox DIR      a throwaway vault, config and state in DIR
    python windows/longhand_host.py --sandbox DIR --check OUT.json [--shot OUT.png]
                                                       type into it, save, read it back, say what happened
"""
from __future__ import annotations

import argparse
import datetime
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
    return {"vault": vault, "note": vault / "daily" / f"{datetime.date.today():%Y-%m-%d}.md"}


def main() -> int:
    ap = argparse.ArgumentParser(description="Longhand's page on Windows (spike)")
    ap.add_argument("--overlay", action="store_true", help="open the overlay instead of the pinned window")
    ap.add_argument("--sandbox", type=Path, help="use a throwaway vault, config and state in this folder")
    ap.add_argument("--check", type=Path, help="drive the page and write what happened to this JSON file")
    ap.add_argument("--shot", type=Path, help="with --check: save a picture of the window here")
    args = ap.parse_args()

    box = sandbox(args.sandbox.resolve()) if args.sandbox else None
    if args.check and not box:
        ap.error("--check needs --sandbox: it types into the note")

    # The page restyles its controls; the native Windows style refuses that.
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickWindow

    import host_api  # noqa: F401  (registers LonghandHost)
    import qs_io  # noqa: F401     (registers Quickshell.Io)
    import qs_wayland  # noqa: F401 (registers Quickshell.Wayland)

    QQuickWindow.setDefaultAlphaBuffer(True)
    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("Longhand")

    warnings: list[str] = []
    engine = QQmlApplicationEngine()
    engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
    engine.addImportPath(str(HERE / "shim"))
    ctx = engine.rootContext()
    ctx.setContextProperty("hostShape", "overlay" if args.overlay else "alongside")
    ctx.setContextProperty("hostKeepAlive", bool(args.check))
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        print("longhand-host: the page did not load", file=sys.stderr)
        for w in warnings:
            print("  " + w, file=sys.stderr)
        if args.check:
            args.check.write_text(json.dumps({"loaded": False, "warnings": warnings}, indent=2), encoding="utf-8")
        return 1

    if args.check:
        import spike_check
        spike_check.run(app, engine, box, args, warnings)

    code = app.exec()
    if not args.check:
        for w in warnings:
            print(w, file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
