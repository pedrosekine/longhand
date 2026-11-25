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

Found here, and fixed in `plugin-page/` for both: the first open after the
shell starts asks the note for the keys before it has been read, and the ask
was lost — a closed sheet's hidden key catcher kept them. On Omarchy the
overlay typed into hidden settings that way (the window shape was saved by a
second ask, made when Wayland maps it, after the read); here both shapes did,
and the host gave the note the keys itself (`keysOwed`, gone). Now
`NoteEditor.focusNote` owes the note the keys until its lines come, unless
something shown has been given them meanwhile (`tests/tst_editor.qml`; the
first check of `tests/page/run.py`).

## Install and run

Python 3.13. Git for Windows is no longer needed by the page: what it ran
through `sh` and `find` is done in Python (`page_fs.py`, `play_sound.py`);
where Git is installed, a script with a bash shebang still runs under its
bash. From the repo, into a Python of Longhand's own:

```powershell
python tools\install --vault C:/Users/you/your-vault   # all of it, as on Omarchy
python tools\install --tools                          # …and with winget, the optional tools it finds missing
```

`tools/install` makes the repo's `.venv` (or uses the virtual environment
it runs in), installs Longhand into it (`pip install -e windows`), writes
a config from `config.example.json` if there is none (`--vault` goes into
it), puts the commands on your PATH, puts Longhand in the Start menu and
starts it with the session (`longhand install`; `--no-path` and
`--no-autostart` leave those out), runs `longhand-agent install` once the
vault is there, and ends with the doctor. Run again, it changes nothing
that is already right. Open a new terminal afterwards: one already open
keeps the PATH it started with.

`--tools` installs with winget what the doctor found missing. winget
writes a program's folder into the registry's PATH only, so before
starting MiKTeX's `initexmf` (below) the install takes the registry's PATH
again, and looks in MiKTeX's own folders
(`%LOCALAPPDATA%\Programs\MiKTeX\miktex\bin\x64`, the same under
`%ProgramFiles%`); found nowhere, or with no winget, it says what to run by
hand (`tests/test_install.py`, with winget and the registry played).

