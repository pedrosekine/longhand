# omarchy-student

Hybrid Pomodoro and deadline tracker for Omarchy: CLI that works in terminal +
thin bar widgets. Keyboard-first v0.1. Next: a diary page in the shell that an
agent reads and answers — reference plan in `docs/diary.md`.

## Why hybrid?

- **Plugin-only** = QML running inside `omarchy-shell`. Dies with shell, no terminal use.
- **Standalone** = CLI/daemon (like `focusd`). Works in terminal, scriptable, survives restarts.
- **Hybrid (this project)** = standalone core + thin plugin that just displays status.
  Best for keyboard shortcuts because bindings call the CLI even when bar is closed.

## Scope v0.1 (keyboard shortcuts only)

- `pomo start [focus|break|up] [minutes|up] [--for <deadline id>]|pause|resume|toggle|reset|skip|status`
  from terminal (`pomo start up` runs an open-ended count-up focus session;
  skipping it logs the elapsed time as a completed session; `--for 3` ties
  the session to deadline #3 so its log lines read `focus completed · 25:00 · for #3 Essay draft`)
- `pomo deadline add <title> [--subject <s>] [--link <url-or-path>] <when...>`,
  `set <id> [--title <t>] [--subject <s>] [--link <l>] [<when...>]`,
  `list [--all] [--json] [--subject <s>]`, `done|reopen|grade|hide|unhide|rm|next`
  — manual deadlines with free-text dates ("next friday 17:00", "in 3 days");
  `--subject` is the course or project it belongs to, `--link` the file or URL
  for the thing itself; `done` takes one off the clock, `grade` records the
  mark, `hide` keeps the record but drops it from the list
- Hypr bindings example in `docs/plan.md`
- State in JSON file, no bar widget yet

## Out of scope for v0.1

- Bar widget, analytics UI, calendar integration

See `docs/plan.md` for full steps.

## The page (phase 14.1)

`plugin-page/` is a full-screen overlay for `omarchy-shell`: today's note as a
blank sheet in the current theme, saved on every keystroke. `SUPER+ALT+=` or
the `󰏫` bar glyph opens it, `Esc` closes. `SUPER+ALT+\` opens the same
sheet as a normal window to tile beside something; `Ctrl+P` flips between
the two. The note is drawn, not shown as markdown: headings set large,
checkboxes as boxes (click or `Ctrl+L`), bullets, numbers, and private
callouts marked "never sent"; typing `# `, `- [ ] ` or `> ` turns the line
into that kind, Backspace at its start turns it back. Type follows the
shell's own scale (your Omarchy font size); `Ctrl+=` / `Ctrl+-` / `Ctrl+0`
zoom the whole page like a browser, remembered across restarts. The file stays plain
markdown, changed only where you typed. Blocks the agent has seen are
veiled; a block with a reply carries a gutter mark and its reply shows in the
margin to the right when asked. Finishing an `@` or `?` line stages the block
(hollow mark) and asks "send to agent?" under the cursor with *no*
preselected; an arrow then Enter sends. A checkbox list is staged as one
submission when you leave it. `Ctrl+Enter` sends a staged block later. `Alt+Up/Down`
move between blocks, `Ctrl+Up/Down` jump to a block's start or end,
`Alt+Right` goes into the margin — proposals first (Enter accepts one and runs
it through `pomo`), then the chat — `Alt+Left` or `Esc` comes back. `Ctrl+T`
opens the what's-next panel: every open checkbox across your daily notes and
what the agent has raised. Enter goes to a task or waves off a suggestion,
Space ticks, Ctrl+Z unticks. Drop
course material into `agents/student/curriculum/` and run
`student-agent curriculum` once for PDFs. List your `languages` in the config; the agent answers in the one the
block is written in. Needs `~/.config/omarchy-student/config.json` (copy
`config.example.json`) pointing at your vault; the note lives at
`<vault>/<daily.dir>/<date>.md` exactly where Obsidian's daily notes would.

```bash
cp -r plugin-page ~/.config/omarchy/plugins/student.page   # then add {"id":"student.page"} to plugins[] in ~/.config/omarchy/shell.json
python3 tests/test_blocks.py                                # block splitter, JS and Python must agree (needs node)
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_editor.qml   # the drawn editor, driven by keys
```

## The loop (phase 14.2)

`agent/student-agent` is what the page calls when you finish a checkbox line,
an `@` line, a line ending in `?`, tick a box, or open the page. It builds
the context from an allowlist, logs it, runs a tool-less opencode agent, and
writes the reply to `agents/student/daily/<date>.md` in your vault. It never
writes under your daily-notes folder.

```bash
ln -s "$PWD/agent/student-agent" ~/.local/bin/student-agent
student-agent install                       # opencode agent definition + folders
student-agent context --trigger open        # show exactly what the model would see
student-agent run --trigger open            # one pass over today's note
python3 tests/test_agent.py                 # offline, stub opencode
```

## Pointing an agent at it

Everything is plain files plus one command, no daemon:

```bash
pomo report --json        # timer state, session counts, every deadline (incl. hidden) with status/done_at/grade
pomo deadline list --all --json
pomo status               # timer only
```

Files live in `~/.local/state/omarchy-student/`:

| File | What |
|------|------|
| `deadlines.tsv` | `id<TAB>due_epoch<TAB>title<TAB>status<TAB>done_at_epoch<TAB>grade<TAB>subject<TAB>link` — status is open / done / hidden; subject and link may be empty (older lines stop after grade and read the same) |
| `pomo.log` | one line per event (`focus completed · 25:00`, `deadline #3 graded 7.5 · Essay`) — the history an agent reasons over |
| `state.json` | current timer, incl. `"for"`: the deadline id the running session is for (0 when none) |

Ids are stable and never reused, so a log line about `#3` always means the same
deadline. Write through the CLI (`pomo deadline ...`), not to the files, so the
bar widget and the log stay in step. Design notes for the agent side are in
`docs/student-os.md`.
