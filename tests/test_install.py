"""`tools/install --tools` on Windows: after winget, what it installed is
found though this process's PATH predates it (MiKTeX's initexmf), and what
cannot be found or run is said, not a crash. winget, the registry's PATH
and MiKTeX are played by the test: nothing is installed, no PATH is read
or written. Elsewhere there is nothing to test, and the file says so.

Run: python tests\\run_all.py install
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def load_install():
    loader = importlib.machinery.SourceFileLoader("longhand_tools_install", str(ROOT / "tools" / "install"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def main() -> int:
    if os.name != "nt":
        print("skip: winget and MiKTeX's folders are Windows' (on Omarchy: tools/install, no --tools)")
        return 0
    sys.path.insert(0, str(ROOT / "windows"))
    import shortcuts
    install = load_install()

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="install-test-"))
    tools = tmp / "winget-tools"          # where winget stands, on this process's PATH
    tools.mkdir()
    (tools / "winget.exe").write_bytes(b"")
    miktex = tmp / "local" / "Programs" / "MiKTeX" / "miktex" / "bin" / "x64"
    registry: list[str] = []               # the PATH a new terminal would get
    calls: list[list[str]] = []

    def fake_run(cmd, **kw):
        calls.append([str(c) for c in cmd])
        if pathlib.Path(cmd[0]).stem == "winget" and "MiKTeX.MiKTeX" in cmd:
            # As MiKTeX's installer does: the program, and its folder on the
            # registry's PATH only.
            miktex.mkdir(parents=True, exist_ok=True)
            (miktex / "initexmf.exe").write_bytes(b"")
            registry.append(str(miktex))

    def plain(cmd, **kw):
        calls.append([str(c) for c in cmd])

    install.run = fake_run
    shortcuts.new_terminal_path = lambda: list(registry)
    # MiKTeX's own folders, the test's: nothing there until "installed".
    os.environ["LOCALAPPDATA"] = str(tmp / "local")
    os.environ["ProgramFiles"] = str(tmp / "programs")

    def tools_run(packages, path):
        calls.clear()
        env = {"PATH": path}
        os.environ["PATH"] = path
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                install.install_tools(packages, env)
            return out.getvalue(), env, None
        except Exception as e:  # noqa: BLE001 — what the test is about
            return out.getvalue(), env, e

    # 1. Fresh: MiKTeX installed by winget, its folder only in the registry.
    said, env, err = tools_run(["JohnMacFarlane.Pandoc", "MiKTeX.MiKTeX"], str(tools))
    check(err is None, f"winget then initexmf in one run does not crash ({err!r})")
    check([pathlib.Path(c[0]).stem for c in calls] == ["winget", "winget", "initexmf"],
          f"each package by winget, then initexmf ({[c[:4] for c in calls]})")
    check(calls and [os.path.normcase(calls[-1][0]), *calls[-1][1:]]
          == [os.path.normcase(miktex / "initexmf.exe"), "--set-config-value=[MPM]AutoInstall=1"],
          "initexmf is the one MiKTeX just installed, told to fetch packages by itself")
    check(str(miktex) in env["PATH"].split(os.pathsep) and str(miktex) in os.environ["PATH"].split(os.pathsep),
          "the registry's new folder is on this process's PATH, and its children's")
    check(env["PATH"].split(os.pathsep)[0] == str(tools), "…at the end: what was there first stays first")
    check("open a new terminal" in said, "it says a new terminal has them")

    # 2. Not on the registry's PATH (it was not written yet): MiKTeX's own folder.
    registry.clear()
    install.run = plain
    said, env, err = tools_run(["MiKTeX.MiKTeX"], str(tools))
    check(err is None and calls[-1][0] == str(miktex / "initexmf.exe"),
          f"initexmf found in MiKTeX's folder for the person, though not on PATH ({calls[-1:]})")

    # 3. Nowhere (the install failed, or went elsewhere): said, by hand.
    (miktex / "initexmf.exe").unlink()
    said, env, err = tools_run(["MiKTeX.MiKTeX"], str(tools))
    check(err is None, f"no initexmf anywhere: no crash ({err!r})")
    check([pathlib.Path(c[0]).stem for c in calls] == ["winget"], "…and nothing started in its name")
    check("initexmf --set-config-value=[MPM]AutoInstall=1" in said and "new terminal" in said,
          "…and it says what to run, in a new terminal")

    # 4. For all users: MiKTeX under Program Files.
    allusers = tmp / "programs" / "MiKTeX" / "miktex" / "bin" / "x64"
    allusers.mkdir(parents=True)
    (allusers / "initexmf.exe").write_bytes(b"")
    check(install.find_initexmf(str(tools)) == str(allusers / "initexmf.exe"), "initexmf found under Program Files")

    # 5. A failure to start it (a broken install) is said too.
    def refusing(cmd, **kw):
        calls.append([str(c) for c in cmd])
        if pathlib.Path(cmd[0]).stem == "initexmf":
            raise OSError(193, "%1 is not a valid Win32 application")
    install.run = refusing
    said, env, err = tools_run(["MiKTeX.MiKTeX"], str(tools))
    check(err is None and "initexmf --set-config-value" in said, f"initexmf that cannot start: said, no crash ({err!r})")

    # 6. No winget at all: nothing run, everything said.
    install.run = fake_run
    said, env, err = tools_run(["Gitleaks.Gitleaks", "MiKTeX.MiKTeX"], str(tmp / "nothing-here"))
    check(err is None and not calls, f"no winget: nothing started, no crash ({err!r})")
    check("winget install Gitleaks.Gitleaks" in said and "winget install MiKTeX.MiKTeX" in said
          and "initexmf --set-config-value" in said, "…and every command is said, to run by hand")

    print(f"\n{failures} failure(s)")
    return failures


if __name__ == "__main__":
    sys.exit(main())
