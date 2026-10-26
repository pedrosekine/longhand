# Files: the notes outside the calendar

_Grilled 2026-10-26. Amends the 2026-10-09 stance in
[diary.md](diary.md) ("daily notes only, not a whole-vault tree"). Nothing
here is built yet; the order is in [plan.md](plan.md), parking lot item 9._

The page is about days: the calendar, the day's deadlines, the projects,
the note. That stays first. But a vault holds years of other notes (course
files, reference, career, journaling), and for the page to be usable beside
Obsidian, or instead of it, those notes have to be findable and readable in
the page too. Time-based notes stay the default. Files are one step away and
never in the way.

## How it is built

The rules every part below is judged by. They apply to the whole page, and
this feature is where they are easiest to break:

- **Light on memory.** The shell, page included, used 489 MB RSS on
  2026-10-26. Files must not move that number much:
  - the tree lists a folder when it is opened, never the whole vault up front;
  - images are decoded at the size they are drawn (`sourceSize`) and let go
    when they scroll away;
  - the PDF view is loaded only while a PDF is open;
  - diagrams are rendered once to SVG and cached;
  - no web engine.
- **Minimal.** One more space in the sidebar, not a second app. What isn't
  needed yet isn't built.
- **Keyboard first.** Every action has a key, registered in `Shortcuts.js`
  so the keys sheet lists it and it can be moved. The mouse and the trackpad
  are second ways in, never the only ones.
- **Beautiful.** Drawn in the theme, by role, as the rest of the page is.
  Rendering is designed and prototyped, not left at Qt's defaults.
- **Better each pass.** Ship a first version, use it, then improve it.

## Spaces: the sidebar swipes

