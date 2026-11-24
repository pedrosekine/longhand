# Longhand on Windows — spike

A host that stands in for `omarchy-shell`, so `plugin-page/` loads on Windows
with nothing in it changed. Started 2026-11-23 to answer one question: does
`Page.qml` load, draw and take keys under a shim? It does (`first-run.png`).

Nothing here is used on Omarchy, and nothing outside `windows/` was touched.

## Install and run

Python 3.13, and Git for Windows for the page's few `sh`/`find` calls. From
the repo, into a Python of Longhand's own:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -e windows
```

That brings PySide6 (6.12, the Qt the page is written for) and makes the
commands beside `python.exe`, where Windows can start them by name:
`pomo.exe`, `longhand-agent.exe`, `longhand-check.exe`, `longhand-read.exe`
(`longhand_launch.py`), and `longhand.exe`, the page. Each runs the script
in the repo; nothing is copied, so a pull is the update. The host puts that
folder on its children's PATH; for a terminal, put it on yours.

```powershell
.venv\Scripts\longhand --sandbox $env:TEMP\longhand-try   # a throwaway vault
.venv\Scripts\longhand                                    # your own ~/.config/longhand/config.json
.venv\Scripts\longhand --overlay                          # the unpinned shape
```

What the agent's extras call, and some tests: `gitleaks` (without it the
agent shares no passage: it cannot check one for secrets), poppler's
`pdftotext` (papers), and `node` (two tests compare the JS with the Python).

```powershell
winget install Gitleaks.Gitleaks
winget install oschwartz10612.Poppler
winget install OpenJS.NodeJS.LTS
```

`python windows\longhand_host.py --sandbox DIR --check out.json --shot out.png`
types into the note as a keyboard would, saves, reads the file back, writes
into it from outside, writes a box with a date and waits for it in the
store, and says what the page did.

## What stands in for what

| The page imports | Here |
|---|---|
| `Quickshell.Io` — `Process`, `StdioCollector`, `SplitParser`, `FileView`, `FileViewError` | `qs_io.py`, on QProcess and plain files |
| `Quickshell` — the singleton, `PanelWindow`, `FloatingWindow` | `shim/Quickshell/`, on Qt Quick's `Window` |
| `Quickshell.Wayland` — layer-shell names | `qs_wayland.py`: accepted, not acted on |
| `qs.Commons` — `Style`, `Color`, `Border`, `Util` | `shim/qs/Commons/`: Windows' light/dark and accent, live |
| `qs.Ui` — `BorderSurface`, `TextField`, `PanelToolTip` | `shim/qs/Ui/` |
| scripts by name or in `~/.local/bin` | `qs_io.resolve`: the repo's own, run by Python or Git's bash |
| `pomo` (bash, sed, awk, flock, GNU date) | `cli/pomo.py` |
| `~/.local/bin` links and shebangs | `.exe` launchers from `pyproject.toml`, through `longhand_launch.py` |
| UTF-8 as the system's encoding | Python's UTF-8 mode, switched on by the host and the launchers |
| `fcntl.flock` | `pyshim/fcntl.py` |
| a process group and SIGTERM, to stop a model's run | a job and a named event: `agent/winproc.py` |

## Known, not done

- First open: the page asks the note to take the keys before the note has
  rows, and a sheet's hidden `focus: true` key catcher keeps them. The host
  gives them to the note once it has loaded (`Main.qml`, `keysOwed`).
  Whether Omarchy has the same order on its first open is not checked; if it
  does, the place to fix it is `NoteEditor.focusNote`.
- `hyprctl` (pointer follows the pane, raise, key capture) has no stand-in.
- `pomo` is `cli/pomo.py` here: the bash one command for command
  (`tests/test_pomo_port.py` runs both and compares).
- The tests run through the runner (`python tests\run_all.py`, or
  `… run_all.py check plan`), which gives each file what Linux gives it for
  nothing (`tests/windows/`). On 2026-11-24, with gitleaks, poppler and
  node installed: 69 files pass in about four minutes, 5 are passed over as
  Omarchy's own (named, with the reason), 1 fails: cursors, which wants
  PyQt6. One check of projects fails on a Monday on any system: it asks
  for yesterday's week and expects a file touched today in it.
- Stopping a run: Windows has no process group and no SIGTERM a process
  can take and go on. The model's process is in a job, ended whole; the
  page's host asks the runner to stop through a named event, and the runner
  does what it does on SIGTERM (`agent/winproc.py`). What is not a runner is
  ended outright, tree and all — after three seconds when it has only just
  started, since a runner needs that long to say it listens.
- Two holes in what the agent keeps back, both Windows' alone, found by the
  suite and closed: gitleaks was told to report to `/dev/stdout`, failed,
  said nothing, and that read as "no secret found"; and a day before the
  agent's horizon was known by its folder as text, `human\Daily`, which
  never matched. A passage with a token, or a day the agent was never
  shown, would have been sent.
- A path inside the vault is written with `/` on every system
  (`.as_posix()`), and a day with no leading zero goes through `day_text`
  (`%-d` is Linux's): both were the agent's, and both are the same on Linux.
- A finished session's sound plays; there is no notification yet.
- No global key, no tray, no bar widgets; no Start menu entry, and the
  programs the agent's extras call (pandoc, poppler, tesseract) are not
  installed for you.
- Borders are flat (no gradient ring); the page's prose face is named in the
  sandbox config (`Segoe UI Variable Text`), since Windows has none of the
  faces the page looks for.
