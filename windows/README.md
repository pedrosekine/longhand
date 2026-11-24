# Longhand on Windows

A host that stands in for `omarchy-shell`, so `plugin-page/` loads on Windows
with nothing in it changed. Started 2026-11-23 as a spike to answer one
question: does `Page.qml` load, draw and take keys under a shim? It does
(`first-run.png`, the page as a window; `overlay.png`, over everything).

Nothing here is used on Omarchy. Outside `windows/`: `cli/pomo.py` (the bash
`pomo`'s twin), `agent/winproc.py` (stopping a run), `tests/windows/`, and
the few lines in the agent and the tests that took Linux for granted, each
the same on Linux.

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
.venv\Scripts\longhand                                    # today's note as a window: your own ~/.config/longhand/config.json
.venv\Scripts\longhand --overlay                          # the page over everything (again: away)
.venv\Scripts\longhand --tray                             # in the tray only, nothing opened
.venv\Scripts\longhand quit
```

Longhand stays by the clock once started: closing the page's window puts
the page away, and Quit in the tray's menu ends it. One runs at a time; a
second `longhand` tells the first what was asked (`summon` and `toggle` take
the payload `omarchy-shell shell summon longhand.page` takes, or a bare
`alongside`).

The tray is the bar's two widgets as one icon: its tip and its menu say the
timer and the next deadline (from `plugin/Service.qml` and
`plugin-deadline/Service.qml`, loaded as they are), a click is today's
note, the menu starts, pauses, skips and resets the timer, and a session
that runs out is said there, as `notify-send` says it on Omarchy.

From anywhere, as Hyprland's keys with Win for Super (`hotkeys.py`):

| | |
|---|---|
| `Win+Alt+\` | the page as a window |
| `Win+Alt+=` | the page over everything, and away |
| `Win+Alt+P` | the timer: start, pause, resume |
| `Win+Alt+N` | the timer: on to the next phase |

`~/.config/longhand/windows-keys.json` moves one (`{"page": "Win+F9"}`) or,
with `""`, leaves it without a key. A key must hold Win, and one Windows or
another program has is not taken: it is said on stderr.

What the agent's extras call, and some tests: `gitleaks` (without it the
agent shares no passage: it cannot check one for secrets), poppler's
`pdftotext` (papers), and `node` (two tests compare the JS with the Python).

```powershell
winget install Gitleaks.Gitleaks
winget install oschwartz10612.Poppler
winget install OpenJS.NodeJS.LTS
```

## Your own vault

`%USERPROFILE%\.config\longhand\config.json`, as `config.example.json`, with
two things Windows asks for: the vault written with `/`
(`"C:/Users/you/your-vault"`), and a `font` and `codeFont` Windows has
(`Segoe UI Variable Text`, `Cascadia Mono`), since it has none of the faces
the page looks for. Then `longhand-agent install`, which puts the agent's
four prompts in `~/.config/opencode/agent` and writes nothing into a vault
that already has its folders.

What stays with a machine does not come with a synced vault: `settings.json`
beside the config (the horizon, how far the agent may go, calendars, the
folders it may search) and the state in `~/.local/state/longhand`. Without
a horizon of its own a machine falls back to the first day the agent has a
record of, which is the same day everywhere.

Set up on 2026-11-24 against a vault Syncthing shares with an Omarchy
machine: `install`, `horizon`, `dated` and `documents` read it as they
should, nothing in the vault changed and nothing was sent. The page has not
been opened on it by the checks: opening it is the day's first pass and
plan, and those are the person's to start.

`python windows\longhand_host.py --sandbox DIR --check out.json --shot out.png`
types into the note as a keyboard would, saves, reads the file back, writes
into it from outside, writes a box with a date and waits for it in the
store, and says what the page did.

## With a real model

Tried on 2026-11-24 with Claude Code 2.1.330 (`"model": "claude-code/sonnet"`)
on its own sign-in, in a throwaway vault whose note held a private block
with a marker in it (`agent-reply.png`):

- `longhand-agent run --trigger open` answered in six seconds, into
  `agents/longhand/daily/`; the note was the same file, byte for byte.
- The marker was in none of it: not the payload log, not the events, not
  Claude Code's own transcript. Claude Code said it offered no tools and no
  MCP servers, and attached the six things it may and nothing else.
- From the page: a question written, `Ctrl+Enter`, and its answer beside it
  fifteen seconds on (behind the day's opening pass and plan); `Ctrl+Enter`
  again opens the conversation.
- A second message stopped midway ended in 0.2 s, the run logged as
  stopped, no Claude Code left running, the words back in the box.

`LONGHAND_HOST_TRACE=1` puts every process the page starts, and how it
ends, on the host's stderr with the second it happened.

Codex (`"model": "codex/gpt-6.2-sol"`, with `"codex"` naming
`codex-x86_64-pc-windows-msvc.exe` by its whole path: the `codex` on PATH is
a `.cmd`, which is not started by name) was tried the same day, on a real
vault first and it went wrong twice, both Windows' doing:

- Every run was dropped by Longhand's own check and answered by the
  fallback. Python on Windows writes `\r\n` for every `\n` of a file or a
  pipe opened as text; Codex kept its instructions and the person's words
  as it got them, and the check, holding them against what Longhand had
  meant to send, found neither the same. Codex had carried nothing it
  should not and called no tool. The same `\r\n` was in every file the
  agent wrote into the vault — one shared with Linux machines — and in the
  installed prompts, whose fingerprint was therefore not Linux's.
  `pyshim/longhand_lf.py` makes `\n` the line ending of what Longhand's
  Python writes and sends; `tests/test_line_endings.py` holds it.
- The plan's run ended as "Claude Code exited 129". Opened from
  `longhand.exe` the host is `pythonw.exe`, the agent it started had no
  console, and each program the agent started got a console window of its
  own, on screen, the run ending with the window. The host now starts its
  scripts with `python.exe`, which Qt gives a console without a window
  (`qs_io.python`).

After both: one opening pass through Codex in a throwaway vault, on the
sign-in made for Longhand (`CODEX_HOME` as the README says), answered and
passed the check, the private marker in neither the payload log nor
Codex's session file, no `\r` in anything written.

opencode and Antigravity are installed here and not tried.

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
| `\n` as the line ending of what is written and sent | `pyshim/longhand_lf.py`, loaded at start |
| `Qt.openUrlExternally("file://" + path)` with a path from `/` | `file_urls.py`: `file://C:/…` (and its unparseable spellings) opened as the file on that drive |
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
  node installed: 70 files pass in four to eight minutes, 5 are passed over as
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
- The bar's two popups (the timer's, the deadlines') are not here: the tray
  says both and its menu works the timer, but a deadline is ticked in the
  page. The keys sheet still lists Hyprland's six as none: the global keys
  are moved in `windows-keys.json`, not from the sheet.
- No Start menu entry and nothing starts Longhand with the session; the
  programs the agent's extras call are not installed for you.
- In the tray with the page loaded and nothing shown, the host holds about
  150 MB.
- Borders are flat (no gradient ring); the page's prose face is named in the
  sandbox config (`Segoe UI Variable Text`), since Windows has none of the
  faces the page looks for.