The left pane holds **spaces**, after the
[Zen browser](https://docs.zen-browser.app/guides/about-config-flags)'s
workspaces. A space is what the sidebar shows, the same way the middle shows
the note or the dashboard. There are two:

| Space | What it shows |
|---|---|
| **Time** (the default) | the calendar, the day's deadlines, the projects, as today |
| **Files** | the notes as folders and files: yours, then the agent's |

- **Switching:** `Ctrl+Shift+[` and `Ctrl+Shift+]` (wrapping around), a
  two-finger swipe or Ctrl+scroll on the sidebar, or a click on the two
  marks at the sidebar's foot that show which space is open. `Ctrl+[` keeps
  its one meaning (go to the sidebar; in it, close it), and Esc still backs
  out one level ([navigation.md](navigation.md)).
- **Each space has its own tint**, so the space is known without reading.
- **A fresh open lands on Time.** The page still opens blank on today.
- **Essentials:** what stays at the sidebar's foot in every space. That is
  the seal, **keys**, **settings** and a **today** mark. Pinned notes can be
  added later if the same few keep being reopened.
- **Projects stay in Time.** They are sections of the daily notes, so they
  are time-based. A third space waits until they outgrow it.

## The Files space

- **Two roots, two rights.** **Yours**, the notes root (`human/` here), is
  editable. **The agent's**, `agents/`, is read-only and drawn in the agent's
  style, `.md` only, never its `.json` state.
  - That boundary is also the answer to "who wrote this?": the vault keeps no
    author (Obsidian doesn't, and the Mac's hourly commit doesn't), so **the
    folder is the rule**.
  - The runner's write guard widens from the daily folder to the whole notes
    root, so no agent run writes in yours.
  - For other students, the notes root is one line in the config, like
    `daily`, and nothing assumes Obsidian.
- **What the tree shows:** `.md` files, and later PDFs.
  - Hidden: `Daily`, which the Time space owns, every `_`-prefixed folder
    (`_Attachments`, `_Archive`, `_Secrets`) and `Templates`.
  - `Archive/` starts folded.
  - Folders come first, then files, by name.
- **Browse and find.** The tree, plus a typed filter that narrows it by name.
  That covers both "I know roughly what I want" and "I don't know where it
  is". A fuzzy switcher over the whole notes root comes later, if the filter
  proves too slow.
- **Opening a file** puts it in the middle, in place of the note, like a
  past day, and editable the same way. Consulting is the intention and
  editing is allowed. `Ctrl+H` is home to today.
- **Following a wikilink** replaces the view, browser-style, with a back
  history. The keys get settled when building: Enter, Ctrl+Enter and
  Alt+←/→ are already taken in the note.

## Talking about a note

- `Ctrl+Shift+Enter` keeps meaning "talk about *this thing*": the block in
  a file, as in the note.
- **ask about this note** in the header shares the whole file.
- Neither writes into the file. The conversation lives in the agent's pane,
  is kept in `agents/` under the file's path, and the file's header shows
  that one exists.
- **Opening is not sharing.** The agent sees an open file only when it is
  talked about this way, or pointed at with `@` in the agent's box.
- Talking about a private note, or a day before the horizon, is the
  explicit consent, for that conversation only.
- **The context blip.** When the keys move from the middle into the agent's
  pane, what the agent will be given (the block, the whole sheet, the row)
  pulses once, so it's always visible what goes along.

## Privacy

### The horizon (built 2026-10-26)

On 2026-10-26 the agent's search included `Daily` by default, and none of
the 672 daily notes (2021-07-17 onwards) was marked `agent: false`, so
**years of journaling were searchable by the agent**.

The fix is a **horizon date**: the agent sees daily notes only from
**2026-09-17** (the day Longhand began) onwards. Earlier days are private
unless the person brings one into a conversation.

- It is one date in the settings, shown and changeable in Settings → what
  the agent may search.
- No file is touched.
- It is checkable in the payload log.
- It covers `Daily` only, because `Personal` (where `Reflections` lives) and
  `Health` are already off for the agent's search.

**How it is built.**

The runner holds the rule:
- `agent_horizon` takes the date from settings.json, else the first
  `agents/longhand/daily/*.json`, else today. A vault the agent never ran in
  shows it nothing from before.
- `before_horizon` gates every reader of past days: a run on that day, a
  project's earlier notes, the planner's week of notes, the outcomes, a
  task's block and the briefs.
- `search.py` holds such days back and counts them as `horizon`.
- `longhand-agent horizon` reports the date, its default and how many daily
  notes fall on each side of it.

The page has two parts:
- It reads the horizon when it opens and offers nothing on a day before it.
  The header says "before the agent's horizon".
- Settings → what the agent may search has a row above the folders: ←/→
  moves it by a month, Shift+←/→ by a year, and Backspace sets the default
  again.

On this vault: 644 days held back, 28 left.

Tests: `tests/test_search.py` (the horizon), `tests/test_agent.py` 16b, and
`tests/page/run.py` 12c.

### How private looks (to explore)

**Private notes.** A private note's only sign today is the header word,
which reads "private · the agent sees nothing here" and goes from faint to
the text colour. The words, the sheet and the gutter stay as they were, so
clicking **private** seems to do nothing but show a hint.

**Private blocks.** A `[!private]` block is a callout with a magenta label
over ordinary text. Meanwhile "the agent has seen this" is a veil, so the two
are easy to confuse or miss.

**What needs designing.** How a private *note*, a private *block*, a day
*before the horizon* and a block the agent *has seen* are told apart. The
one rule so far: **private and seen never share a look.** Candidates:

- a different material: another paper tone for a private sheet, and an inset
  of that tone for a private block;
- a lock in the gutter where the agent's marks would go;
- the header's "ask" replaced by "private".

These are to be mocked up in the theme and compared before anything is
built.

## Rendering

From the 2026-10-26 survey of the notes root:

| Feature | Count |
|---|---|
| Image embeds (almost all png) | about 1,160 |
| Wikilinks | 747 (over half with an `\|alias`, a third to a `#heading`) |
| Tables | 77 |
| Callouts, Dataview, mermaid | none |
| Frontmatter | `date:` only |

All of these deserve a beautiful version, researched and prototyped before
building:

- **Images** are drawn in the column at their drawn size. With the cursor on
  an image's line, its source (`![[x.png]]`) shows above it so the name can
  be edited, as Obsidian's live preview does. Revisit if it gets in the way.
- **Wikilinks** are followable, land on their heading and show their alias.
  Hover previews are worth researching.
- **Tables** start as aligned text. A real grid comes once it is designed.
- **Diagrams** use [Pele](https://github.com/obsidianmd/pele), Obsidian's
  MIT-licensed Mermaid-to-SVG renderer. `render(text)` is synchronous and
  needs no runtime dependencies.
  - It colours its SVG with CSS variables, which Qt's SVG renderer cannot
    read. The theme's colours are substituted in before drawing, as
    `ThemeColors` does for the page.
  - It runs once per diagram through `node` and is cached. Whether
    `render()` needs a DOM, so whether it could run in QML's own engine, is a
    prototype's question.
- **PDFs** use `QtQuick.Pdf` (`PdfMultiPageView`), already installed with
  Qt 6.12, so no new dependency.

## Open, and documented as open

- **The middle ground.** `projects/`, `reference/` and `inbox/` are mixed
  authorship: the person's projects with agent-written handoffs. They fit
  neither "yours" nor "the agent's", so they are left out of the Files space
  for now. Deciding how they show is a decision of its own.
- **Tabs.** Following a link replaces the view. Several notes open at once,
  as tabs, is a later discussion.
- **A fuzzy switcher** across the notes root, if the tree's filter is not
  enough.
