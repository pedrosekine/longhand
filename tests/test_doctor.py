"""Health check (`tools/doctor`): reports missing config/vault as failures and
a healthy throwaway setup as ok; names the program each configured model
route starts (Antigravity's is `agy`); on Omarchy the shell's plugins, on
Windows the Start menu entry and the session's start in their place.

Run: python3 tests/test_doctor.py
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCTOR = ROOT / "tools" / "doctor"
WINDOWS = os.name == "nt"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-doctor-"))
    cfg_dir = tmp / "config"
    state_dir = tmp / "state"
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    for name, rel in (
        ("pomo", "cli/pomo"),
        ("longhand-agent", "agent/longhand-agent"),
        ("longhand-check", "cli/longhand-check"),
        ("longhand-read", "cli/longhand-read"),
        ("longhand", "windows/longhand_host.py"),
        ("agy", ""),
    ):
        if WINDOWS:
            # pip's .exe launchers stand where Linux has links: a .cmd is
            # found by its name the same way.
            (bin_dir / f"{name}.cmd").write_text(f"@echo {name}\n")
        elif rel:
            (bin_dir / name).symlink_to(ROOT / rel)
        else:
            (bin_dir / name).write_text("#!/bin/sh\n")
            (bin_dir / name).chmod(0o755)

    base_env = dict(
        os.environ,
        XDG_CONFIG_HOME=str(cfg_dir),
        XDG_STATE_HOME=str(state_dir),
        PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        # Windows: the Start menu under a throwaway APPDATA, the session's
        # start read from a key nothing writes.
        APPDATA=str(tmp / "appdata"),
        LONGHAND_RUN_KEY="Software\\LonghandDoctorTest\\NoSuchRun",
    )
    base_env.pop("LONGHAND_CONFIG", None)

    # 1. Missing config.json → fails with actionable message.
    r1 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
    check(r1.returncode == 1 and "FAIL config.json" in r1.stdout, f"missing config fails cleanly ({r1.returncode})")

    # 2. Config pointing at non-existent vault → fails on vault.
    cfg_path = cfg_dir / "longhand" / "config.json"
    cfg_path.parent.mkdir(parents=True)
    cfg_path.write_text(json.dumps({
        "vault": str(tmp / "no-such-vault"),
        "daily": {"dir": "Daily", "format": "YYYY-MM-DD", "template": "agents/longhand/templates/daily"},
        "agentDir": "agents/longhand",
    }))
    r2 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
    check(r2.returncode == 1 and "FAIL vault" in r2.stdout, "missing vault folder fails cleanly")

    # 3. Healthy vault + daily folder + template → passes (exit 0).
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    (vault / "agents" / "longhand" / "templates").mkdir(parents=True)
    (vault / "agents" / "longhand" / "templates" / "daily.md").write_text("[[agents/longhand/daily/{{date}}|agent]]\n\n")
    cfg_path.write_text(json.dumps({
        "vault": str(vault),
        "daily": {"dir": "Daily", "format": "YYYY-MM-DD", "template": "agents/longhand/templates/daily"},
        "agentDir": "agents/longhand",
    }))
    r3 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
    check(r3.returncode == 0 and "ok   vault" in r3.stdout and "ok   daily template" in r3.stdout,
          f"healthy setup exits 0 ({r3.stdout.strip()})")

    # Each configured route by the program the agent starts: Antigravity's
    # is `agy` (the doctor looked for `antigravity`, which nobody has).
    cfg_path.write_text(json.dumps({
        "vault": str(vault), "daily": {"dir": "Daily"}, "agentDir": "agents/longhand",
        "model": "antigravity/gemini-3-pro", "fallbackModel": "codex/gpt-5", "codex": str(tmp / "no-such-codex.exe"),
    }))
    r6 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
    agy = [l for l in r6.stdout.splitlines() if "model route (agy)" in l]
    check(bool(agy) and agy[0].startswith("ok") and str(bin_dir) in agy[0], f"antigravity/ is agy, found ({agy})")
    codex = [l for l in r6.stdout.splitlines() if "model route (codex)" in l]
    check(bool(codex) and codex[0].startswith("WARN") and "no-such-codex" in codex[0] and "fallbackModel" in codex[0],
          f"the fallback's program, by the path the config gives it ({codex})")

    if WINDOWS:
        lines = r3.stdout.splitlines()
        check(any(l.startswith("ok") and "page (longhand)" in l for l in lines), "Windows: the page's host is found")
        check(any(l.startswith("WARN") and "start menu" in l and "longhand install" in l for l in lines),
              "Windows: no Start menu entry is named, with what makes one")
        check(any(l.startswith("WARN") and "with the session" in l for l in lines),
              "Windows: not started with the session is named")
        check(not any("omarchy plugins" in l or "shell.json" in l for l in lines),
              "Windows: Omarchy's plugins are not asked for")
        lnk = tmp / "appdata" / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Longhand.lnk"
        lnk.parent.mkdir(parents=True)
        lnk.write_bytes(b"")
        r7 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
        check(any(l.startswith("ok") and "start menu" in l for l in r7.stdout.splitlines()),
              "Windows: …and an entry there is ok")
        print("PASS" if failures == 0 else f"{failures} FAILED")
        return 1 if failures else 0

    # 4. shell.json: a plugin counts as on in plugins[] or as a widget in the
    # bar's layout (2026-11-20: the timer and the deadlines, bar widgets only,
    # were reported as not enabled).
    shell = cfg_dir / "omarchy" / "shell.json"
    shell.parent.mkdir(parents=True)
    shell.write_text(json.dumps({"plugins": [{"id": "longhand.page"}],
                                 "bar": {"layout": {"right": [{"id": "longhand.deadline"}, {"id": "longhand.pomo"}]}}}))
    r4 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
    check("ok   shell.json" in r4.stdout, f"bar widgets count as enabled ({[l for l in r4.stdout.splitlines() if 'shell.json' in l]})")
    shell.write_text(json.dumps({"plugins": [{"id": "longhand.page"}], "bar": {"layout": {"right": [{"id": "longhand.pomo"}]}}}))
    r5 = subprocess.run([sys.executable, str(DOCTOR)], env=base_env, capture_output=True, text=True)
    check("WARN shell.json" in r5.stdout and "longhand.deadline" in r5.stdout and "longhand.pomo" not in
          next(l for l in r5.stdout.splitlines() if "shell.json" in l), "…and one in neither is still named")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