By hand, the first of those is:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -e windows
```

That brings PySide6 (6.12, the Qt the page is written for) and makes the
commands beside `python.exe`: `pomo.exe`, `longhand-agent.exe`,
`longhand-check.exe`, `longhand-read.exe`, `longhand-doctor.exe`
(`longhand_launch.py`), and `longhand.exe`, the page. Each runs the
script in the repo, so a pull is the update. The host puts that folder on
its children's PATH. For a terminal, `longhand install` does what
Omarchy's `tools/install` does with `~/.local/bin`: it copies the six
launchers into `%USERPROFILE%\.local\bin` and adds that folder at the end
of your PATH (`HKCU\Environment`, the value's type kept, never twice,
Windows told of the change). Not `.venv\Scripts` itself, which would put
that Python's `python.exe`, `pip.exe` and `pyside6-*.exe` on your PATH as
well. A copied launcher holds the path of the `python.exe` it starts, so
it works from anywhere; a pull still needs nothing, a new `.venv` needs
`longhand install` again. `longhand uninstall` (or `install --no-path`)
takes the copies away, and the folder off PATH when nothing else is in it
(uv keeps its tools there too). `longhand-doctor` says whether a new
terminal finds each command by name.

```powershell
longhand --sandbox $env:TEMP\longhand-try   # a throwaway vault
longhand                                    # today's note as a window: your own ~/.config/longhand/config.json
longhand --overlay                          # the page over everything (again: away)
longhand --tray                             # in the tray only, nothing opened
longhand quit
```

```powershell
longhand install      # the commands on PATH, in the Start menu, and started with the session (in the tray)
longhand uninstall
longhand-doctor       # what is there and what is missing (tools/doctor), read-only
```

(Before `longhand install`, or with `--no-path`: `.venv\Scripts\longhand`
and the like.)

`longhand-doctor` looks over the config, the vault, the commands (and
whether a new terminal finds them by name), the
program of each model the config names (`model`, `fallbackModel`,
`planModel`; `"codex"` and the like when the config gives a path) and
whether it can run (opencode's agents installed, Antigravity signed in), the
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
the page away, and Quit in the tray's menu ends it, once the last save has
landed. Signing out, restarting or shutting down does the same: asked by
Windows whether the session may end, Longhand saves what is typed first
(`save_at_session_end` in `longhand_host.py`). One runs at a time; a
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

Beside the seal stand the bar's other two widgets, an icon each, as they
stand beside the page's glyph on Omarchy: the timer, saying the minutes
left (in the accent while a focus runs, faint paused or not started; a
click is its popup, the middle button starts or pauses it, its menu
skips and resets), and the deadlines, saying how far off the next one is
as the bar does (`4d`, `9h`, `!` once late, a tick when all are handed
in; a click is their popup). Their pictures are drawn as they change
(`host_api.tray_glyph`: an SVG, sharp at whatever size Windows asks).
Windows puts a new program's icons under the `^` arrow; one switch shows
all three: Settings → Personalization → Taskbar → Other system tray icons
→ Longhand (the three share it, as Windows keeps the setting by program).

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

A symbol is a character, not a place on a US keyboard: Windows is given the
key that types it on the keyboard layout in use (`VkKeyScanExW`), as
Hyprland reads a keysym through XKB. On a German keyboard `Win+Alt+=` is
Win+Alt+Shift+0 and `Win+Alt+\` is Win+AltGr+ß (AltGr is Ctrl+Alt to
Windows); on a French one `\` is AltGr+8, on a British one the key by the
left Shift. A symbol that needs Shift or AltGr is kept with them, since those
are the keys a person presses to type it with Win and Alt held, and the keys
the sheet hears; the sheet and the tray menu still say the symbol. Letters,
digits and F-keys are the same keys on every layout. A symbol the layout has
not got at all falls back to the US keyboard's key, and one only behind a
Kana shift is refused. The layout is the window in front's, asked every
second: switched to another, the keys are taken again where it types them
(only when that makes any of them another key).

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
the vault written with `/` (`"C:/Users/you/your-vault"`). `font` and
`codeFont` can stay empty: the page falls back to Windows' own faces
(`Segoe UI Variable Text`, `Cascadia Mono`) when none of Omarchy's is
installed. Then `longhand-agent install`, which puts the agent's
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
`codex-x86_64-pc-windows-msvc.exe` by its whole path: the `codex` on PATH was
a `.cmd`, which Windows does not start by name. The agent now finds a
`.cmd` on PATH itself (`_win_cmd`), so `"codex"` can be left out; naming
the `.exe` still skips cmd.exe in between) was tried the same day, on a real
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

opencode (2.3.2, winget) and Antigravity (`agy` 1.5.16, winget) were
tried the same evening, each in a throwaway vault of made-up notes with a
private callout holding a marker, `XDG_CONFIG_HOME` and `XDG_STATE_HOME`
in scratch folders, `longhand-agent install` run first:

- opencode, on its own sign-in (`~/.local/share/opencode`, which neither
  variable moves), the agent's own model (`opencode-go/deepseek-v4.1-flash`):
  `run --trigger open` answered into `agents/longhand/daily/`; a `chat` on a
  block answered on that block, and a second resumed the same session. On
  Windows opencode reads its config, agents included, from
  `$XDG_CONFIG_HOME/opencode` (else `~/.config/opencode`; not `%APPDATA%`;
  `opencode debug paths` says so), which is where `install` writes them;
  without them a run fails "Agent not found", it never falls back to an
  agent with tools.
- One thing was wrong, not Windows' own: the price of a run is asked of
  the session afterwards (`opencode session export`), and without
  `--standalone` opencode 2 asks its background service, starting one if
  none runs. Here another program's opencode held the service's port, so
  every export took 25 s to fail, and the ledger's tokens, which the run's
  events had, were overwritten with zeros. The export now runs standalone
  (1 s), and the events' tokens stand when the session cannot be asked
  (opencode 2.3 also stopped saying their total; it is the three added).
- Antigravity (`"model": "antigravity/gemini-3.8-flash#low"`): the opening
  pass (10 s), a chat (7 s) and its second turn (6 s, the same
  conversation resumed, Antigravity's "server restart" notice passed over
  as PR #27 meant) all answered. The sign-in is not a file: agy keeps it in
  the Credential Manager (`gemini:antigravity`; its log: "authenticated
  via keyring"), so the home Longhand gives it (`USERPROFILE`, `HOMEDRIVE`,
  `HOMEPATH` and `HOME` all pointed at `STATE_HOME/antigravity`) finds it
  from a fresh, empty folder. Nothing was written into the person's own
  `~/.gemini` or AppData.
- Neither note was touched (bytes and time), the marker was in no payload,
  event log or reply, and no fallback ran.

Not tried: Antigravity with no sign-in at all. Its print mode tries a
silent sign-in from the keyring and has an "authentication failed" error
for when that fails; whether it ends there or waits on a code was not
seen, as it would mean signing the person out. `longhand-doctor` now says
whether each route can run, not only that its program is there: for
opencode, whether Longhand's agents are where it reads them; on Windows
for Antigravity, whether the Credential Manager holds its sign-in (asked
by name, never read out).

## The page's live test, here

`tests/page/run.py`, the test that drives the page over IPC on Omarchy
(about a thousand checks), runs here too, over the host
(`tests/page/qt_host.py` loads `harness.qml` and the page in PySide6,
offscreen, and answers over a local socket what `quickshell ipc` answers
there):

```powershell
.venv\Scripts\python -X utf8 tests\page\run.py --host qt   # about 8 minutes here
.venv\Scripts\python -X utf8 tests\run_all.py page         # the same, through the runner
```

`PAGE_LOG=file` keeps what the page says, `LONGHAND_HOST_TRACE=1` adds
every process it starts, `PAGE_KEEP=1` leaves the throwaway vault and state
to read after a failure. GitHub runs it on every pull request beside the
offscreen suite (the workflow's Windows job, `page` half).

First run whole on 2026-11-24: 28 checks failed, and it stopped halfway.
What was found:

- In the host, two orders Quickshell keeps (asked on Omarchy) and the
  stand-in did not: a Process started again from its own output's
  `streamFinished` did not start (`qs_io.Process._end` still counted it
  running) — the page asks for its next deadline check that way, so a
  check was now and then dropped and the page waited eight seconds for
  it, and a bound line pasted back stayed cancelled; and `running =
  false`, a new command, `running = true` before the old process had
  ended dropped the new one — the page leaves Hyprland's submap that way.
  `tests/test_windows_shell.py` holds both.
- In the page: the second Enter that lets the page keep Hyprland's six
  keys was lost when it came while the sheet was still reading them (a
  Python started cold, most of a second here); now made when the read
  ends (`Page.qml`, `hyprNext`). And an exported PDF opened under its
  whole path in the header ("C:\Users\…\Downloads\Diary 1"): its name was
  cut at the last "/" only (`fileName`).
- In the agent: accepting a drop of a deadline with no line, the page
  cancels it, then records the accept; a list read in between settled it
  as moot (as one cancelled some other way is), and the accept that came
  after changed nothing. The page asks only while the deadline is open,
  so that accept now stands (`answer_proposal`;
  `tests/test_margin_cards.py`).
- In the test, the rest: the agent found the `opencode` installed on this
  machine rather than the test's stand-in (a name is looked up with
  PATHEXT here; the stand-in has no extension — it is now named by its
  path, and nothing it was asked reached a model); the host put
  `pyshim/` before the tests' own `sitecustomize` on its children's
  PYTHONPATH, so they could not start a `#!` stand-in; offscreen Qt had
  no fonts (the measure read 46 characters for 72; `QT_QPA_FONTDIR`); the
  test's runner did not listen for a stop, so the host waited three
  seconds before ending it; a note read at the instant the page renames
  a new copy over it is refused here, briefly; and checks that acted on
  a dashboard row or a card before it had caught up with the last edit,
  which a Linux machine does before the next IPC call.

