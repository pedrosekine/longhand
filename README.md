# Longhand

You write the day by hand, in your own words, and it stays yours. Longhand is
a daily page on [Omarchy](https://omarchy.org): a blank sheet inside the shell
where you drive and own your threads (the courses, projects and questions you
carry from day to day). An agent is there when you call it, to lend help and
power: it reads only what you send it and answers in the margin, never in
your text. Deadlines, tasks and focus sessions live in the same notes, so a
course's work is found by the course and not by the day it was written.

Keyboard-first, plain markdown underneath (your Obsidian vault reads the same
files), and private by construction: the agent sees only what local code
assembled for it, every payload is logged before it is sent, and it only runs
when you ask.

## What is in it

| Part | What it does |
|------|--------------|
| **The page** (`plugin-page/`) | Today's note as a full-screen overlay or a tiling window, drawn in the Omarchy theme: headings, checkboxes, emphasis, private callouts. Month calendar and your projects in a sidebar. |
| **The agent** (`agent/longhand-agent`) | `Ctrl+Enter` sends the block you are in; the reply and the conversation appear beside it. Tool-less, sandboxed opencode, with a cost ledger. |
| **Deadlines in the notes** | Write `- [ ] essay draft #course due fri 17:00` and the line becomes a deadline, still readable in Obsidian. |
| **The dashboard** (`Ctrl+T`) | Every open task and deadline across all your notes, grouped by what it asks of you and then by course. |
| **Bar widgets** (`plugin/`, `plugin-deadline/`) | A Pomodoro countdown and the next deadline, with popups. |
| **`pomo`** (`cli/pomo`) | The timer and deadline store behind it all, scriptable from a terminal or Hyprland bindings. |

Status: in daily use by its author through the semester; installable by
others, though setup is still manual. Design notes in `docs/diary.md`, the
build log in `docs/plan.md`.

Logo placement, exports, and theme integration: read the
[logo source of truth](docs/brand/README.md). It identifies the active A2 seal,
canonical assets, and historical studies.

## Install

Needs Omarchy (for `omarchy-shell`) and [opencode](https://opencode.ai) with
one model key.

```bash
mkdir -p ~/.config/longhand
cp config.example.json ~/.config/longhand/config.json   # then point "vault" at your notes
cp -r plugin-page     ~/.config/omarchy/plugins/longhand.page
cp -r plugin          ~/.config/omarchy/plugins/longhand.pomo
cp -r plugin-deadline ~/.config/omarchy/plugins/longhand.deadline
# add {"id":"longhand.page"}, {"id":"longhand.pomo"}, {"id":"longhand.deadline"} to plugins[] in ~/.config/omarchy/shell.json
ln -s "$PWD/cli/pomo"             ~/.local/bin/pomo
ln -s "$PWD/agent/longhand-agent" ~/.local/bin/longhand-agent
ln -s "$PWD/cli/longhand-check"   ~/.local/bin/longhand-check    # keeps the notes, the store and the popup one thing
longhand-agent install
mkdir -p ~/.local/share/icons/hicolor/scalable/apps         # "Longhand" in the app launcher (Super+Space)
ln -s "$PWD/launcher/longhand.desktop" ~/.local/share/applications/longhand.desktop
ln -s "$PWD/launcher/longhand.svg"     ~/.local/share/icons/hicolor/scalable/apps/longhand.svg
```

Upgrading from **omarchy-student** (Longhand's name until 2026-10-16): run
`tools/migrate-to-longhand` to see what it would move, then
`tools/migrate-to-longhand --apply` and `omarchy restart shell`. It moves
`~/.config/omarchy-student` and `~/.local/state/omarchy-student` to
`longhand` (the old paths stay as symlinks), the vault's `agents/student` to
`agents/longhand` with the agent link in each daily note, the plugins and
their ids in `shell.json`, `hypr/student.lua`, and `student-agent`. A copy of
everything it moves or replaces goes to `~/Backups/longhand-rename-<date>`
first, and a second run does nothing.

## The page

`plugin-page/` is a full-screen overlay for `omarchy-shell`: today's note as a
blank sheet in the current theme, saved on every keystroke. `SUPER+ALT+=` or
the `󰏫` bar glyph opens it, `Esc` closes. `SUPER+ALT+\` opens the same
sheet as a normal window to tile beside something; `F11` (or `Ctrl+Alt+P`)
flips between the two. The note is drawn, not shown as markdown: headings set large,
checkboxes as boxes (click or `Ctrl+L`), bullets, numbers, and private
callouts marked "never sent"; typing `# `, `- [ ] ` or `> ` turns the line
into that kind, Backspace at its start turns it back. Colours follow the
Omarchy theme: the four heading levels are four kinds of thing — H1 the
theme's own chroma, H2 that colour halfway to the text, H3 the prose, H4 the
quiet grey — with highlights, selection and checkboxes from the theme's
palette, greys only where they stay readable, and body text at the contrast
the theme chose.
`Ctrl+B` and `Ctrl+I` wrap the selection — or the word the cursor is in — in
`**` and `*`, `` Ctrl+` `` in backticks, `Ctrl+Shift+S` in `~~`; the same keys
take them off again. Emphasis is **drawn**: the markers go to nothing and
the words carry the weight, nested ones too (`***both***`). They are still
in the file exactly as written, so Obsidian reads the same markdown. A `*`
with spaces around it is arithmetic and an underscore inside a word is part
of the word; neither is markup. A pair is one thing to the cursor: it never
stands inside one, arrows cross a whole pair in one press, and Backspace
takes the letter past it rather than the marker. Delete what an emphasis
holds and the pair goes with it, so you are never left looking at a `**` you
did not type. The one pair you do see is the empty one the key writes when
there is nothing to wrap — it stands waiting for the first letter, which
takes it away.

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
`Ctrl+Enter` lands on the match selected and closes the search, Esc closes
it with the cursor on the match (as browsers and editors do), Shift+Esc
goes back to where you were. `Ctrl+Shift+B` shows a month calendar in a sidebar
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
one line. A block that already has an answer is never asked twice: the word
reads **reply**, and `Ctrl+Enter` opens the conversation on it with the
cursor in the box. (A block's identity is its text, so changing the words
makes it a new block that runs as usual — what cannot happen is paying to
ask the identical question again and overwriting the first answer with the
second.) What you send appears in the conversation at once, with *thinking*
under it until the answer arrives, counting the seconds once it has been a
few. From the moment you ask until the answer is back, the block's
gutter mark carries a light travelling down it and the header's **agent**
brightens — a mark that moves means still thinking, a mark that rests means
answered. A pass that fails says so in a line under the cursor; it never
looks like an agent with nothing to say. `Ctrl+Up/Down`
go to a block's start or end and, pressed again, on through the blocks
before or after, the way Word walks paragraphs (`Ctrl+Shift+Up/Down` select
the same way); `Alt+Up/Down` move the line, or every line selected, up or
down, as in VS Code;
`Alt+Right` goes into the margin — proposals first (Enter accepts one and runs
it through `pomo`), then the chat — `Alt+Left` or `Esc` comes back. Drop
course material into `agents/longhand/curriculum/` and run
`longhand-agent curriculum` once for PDFs. Set `inbox` (e.g. `~/Downloads`) and the PDFs there that belong to a course — its code, title or tag in the file name or on the first two pages, or downloaded during or just after one of its classes — are proposed in the dashboard for filing into `<vault>/projects/<tag>/docs/`; nothing else in the folder is ever listed. A course's documents are in its project in the sidebar, and the agent sees their titles on a run about the course. List your `languages` in the config; the agent answers in the one the
block is written in. Add your calendars in **Settings → Calendar** (`Ctrl+,`, or **settings** at the foot of the
sidebar): paste an `.ics` or `webcal://` address and each calendar is fetched at once and says whether it works. Classes are
matched to your projects by course code, so the sidebar's next session follows them; and for each calendar you choose
what the agent sees — its classes only (the default), or everything in it (titles, times and places, never descriptions).
They are fetched when the page or sidebar opens, at most hourly; the addresses stay in `settings.json` on your machine. A tick
makes a short, soft sound — never an untick, never while notifications are silenced — which Settings can turn off. Needs `~/.config/longhand/config.json` (copy
`config.example.json`) pointing at your vault; the note lives at
`<vault>/<daily.dir>/<date>.md` exactly where Obsidian's daily notes would.

### Every key, and moving one

Days have keys of their own, ones a laptop reaches without Fn: `Ctrl+H` is
today's note from anywhere (the dashboard and the sidebar too), `Ctrl+[` /
`Ctrl+]` the day before or after that has a note — as Obsidian steps its
daily notes, on Notion's back and forward keys — and forward from the last
one is today. `Alt+Home` and `Ctrl+PgUp/PgDn` do the same on a keyboard
with those keys of their own. Where another app has taught a key, the page answers
to it as well: `Ctrl+E` for inline code beside `` Ctrl+` `` (Notion), `Ctrl+\`
for the sidebar beside `Ctrl+Shift+B`; in the dashboard `j`/`k` move, Space
or `e` ticks (Todoist), and the note's own `Ctrl+L` and `Ctrl+D` tick and ask
"when?" there too. `Ctrl+L` ticks a deadline wherever one is listed: the
sidebar's list for a day, and the bar's deadline popup beside its `d`; `t` in the calendar is today. On a keyboard with dead keys
(US-International, most European layouts) `` Ctrl+` `` is the backtick, as it
should be.

Every key, with where it works, is in [docs/keys.md](docs/keys.md). It is
written from the keys themselves (`python3 tools/keys_guide.py`, which
`tests/test_keys_guide.py` holds to), so it never names a key the page no
longer has; `--mine` prints it with the keys you moved.

`Ctrl+/`, or **keys** at the foot of the sidebar, turns the sheet into the list of every
key the page answers to, grouped by where it works: the page, writing,
moving through the note, the agent, `@`, find, the dashboard, the calendar,
the sidebar's lists and the margin. Type to narrow it ("bold", "ctrl+t").
Enter on a row and press the new key to move it there; Shift+Enter adds a
second key beside the first; `Del` gives the row its own keys back. Every
hint in the page follows the move. A key that something else in the same
place already has is asked about first (press it again to take it), a
letter alone is refused wherever you write, since it would be typed, and the
text field's own keys (arrows, selecting, the clipboard, Enter, Tab) are
listed but never taken. What you move is kept in
`~/.config/longhand/keys.json`, only the keys that differ, by the
names in `plugin-page/Shortcuts.js` — `{"bold": ["Ctrl+K"]}` — and the page
reads it again when you edit it by hand. Delete it to have every key back.

The mouse teaches the keys. Hover over anything you can click: the header's
words, a checkbox, a dashboard row, a calendar day or arrow, a deadline,
project or section in the sidebar, an `@` suggestion, a proposal in the
margin. A hint says what it does and which key does the same, and it names
a key you moved, or says there is none. The bar glyph's hint names the
Hyprland key that opens the page.

Hyprland's six keys for the page, the timer and the deadlines
(`SUPER+ALT+=`, `\`, `D`, `O`, `P`, `N`) are listed last, read from your
Hyprland config, wherever and on whatever keys you bound them. Above them, one row
offers to let the page keep them. Enter on it says what it will write, and
Enter again does it: the six go into `~/.config/hypr/longhand.lua`, a file
the page owns, and one line at the end of `~/.config/hypr/bindings.lua`
loads it (through Omarchy's `require_optional`, so a deleted file is never
an error). Your own lines for those six are commented out, saying where
they went, and `bindings.lua` is backed up first (`bindings.lua.bak.<time>`).
After that the page never writes into `bindings.lua` again, and the six move
like any other key. While the sheet waits for one, Hyprland is put in a
submap of its own, so a key Hyprland already uses reaches the sheet
instead of doing its job. Hyprland leaves that submap by itself after 30
seconds. A Hyprland key must hold Super, so it can never take a key an app
needs. A key that another bind has (Omarchy's `SUPER+ALT+F`, say) is asked
about first; taking it writes an `hl.unbind` for it in `longhand.lua`, and
moving off it gives the key back. Every change reloads Hyprland, and if
Hyprland reports a new config error, the old file is put back.
`plugin-page/hyprkeys.py` does the writing; you can edit the keys in
`longhand.lua` by hand, and the sheet reads them back.

```bash
python3 tests/test_blocks.py                                # block splitter, JS and Python must agree (needs node)
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests   # editor (driven by keys), keys, emphasis, calendar days, bound lines
python3 tests/test_pomo.py                                    # the deadline CLI's contract with the page
python3 tests/test_check.py                                   # one copy of a task: the notes, the store and the ledger agree
python3 tests/test_keys_guide.py                              # docs/keys.md is the keys as they are (needs node)
python3 tests/test_hyprkeys.py                                # Hyprland's six keys, against a fake hyprctl
python3 tests/test_migrate.py                                 # the move from omarchy-student, in a throwaway $HOME
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
and the page draws the date at the line's end. The line is the task: its
words are the deadline's title, its `#tag` (or the tagged heading above it)
its project, and a tick or a date changed anywhere — the line, the
dashboard, the bar popup, `pomo`, Obsidian — reaches every other place.
Deleting the line, or a whole block, cancels its deadlines and says so
under the cursor; pasting the line anywhere or `Ctrl+Z` brings them back.
Nothing is asked, and nothing is erased: cancelled is history. The
calendar marks deadline days, `Ctrl+T` lists deadlines first, and in the
bar popup `o` opens a deadline's line. How it all holds together, and why:
[docs/tasks.md](docs/tasks.md).

## The dashboard

`Ctrl+T` turns the sheet into the dashboard: every open checkbox and every
deadline across all your daily notes, full width. Rows are grouped by what
they ask of you — **due** (a date you owe), **doing** (a day you mean to work
on it), **to schedule** (a priority and no day yet) — and then by course,
never by the day the thought was written. Each row says where it was written
and how long ago ("Design Theory › Essay 2 · yesterday"); dates are the same
pills as in the note.

Enter opens the line in its note, on any day, as it does everywhere.
`Ctrl+Enter` ticks it — in the day it was written, so the note and the
dashboard never disagree. `t` asks "when?" in words ("friday"), `p` walks
the three priorities, `Ctrl+E` renames it (the line's words; details stay in
the note, as indented lines under it, and the row says how many), `Del`
cancels it (kept in the note as `- [-] … ❌ <day>`, so the decision is on
record), `Ctrl+Z` takes a tick or a cancel back. A deadline no note holds
yet — an agent's proposal that matched none of your checkboxes, or one
added with `pomo` — waits under **not in a note yet**, marked as the
agent's: `Ctrl+E` lets you write over its words, Enter writes it into
today's note. The bar's deadline popup (`SUPER+ALT+D`) stays the glance;
the dashboard is where the work gets done.

## How it is used

`longhand-agent stats [--days 14 | --since 2026-10-11] [--json]` prints, day
by day, what is already on disk: words written, checkboxes written → ticked,
bound deadlines and whether they were closed by their time, agent runs and
cost, focus sessions, the #tags and languages in the notes, and what the page
was opened for. The page keeps its part in `~/.local/state/longhand/usage.tsv`
— event names and numbers, never a word of a note, never sent anywhere.

## The agent

`agent/longhand-agent` is what the page calls when you finish a checkbox line,
an `@` line, a line ending in `?`, tick a box, or open the page. It builds
the context from an allowlist, logs it, runs a tool-less opencode agent, and
writes the reply to `agents/longhand/daily/<date>.md` in your vault. It never
writes under your daily-notes folder.

opencode is run `--standalone`, from the agent's own empty directory, so a
pass has a server of its own that dies with it and nothing of any project is
ever in scope. The ledger (`~/.local/state/longhand/cost.tsv`) reads
each pass's price back from its session.

```bash
ln -s "$PWD/agent/longhand-agent" ~/.local/bin/longhand-agent
longhand-agent install                       # opencode agent definition + folders
longhand-agent context --trigger open        # show exactly what the model would see
longhand-agent run --trigger open            # one pass over today's note
longhand-agent sections --tag intsem         # one project's notes across every day (JSON)
longhand-agent context --trigger mention --hash <h>   # incl. that project's earlier notes
python3 tests/test_agent.py                 # offline, stub opencode
```

## The timer and the deadline store

`pomo` is a plain CLI, so Hyprland bindings work even when the bar is closed
(example bindings in `docs/plan.md`):

- `pomo start [focus|break|up] [minutes] [--for <deadline id>]`, `pause`,
  `resume`, `toggle`, `reset`, `skip`, `status`. `up` counts up instead of
  down; `--for 3` ties the session to deadline #3, so the log reads
  `focus completed · 25:00 · for #3 Essay draft`.
- `pomo deadline add <title> [--project <p>] [--link <url-or-path>] <when...>`
  with free-text dates ("next friday 17:00", "in 3 days"); also `set`,
  `list [--all] [--json] [--project <p>]`, `done`, `reopen`, `grade`, `hide`,
  `unhide`, `rm`, `next`, `when`.

## Pointing an agent at it

Everything is plain files plus one command, no daemon:

```bash
pomo report --json        # timer state, session counts, every deadline (incl. hidden) with status/done_at/grade
pomo deadline list --all --json
pomo status               # timer only
```

Files live in `~/.local/state/longhand/`:

| File | What |
|------|------|
| `deadlines.tsv` | `id<TAB>due_epoch<TAB>title<TAB>status<TAB>done_at_epoch<TAB>grade<TAB>project<TAB>link` — status is open / done / hidden; project and link may be empty (older lines stop after grade and read the same) |
| `pomo.log` | one line per event (`focus completed · 25:00`, `deadline #3 graded 7.5 · Essay`) — the history an agent reasons over |
| `state.json` | current timer, incl. `"for"`: the deadline id the running session is for (0 when none) |

Ids are stable and never reused, so a log line about `#3` always means the same
deadline. Write through the CLI (`pomo deadline ...`), not to the files, so the
bar widget and the log stay in step. Design notes for the agent side are in
`docs/student-os.md`.
