# Longhand on Windows

A host that stands in for `omarchy-shell`, so `plugin-page/` loads on Windows
with one thing in it changed (below). Started 2026-11-23 as a spike to answer one
question: does `Page.qml` load, draw and take keys under a shim? It does
(`first-run.png`, the page as a window; `overlay.png`, over everything).

Nothing here is used on Omarchy. Outside `windows/`: `cli/pomo.py` (the bash
`pomo`'s twin), `agent/winproc.py` (stopping a run), `tests/windows/`, and
the few lines in the agent and the tests that took Linux for granted, each
the same on Linux. In `plugin-page/`, one: a vault file's `file://` URL is
built by `Links.fileUrl`, which writes a drive's path as `file:///C:/…`.
The page wrote `file://C%3A/…`, which Qt cannot parse, so no PDF opened in
the page's reader (a picture in a note had the same URL; not looked at on
screen); a path from `/` gives the
same URL as before (`tests/tst_links.qml`).

## Install and run

Python 3.13, and Git for Windows for the page's few `sh`/`find` calls. From
the repo, into a Python of Longhand's own:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -e windows
```

That brings PySide6 (6.12, the Qt the page is written for) and makes the
commands beside `python.exe`, where Windows can start them by name:
`pomo.exe`, `longhand-agent.exe`, `longhand-check.exe`, `longhand-read.exe`,
`longhand-doctor.exe` (`longhand_launch.py`), and `longhand.exe`, the page. Each runs the script
in the repo; nothing is copied, so a pull is the update. The host puts that
folder on its children's PATH; for a terminal, put it on yours.

```powershell
.venv\Scripts\longhand --sandbox $env:TEMP\longhand-try   # a throwaway vault
.venv\Scripts\longhand                                    # today's note as a window: your own ~/.config/longhand/config.json
.venv\Scripts\longhand --overlay                          # the page over everything (again: away)
.venv\Scripts\longhand --tray                             # in the tray only, nothing opened
.venv\Scripts\longhand quit
```

```powershell
.venv\Scripts\longhand install      # in the Start menu, and started with the session (in the tray)
.venv\Scripts\longhand uninstall
.venv\Scripts\longhand-doctor      # what is there and what is missing (tools/doctor), read-only
```

`longhand-doctor` looks over the config, the vault, the commands, the
program of each model the config names (`model`, `fallbackModel`,
`planModel`; `"codex"` and the like when the config gives a path), the
Start menu entry and the session's start, and the optional tools: pandoc
and xelatex (the export), poppler (`pdftotext`, `pdfinfo`, `pdftoppm`;
it says so when xpdf's `pdftotext`, which Git's shell carries, is found
first), gitleaks, tesseract and qpdf (reading a scan).

`install` (`shortcuts.py`) is the desktop entry and the shell's start of the
plugins, as Windows has them, for the person alone: a shortcut, Longhand, in
the Start menu's Programs, which opens today's note as a window; its icon,
the launcher's seal on its tile, drawn from `launcher/longhand.svg` at eight
sizes into `~/.local/state/longhand/icon/longhand.ico` (a derivative, made
where it is used: `docs/brand/README.md`); and `longhand --tray` under the
person's Run key (`--no-autostart` leaves that out). The shortcut carries
the name the running Longhand gives itself to Windows, so the taskbar shows
one button for both, and pinning it pins Longhand, not Python.

Longhand stays by the clock once started: closing the page's window puts
the page away, and Quit in the tray's menu ends it. One runs at a time; a
second `longhand` tells the first what was asked (`summon` and `toggle` take
the payload `omarchy-shell shell summon longhand.page` takes, or a bare
`alongside`).

The tray is the bar's three widgets as one icon: its tip and its menu say
the timer, the next deadline and — as the page glyph turns urgent on the
bar — a reply waiting that has not been read and what the agent proposes
(`proposals.json`), in words, never on the seal (`docs/brand/README.md`:
the seal is no status light). A click is today's note, the menu starts,
pauses, skips and resets the timer, and a session that runs out is said
there: `pomo` says it as it says it to `notify-send` on Omarchy, and the
running Longhand takes it (`notify.py`); with no Longhand running, a
Windows toast says it. The seal is drawn in Windows' colours, the tile in
the apps' ground and the seal in the accent, as `tools/theme_icon.py`
draws the Omarchy launcher's in the theme's, and follows a change of
either at once.

The widgets themselves are loaded as they are (`plugin/Panel.qml`,
`plugin-deadline/Panel.qml`), and so are their popups: the timer's, where a
length is typed as on a microwave and the day's sessions are counted
(`timer-popup.png`), and the deadlines', where one is ticked, graded,
hidden, cancelled or opened on its line in the note (`deadlines-popup.png`).
Each opens as a small window in the corner by the clock, from the tray's
menu (Timer…, and the line of the next deadline), the tray's middle button
(the timer's), a global key, or `longhand timer` / `longhand deadlines`.
The keys in them are the bar's: arrows or `h j k l`, Enter, Tab from one to
the other, Esc to put it away; clicking another window puts it away too.
What the shell gives a widget for its popup — `Panel`, `KeyboardPanel`,
`PanelKeyCatcher`, `CursorSurface`, the buttons and the switch — has
stand-ins in `shim/qs/Ui/`; a button's picture is Windows' own for the same
thing (`Glyphs.js`), since Windows has no Nerd Font. Where a widget asks
the bar for its colours and face, `Main.qml` answers with Windows'.

From anywhere, as Hyprland's keys with Win for Super (`hotkeys.py`):

| | |
|---|---|
| `Win+Alt+\` | the page as a window |
| `Win+Alt+=` | the page over everything, and away |
| `Win+Alt+P` | the timer: start, pause, resume |
| `Win+Alt+N` | the timer: on to the next phase |
| `Win+Alt+O` | the timer's popup |
| `Win+Alt+D` | the deadlines' popup |

They move in the page's keys sheet (`Ctrl+/`), as Hyprland's do on Omarchy:
Enter on one, then the new key. The sheet asks `hyprkeys.py`; here
`winkeys.py` answers in its words and writes
`~/.config/longhand/windows-keys.json`, which the running Longhand watches
and takes at once (by hand too: `{"page": "Win+F9"}`, several as a list,
`""` for none). While the sheet waits for a key, Longhand lets go of its
own, so the key reaches the sheet (Hyprland's submap, here). A key must
hold Win, and one Windows or another program has is refused, saying so.
The agent's manual says these keys, as Windows writes them.

What the agent's extras call, and some tests: `gitleaks` (without it the
agent shares no passage: it cannot check one for secrets), poppler's
`pdftotext` (papers), and `node` (two tests compare the JS with the Python).

```powershell
winget install Gitleaks.Gitleaks
winget install oschwartz10612.Poppler
winget install OpenJS.NodeJS.LTS
```

Exporting a note as a PDF (`Ctrl+Shift+E` in the page) takes pandoc and a
xelatex; MiKTeX's, told to fetch the LaTeX packages it lacks by itself
(otherwise it asks in a window, and an export from the page waits on it):

```powershell
winget install JohnMacFarlane.Pandoc
winget install MiKTeX.MiKTeX
initexmf --set-config-value="[MPM]AutoInstall=1"
```

The first export fetches those packages and takes a minute or two; after
that, seconds. With no `font` in the export's config it is set in Segoe UI
(the variable Segoe UI Variable is one xelatex cannot load), and the look
`omarchy` ("your Windows colours" in the page) is Windows' own light or
dark, headings in the accent as Windows sets text in it
(`palette.theme`), checked on both 2026-11-24.

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
store, opens a PDF it writes into the vault (a folder and a name with spaces
and a `#`) in the page's reader, and says what the page did. In a fresh
sandbox the page's first line says the agent could not run, "no note for"
today: the day's pass starts before the check has typed the note.

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
| `hyprkeys.py` (the keys sheet's six keys from anywhere) | `winkeys.py`, in its words, over `windows-keys.json` and `hotkeys.py` |
| `hyprctl eval` — raise the window, put the pointer, the keys sheet's submap | `compositor.py`, answered inside the host (`qs_io.INSIDE`): Qt's raise and activate, `QCursor.setPos`, the global keys let go |
| a theme's `colors.toml` (red, yellow, green, blue…) | `palette.py`: Windows 11's colours for each role, light or dark, under that path where no theme is |
| `notify-send`, `pw-play --volume=0.6`, `omarchy-shell notifications isDnd` | `notify.py` (the tray, else a toast), `play_sound.py` (scaled to 0.6, not under Do Not Disturb) |
| a layer on the focused monitor; a window placed by Hyprland | `PanelWindow` on the screen the pointer is on; `FloatingWindow` where it was left (`windows.json` in the state folder) |
| `~/.local/bin` links and shebangs | `.exe` launchers from `pyproject.toml`, through `longhand_launch.py` |
| UTF-8 as the system's encoding | Python's UTF-8 mode, switched on by the host and the launchers |
| `\n` as the line ending of what is written and sent | `pyshim/longhand_lf.py`, loaded at start |
| `os.replace` over a file another process is reading (always works on Linux) | `pyshim/longhand_replace.py`, loaded at start: Windows refuses it while the file is open, so it tries again for about three seconds; the host itself tries only briefly, so the window never freezes |
| `Qt.openUrlExternally("file://" + path)` with a path from `/` | `file_urls.py`: `file://C:/…` (and its unparseable spellings) opened as the file on that drive |
| `"file://" + path` given to the page's own PDF reader and pictures | `Links.fileUrl` in `plugin-page/`: no host can reach a URL Qt fails to parse before it loads |
| `fcntl.flock` | `pyshim/fcntl.py` |
| a process group and SIGTERM, to stop a model's run | a job and a named event: `agent/winproc.py` |

## Known, not done

- First open: the page asks the note to take the keys before the note has
  rows, and a sheet's hidden `focus: true` key catcher keeps them. The host
  gives them to the note once it has loaded (`Main.qml`, `keysOwed`).
  Whether Omarchy has the same order on its first open is not checked; if it
  does, the place to fix it is `NoteEditor.focusNote`.
- `pomo` is `cli/pomo.py` here: the bash one command for command
  (`tests/test_pomo_port.py` runs both and compares).
- The tests run through the runner (`python tests\run_all.py`, or
  `… run_all.py check plan`), which gives each file what Linux gives it for
  nothing (`tests/windows/`). On 2026-11-24, with gitleaks, poppler and
  node installed: 73 files pass in four to eight minutes, 5 are passed over as
  Omarchy's own (named, with the reason), 1 fails: cursors, which wants
  PyQt6 (`pip install PyQt6` into the same Python, and it passes: on a
  Windows machine of GitHub's, where the workflow installs it, all 74 do).
  One check of projects fails on a Monday on any system: it asks
  for yesterday's week and expects a file touched today in it.
- A clone needs its text files with `\n`: a prompt's fingerprint is taken
  from its bytes, and bash reads `\r` as part of a word. `.gitattributes`
  says so (`* text=auto eol=lf`), whatever git's own setting on the machine;
  found by the suite's first run on GitHub, where git hands out `\r\n`.
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
- The bar's two popups are driven by the host itself on a throwaway vault
  (`longhand_host.py --sandbox DIR --check OUT.json --popups`,
  `popup_check.py`; `tests/test_tray_popups.py` reads what it says): opened
  in the corner, a length typed and started, Tab to the deadlines', one
  ticked in the store, Esc. Seen drawn on the screen that way. Not yet
  opened by a hand from the tray's menu or a key pressed: Windows gives the
  keyboard to a window only when its program is the one in front, which a
  click on the tray or a global key makes it, and which the check has to
  ask for.
- In the timer's popup the row "Auto-start breaks & focus" is not drawn. It
  is a `CursorSurface` in a `Column` with `Layout.fillWidth` and no width
  of its own, so its width is 0 and the column passes over it. The shell's
  own surface is a plain rectangle too, so the row is likely missing on
  Omarchy as well: not looked at there. The keys still reach it.
- Do Not Disturb is read from Windows' Focus assist profile (the shell's
  own toggle publishes it; `play_sound.silenced`), an undocumented state
  that Windows 11 still keeps: read as off on 2026-11-24, not yet seen on.
- The programs the agent's extras call are not installed for you. The
  Start menu's entry and the start with the session are made by
  `longhand install` and read back as Windows holds them
  (`tests/test_start_menu.py`). Started from the shortcut, the taskbar
  shows the seal (seen 2026-11-24); before Longhand gave itself a name
  Windows filed its window under IDLE, the shortcut that points at
  `pythonw.exe`, and showed that icon. How it looks in the Start menu
  and in Settings → Apps → Startup has not been looked at. The Start menu's
  icon keeps the launcher's own colours (Windows caches a shortcut's icon);
  the tray's follows Windows' light, dark and accent.
- In the tray with the page loaded and nothing shown, the host holds about
  150 MB.
- Borders are flat: the gradient ring is a Hyprland theme's active border
  (its `hyprland.lua`), and Windows has none to give; the accent stands in,
  as it does on Omarchy for a theme that names none. The title bar is dark
  in dark mode by Qt's own doing (checked 2026-11-24).
- The page's prose face is named in the sandbox config
  (`Segoe UI Variable Text`), since Windows has none of the faces the page
  looks for.
