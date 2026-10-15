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
- `pomo deadline add <title> [--project <p>] [--link <url-or-path>] <when...>`,
  `set <id> [--title <t>] [--project <p>] [--link <l>] [<when...>]`,
  `list [--all] [--json] [--project <p>]`, `done|reopen|grade|hide|unhide|rm|next|when`
  — manual deadlines with free-text dates ("next friday 17:00", "in 3 days");
  `--project` is what it belongs to (a course, a thesis, anything; `--subject` still works), `--link` the file or URL
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
into that kind, Backspace at its start turns it back. Colours follow the
Omarchy theme: headings each in their own, highlights, selection and
checkboxes from the theme's palette, greys only where they stay readable,
body text at the contrast the theme chose.
`Ctrl+B` and `Ctrl+I` wrap the selection — or the word the cursor is in — in
`**` and `*`, `` Ctrl+` `` in backticks, `Ctrl+Shift+S` in `~~`; the same keys
take them off again. Emphasis is **drawn**: the markers go to nothing and
the words carry the weight, nested ones too (`***both***`). They are still
in the file exactly as written, so Obsidian reads the same markdown — and
break one of a pair and it stops being emphasis, so the markers come back
at full size, which is how you see them to edit them. A `*` with spaces
around it is arithmetic and an underscore inside a word is part of the
word; neither is markup.

The page is set in **iA Writer Quattro S**, a proportional face made for
writing: prose reads as prose rather than as code, and 72 characters take
less width than they do in a monospace. Fenced code and frontmatter keep a
monospace, where columns mean something. `font` and `codeFont` in the config
name other faces; without them the page takes the first it finds of iA
Writer Quattro S, iA Writer Duo S, then the shell's own. The page asks for
the face's `Regular` cut by name: the iA Writer families declare the same
weight for every style, so asking by weight hands back the Bold file — the
whole page came out heavy and `**bold**` had nowhere heavier to go. A
family without a style of that name is unaffected. Size follows the
shell's scale (your Omarchy font size); `Ctrl+=` / `Ctrl+-` / `Ctrl+0`
zoom the whole page like a browser, remembered across restarts. `Ctrl+F`
finds in the note as you type: Enter next, Shift+Enter previous,
`Ctrl+Enter` lands on the match selected and closes the search, Esc goes
back to where you were. `Ctrl+Shift+B` shows a month calendar in a sidebar
(only when asked): days with a note are full, days without are faded;
arrows move by day and week, `Ctrl+←/→` by month, Enter opens the day in
the same sheet, editable (a day without a note gets its file on the first
word). `Alt+Left`/`Alt+Right` move between calendar and note; `weekStart`
in the config picks the first column. Under it, your projects (one file each
in the agent's `knowledge/projects/`) with their next session. Enter or a
click **opens that project's notes** in the sidebar itself: every section you
wrote under its tag, newest first, with the headings under each as its index,
so a class note is found by its course instead of by the date it happened on.
Enter opens a section in the sheet with the cursor on its heading, editable
like any other day, and the list stays where it is; `←` or Esc goes back to
the projects. A tagged heading claims everything under it until the next
heading of the same or a higher level, so an `## H2` never ends a `# Course`.
Writing a project into the note is the shifted pair: Shift+Enter starts a
class (`# Course #tag`), Ctrl+Enter puts just the tag at the cursor.
The file stays plain
markdown, changed only where you typed. What you wrote is always drawn at
full strength; a block with a reply carries a gutter mark and its reply shows
in the margin to the right when asked — that is the only mark on your words.
Typing `@` calls a project: the list narrows as you type, Enter leaves its
`#tag` where the `@` was, and Shift+Enter (on a line the `@` opened) starts
the class with its `# Course #tag` heading. It is the same vocabulary as the
sidebar's projects list, wherever your hands are. An address — `pedro@it-u` —
is never a call, since `@` only counts at the start of a word.

**private** in the header (or `Ctrl+Shift+P`) marks the open note unseen: it
writes `agent: false` into the note, the word then reads "private · the agent
sees nothing here", and **ask** and the agent mark disappear — no pass runs
when you open it, nothing can be sent, and the runner refuses the note too.
Turning it off puts the day back. For part of a note rather than a whole day,
a `> [!private]` callout hides that block.