Found after (2026-11-25): now and then the dashboard lacked a line just
written, on Omarchy too. Every listing saves the boxes' clocks
(`lifespan.py`), and the page runs several at once; each wrote one shared
`silence.json.tmp` and renamed it, and the second found it gone (or, here,
held: two writers failed 170 times in 300). That listing failed, and the
page read its failure as no tasks at all. Each process writes a copy of
its own now, and the documents' caches the same (`documents.py`);
`tests/test_lifespan.py` runs three listings side by side. Later the same
day the rest went the same way: the reader's acronyms, scan copies and
moved talks, the agent's week and project pages, exports and ledger
header; and the PDF search cache, which was written in place, is written
whole and renamed.

Not run here, and said so: the overlay (`--overlay`, as on Omarchy), a
scanned paper's read (magick, pdftoppm, tesseract, qpdf), and the PDF an
export writes, where pandoc and xelatex are not on PATH (as
`tests/test_export.py`).

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
| `notify-send`, `pw-play --volume=0.6`, `omarchy-shell notifications isDnd` | `notify.py` (the tray, else a toast), `play_sound.py` (scaled to 0.6, after 300 ms of silence for a sleeping sound chip to wake in, not under Do Not Disturb) |
| a layer on the focused monitor; a window placed by Hyprland | `PanelWindow` on the screen the pointer is on; `FloatingWindow` where it was left (`windows.json` in the state folder) |
| `~/.local/bin` links and shebangs | `.exe` launchers from `pyproject.toml`, through `longhand_launch.py` |
| UTF-8 as the system's encoding | Python's UTF-8 mode, switched on by the host and the launchers |
| `\n` as the line ending of what is written and sent | `pyshim/longhand_lf.py`, loaded at start |
| `os.replace` over a file another process is reading (always works on Linux) | `pyshim/longhand_replace.py`, loaded at start: Windows refuses it while the file is open, so it tries again for about three seconds; the host itself tries only briefly, so the window never freezes (the windows' places, the reader's files, the tray's pictures: a tray picture that still cannot be put in place leaves the icon showing what it showed, and the next change draws again). `longhand install`, in the host's process but with no window, tries the patient way over the Start menu's icon, which Explorer reads, and keeps the icon there if it never lets go |
| `Qt.openUrlExternally("file://" + path)` with a path from `/` | `file_urls.py`: `file://C:/…` (and its unparseable spellings) opened as the file on that drive |
| `"file://" + path` given to the page's own PDF reader and pictures | `Links.fileUrl` in `plugin-page/`: no host can reach a URL Qt fails to parse before it loads |
| `open(..., "a")` as `O_APPEND`: a line appended whole while other processes append (the ledger, feedback, conversation, deadlines, proposals, check-ins, usage) | `pyshim/longhand_append.py`, loaded at start: Windows' own is a seek and a write, and six writers at once kept 1998 lines of 2400; opened for appending only (`FILE_APPEND_DATA`), the system puts each write at the end |
| `fcntl.flock` | `pyshim/fcntl.py` |
| a process group and SIGTERM, to stop a model's run | a job and a named event: `agent/winproc.py` |

## Known, not done

- `pomo` is `cli/pomo.py` here: the bash one command for command
  (`tests/test_pomo_port.py` runs both and compares).
- The tests run through the runner (`python tests\run_all.py`, or
  `… run_all.py check plan`), which gives each file what Linux gives it for
  nothing (`tests/windows/`). On 2026-11-24, with gitleaks, poppler and
  node installed: 74 files pass in four to eight minutes, 5 are passed over as
  Omarchy's own (named, with the reason). `test_cursors` wanted PyQt6, which
  nothing here installs; it runs on PySide6, the host's own Qt, when PyQt6
  is not there (2026-11-25).
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
  ticked in the store, Esc; opened again, it goes when another window
  takes the keys. Seen drawn on the screen that way. Not yet opened by a
  hand from the tray: Windows gives the keyboard to a window only when its
  program may take the front, which a click on the tray or a global key
  lets it, and which the check has to ask for.
- Who may take the front (tried 2026-11-24 on the real screen, with
  another program in front and getting input every 300 ms, Windows'
  foreground lock on): a global key (one of the six, pressed as input)
  brought the popup to the front with the keys; so did `longhand timer`
  started by the program in front, with or without the
  `AllowSetForegroundWindow` the client gives first. Started by a program
  in the background, the popup came up over the others without the keys,
  and stayed: it closes only once it has had the keys and lost them, so a
  refused activation leaves it open (put it away the way it came, or click
  it and then elsewhere) instead of flashing.
- Put in the taskbar, the page's window comes back as it went down when a
  second `longhand`, `longhand summon`, the Start menu or Win+Alt+\ asks
  for it: maximized stays maximized (`compositor.come_forward`, which the
  page's raise and the host both use; before, it came back at its old
  size). Seen on the screen and in `tests/test_windows_shell.py`.
- The six keys on other keyboard layouts (2026-11-25): until then a symbol
  was a US keyboard's key, so on a German, Portuguese, British or French
  keyboard `Win+Alt+=` and `Win+Alt+\` were other keys than the ones
  printed. Now they are asked of the layout in use (above). Tested with
  what `VkKeyScanExW` answers on those layouts, written into
  `tests/test_windows_shell.py`, and against this machine's own (US):
  loading another layout to try it would touch the person's list of them.
  Not yet seen with a German keyboard in hand: that Qt hands the sheet
  `=` for Win+Alt+Shift+0 there (the sheet writes the symbol, without its
  Shift) is Qt's keymap, read but not watched.
- On two screens scaled differently (a laptop at 125%, a monitor at 150%),
  Windows shifts a window moved onto the other screen as the scale changes
  under it: the overlay landed 282 px off (2026-11-24). Each of the three
  windows is put on its screen first and placed again 60 ms after it is
  shown: the overlay (`PanelWindow`), the page's window restored where it
  was left (`FloatingWindow`; `savedPlace` names the screen its title bar
  is on), and the popups by the clock (`KeyboardPanel`; `workArea` names
  its screen). The overlay was seen right on both screens; the other two
  are checked in `tests/test_windows_shell.py` with the shift made by
  hand, and on one screen for real, not yet on the two (2026-11-25).
- Do Not Disturb is read from Windows' Focus assist profile (the shell's
  own toggle publishes it; `play_sound.silenced`), an undocumented state
  that Windows 11 still keeps: read as off on 2026-11-24, not yet seen on.
- The programs the agent's extras call are not installed for you. The
  Start menu's entry and the start with the session are made by
  `longhand install` and read back as Windows holds them
  (`tests/test_start_menu.py`); so are the commands' copies and their
  folder's place on PATH, in a registry key of the test's own. On the
  real PATH, a new terminal starting `pomo` by name after `tools/install`
  on a fresh machine, and `--tools` installing MiKTeX and setting it with
  `initexmf` in the same run, have not been seen yet (2026-11-24): the
  test plays winget and the registry. Started from the shortcut, the taskbar
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
