#!/usr/bin/env python3
"""PySide6 IPC host for tests/page/harness.qml.

Stands in for `quickshell -p <shell>` + `quickshell ipc` so the full live
page suite (tests/page/run.py) can run on Windows — and on headless Linux
without Hyprland or Quickshell installed.

Protocol: listens on 127.0.0.1:<ephemeral>, writes the port number to
`<shell>/.qt-ipc-port`, and answers newline-delimited JSON requests:
    {"fn": "summon", "args": ["{}"]}  ->  {"ok": true, "out": ""}
Special host commands:
    {"fn": "__resize", "args": ["701", "850"]}   resize the test window
    {"fn": "__quit", "args": []}                 exit cleanly
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WINDOWS = ROOT / "windows"
sys.path.insert(0, str(WINDOWS))


def _coerce_js(arg: str, type_name: str) -> str:
    """Turn a string IPC argument into a JS literal matching the QML method's parameter type."""
    t = type_name.strip().lower()
    if t in ("bool", "boolean"):
        return "true" if str(arg).lower() in ("1", "true", "yes") else "false"
    if t in ("int", "long", "uint", "qint32", "quint32"):
        try:
            return str(int(float(arg)))
        except ValueError:
            return "0"
    if t in ("double", "float", "qreal", "real"):
        try:
            return repr(float(arg))
        except ValueError:
            return "0"
    return json.dumps(str(arg))


def _format_result(val) -> str:
    if val is None:
        return ""
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (int, float)):
        return str(val)
    return str(val)


def main(argv: list[str]) -> int:
    if len(argv) < 1:
        print("usage: qt_host.py <shell-dir> [width] [height]", file=sys.stderr)
        return 2
    shell_dir = Path(argv[0]).resolve()
    want_w = int(argv[1]) if len(argv) > 1 else 701
    want_h = int(argv[2]) if len(argv) > 2 else 850

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

    from PySide6.QtCore import QMetaMethod, QObject, QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtNetwork import QHostAddress, QTcpServer
    from PySide6.QtQml import QQmlAbstractUrlInterceptor, QQmlApplicationEngine, QQmlExpression, qmlContext
    from PySide6.QtQuick import QQuickWindow

    QQuickWindow.setDefaultAlphaBuffer(True)
    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("LonghandTest")
    app.setQuitOnLastWindowClosed(False)

    import file_urls
    import host_api  # noqa: F401
    import qs_io
    import qs_wayland  # noqa: F401

    qs_io.REWRITE_HYPRKEYS = False
    _file_handler = file_urls.install()  # noqa: F841

    class Interceptor(QQmlAbstractUrlInterceptor):
        """Map `<shell>/page/...` directly to `plugin-page/...` without needing symlinks."""
        def intercept(self, url, kind):
            if url.isLocalFile():
                p = url.toLocalFile().replace("\\", "/")
                prefix = shell_dir.as_posix().rstrip("/") + "/page/"
                if p.lower().startswith(prefix.lower()):
                    rel = p[len(prefix):]
                    return QUrl.fromLocalFile(str(ROOT / "plugin-page" / rel))
                if p.lower() == (shell_dir.as_posix().rstrip("/") + "/page").lower():
                    return QUrl.fromLocalFile(str(ROOT / "plugin-page"))
            return url

    warnings: list[str] = []
    engine = QQmlApplicationEngine()
    interceptor = Interceptor()
    engine.addUrlInterceptor(interceptor)
    engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
    engine.addImportPath(str(WINDOWS / "shim"))
    engine.load(QUrl.fromLocalFile(str(shell_dir / "shell.qml")))
    if not engine.rootObjects():
        print("qt_host: failed to load shell.qml", file=sys.stderr)
        for w in warnings:
            print("  " + w, file=sys.stderr)
        return 1

    roots = engine.rootObjects()  # keep alive
    root = roots[0]

    # Locate the IpcHandler with target == "page"
    handler = None
    for obj in root.findChildren(QObject):
        if isinstance(obj, qs_io.IpcHandler) and obj.property("target") == "page":
            handler = obj
            break
    if handler is None:
        print("qt_host: no IpcHandler(target='page') found", file=sys.stderr)
        return 1

    # Index method parameter types from QMetaObject (QML functions register as Slots or Methods)
    methods: dict[str, list[str]] = {}
    mo = handler.metaObject()
    for i in range(mo.methodCount()):
        mm = mo.method(i)
        if mm.methodType() in (QMetaMethod.MethodType.Method, QMetaMethod.MethodType.Slot):
            name = bytes(mm.name()).decode("utf-8", "replace")
            ptypes = [bytes(t).decode("utf-8", "replace") for t in mm.parameterTypes()]
            methods[name] = ptypes

    ctx = qmlContext(handler)
    size_state = {"w": want_w, "h": want_h}

    def apply_window_size():
        for w in app.allWindows():
            if w.title() == "Page scratch":
                w.setProperty("implicitWidth", size_state["w"])
                w.setProperty("implicitHeight", size_state["h"])
                w.resize(size_state["w"], size_state["h"])

    apply_window_size()

    def invoke(fn: str, args: list[str]) -> tuple[bool, str]:
        if fn == "__quit":
            app.quit()
            return True, ""
        if fn == "__resize":
            size_state["w"] = int(args[0])
            size_state["h"] = int(args[1])
            apply_window_size()
            app.processEvents()
            return True, ""
        if fn not in methods:
            print(f"qt_host: no IPC method {fn!r}", file=sys.stderr, flush=True)
            return False, f"no IPC method {fn!r}"
        ptypes = methods[fn]
        js_args = [_coerce_js(a, ptypes[i] if i < len(ptypes) else "QString") for i, a in enumerate(args)]
        expr = QQmlExpression(ctx, handler, f"{fn}({', '.join(js_args)})")
        res = expr.evaluate()
        if isinstance(res, tuple):
            res = res[0]
        if expr.hasError():
            err = expr.error().toString()
            print(f"qt_host IPC error {fn}({args}): {err}", file=sys.stderr, flush=True)
            return False, err
        if fn == "summon":
            apply_window_size()
        app.processEvents()
        return True, _format_result(res)

    server = QTcpServer()
    if not server.listen(QHostAddress.SpecialAddress.LocalHost, 0):
        print("qt_host: could not listen on localhost", file=sys.stderr)
        return 1

    port_file = shell_dir / ".qt-ipc-port"
    tmp_port = shell_dir / ".qt-ipc-port.tmp"
    tmp_port.write_text(str(server.serverPort()), encoding="utf-8")
    os.replace(tmp_port, port_file)

    sockets = []

    def on_new():
        sock = server.nextPendingConnection()
        if sock is None:
            return
        buf = bytearray()
        sockets.append(sock)

        def on_ready():
            buf.extend(bytes(sock.readAll()))
            while b"\n" in buf:
                line, _, rest = buf.partition(b"\n")
                buf[:] = rest
                try:
                    req = json.loads(line.decode("utf-8"))
                    ok, out = invoke(str(req.get("fn", "")), list(req.get("args") or []))
                    resp = {"ok": ok, "out": out} if ok else {"ok": False, "err": out}
                except Exception as exc:  # noqa: BLE001
                    resp = {"ok": False, "err": repr(exc)}
                sock.write((json.dumps(resp) + "\n").encode("utf-8"))
                sock.flush()

        def on_disc():
            if sock in sockets:
                sockets.remove(sock)
            sock.deleteLater()

        sock.readyRead.connect(on_ready)
        sock.disconnected.connect(on_disc)

    server.newConnection.connect(on_new)
    code = app.exec()
    server.close()
    del roots
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