Nothing ever interrupts your writing to offer the agent. You reach for it:
`Ctrl+Enter`, or **ask** in the header, sends the block your cursor is in —
a run of list items counts as one submission. The word reads dim when that
block carries a sign for the agent (a checkbox, an `@` line, a line ending
in `?`, a ticked box) and faint when it does not; asking anyway says why in
one line. From the moment you ask until the answer is back, the block's
gutter mark carries a light travelling down it and the header's **agent**
brightens — a mark that moves means still thinking, a mark that rests means
answered. A pass that fails says so in a line under the cursor; it never
looks like an agent with nothing to say. `Alt+Up/Down`
move between blocks, `Ctrl+Up/Down` jump to a block's start or end
(`Ctrl+Shift+Up/Down` select to it, a block more each press),
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
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests   # editor (driven by keys), emphasis, calendar days, bound lines
python3 tests/test_pomo.py                                    # the deadline CLI's contract with the page
python3 tests/page/run.py                                     # the page itself, live: a window that never takes focus, a throwaway vault
```

## Deadlines in the notes

A checkbox can stand for a deadline. Write it with a date at the end —
`- [ ] chapter 2 draft #thesis due fri 17:00` (or `by monday`, `until 20
oct`, `the 8th of Feb`, `📅 tomorrow`) — and the date lights up as you type
it, with the pill it will become; when you leave the line it is the
deadline, nothing asked (as in Todoist). To keep the date as words: Backspace
right as it lights up, `Ctrl+D` on the line, or `Ctrl+Z` after it is bound.
Only lines you type in are recognised, so moving through an old note binds
nothing; `Ctrl+D` binds such a line on purpose, asks "when?" on a line with
no date, and on a bound line reschedules (empty unbinds). A checkbox list
goes to the agent only once its dates are bound. The line then
reads `- [ ] chapter 2 draft #thesis 📅 2026-10-16 17:00 ^d6` on disk —
Obsidian shows the date, `^d6` is a block id the deadline links back to —
and the page draws the date at the line's end. The deadline module is the
truth: ticking the line marks it done, editing its words renames it, the
first `#tag` is its project; changes made in the popup or `pomo` reach the
line when its note opens. Deleting a bound line asks whether the deadline
goes too. The calendar marks deadline days, `Ctrl+T` lists deadlines
first, and in the bar popup `o` opens a deadline's line.

## How it is used

`student-agent stats [--days 14 | --since 2026-10-11] [--json]` prints, day
by day, what is already on disk: words written, checkboxes written → ticked,
bound deadlines and whether they were closed by their time, agent runs and
cost, focus sessions, the #tags and languages in the notes, and what the page
was opened for. The page keeps its part in `~/.local/state/omarchy-student/usage.tsv`
— event names and numbers, never a word of a note, never sent anywhere.

## The loop (phase 14.2)

`agent/student-agent` is what the page calls when you finish a checkbox line,
an `@` line, a line ending in `?`, tick a box, or open the page. It builds
the context from an allowlist, logs it, runs a tool-less opencode agent, and
writes the reply to `agents/student/daily/<date>.md` in your vault. It never
writes under your daily-notes folder.

opencode is run `--standalone`, from the agent's own empty directory, so a
pass has a server of its own that dies with it and nothing of any project is
ever in scope. The ledger (`~/.local/state/omarchy-student/cost.tsv`) reads
each pass's price back from its session.

```bash
ln -s "$PWD/agent/student-agent" ~/.local/bin/student-agent
student-agent install                       # opencode agent definition + folders
student-agent context --trigger open        # show exactly what the model would see
student-agent run --trigger open            # one pass over today's note
student-agent sections --tag intsem         # one project's notes across every day (JSON)
student-agent context --trigger mention --hash <h>   # incl. that project's earlier notes
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
| `deadlines.tsv` | `id<TAB>due_epoch<TAB>title<TAB>status<TAB>done_at_epoch<TAB>grade<TAB>project<TAB>link` — status is open / done / hidden; project and link may be empty (older lines stop after grade and read the same) |
| `pomo.log` | one line per event (`focus completed · 25:00`, `deadline #3 graded 7.5 · Essay`) — the history an agent reasons over |
| `state.json` | current timer, incl. `"for"`: the deadline id the running session is for (0 when none) |

Ids are stable and never reused, so a log line about `#3` always means the same
deadline. Write through the CLI (`pomo deadline ...`), not to the files, so the
bar widget and the log stay in step. Design notes for the agent side are in
`docs/student-os.md`.
