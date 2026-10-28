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

- **Switching:** `Ctrl+1` pressed in the sidebar (since 2026-10-27; it was
  `Ctrl+Shift+[` and `Ctrl+Shift+]` before), a two-finger swipe or
  Ctrl+scroll on the sidebar, or a click on the two marks at the sidebar's
  foot that show which space is open. From outside the sidebar `Ctrl+1` goes
  there, and Esc still backs out one level ([navigation.md](navigation.md)).
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

### How it is built (2026-10-27)

**Spaces.**
- `page.sidebarSpace` holds the space, and a fresh open sets it back to
  `time`.
- `Ctrl+1` in the sidebar calls `switchSpace` (the shifted brackets did, until 2026-10-27). A
  sideways swipe or Ctrl+wheel past a threshold does the same, once per
  gesture (a `WheelHandler` on the sidebar; `TouchScroll` passes sideways
  and Ctrl scrolls on).
- The foot shows **time · files**, then **today**, **keys** and
  **settings**.
- The space slides in from the side it was called from, and Files sits on
  the background tinted 6% towards the accent.

**The tree.**
- `FilesPane.qml` holds it as a flat list of rows drawn by a `ListView`, so
  only the rows on screen exist.
- A folder is read with `find -maxdepth 1` when it is opened, and read again
  each time the space is shown, with the same folders open and the same row
  picked. Nothing is watched.
- `/` opens the filter. It reads every note's path once (`find -iname
  '*.md'`), matches every word anywhere in the path, puts name matches
  first and shows at most 200. The list is let go of when the filter closes.
- Keys: ↑↓ (k/j), → (l) opens a folder or steps in, ← (h) folds it or goes
  up, Enter opens, `/` filters, and Esc clears the filter or closes the
  sidebar. All of them are in `Shortcuts.js` as the "files" place.

**The notes root.** It is `notes` in the config, else the daily folder's
parent when nested (`human/Daily` → `human`), else the vault. It is the same
rule in `Service.qml` and the runner (`notes_root`). The agent's root is the
first folder of `agentDir`.

**A file in the sheet.**
- `svc.openFile(rel, readOnly)` sets `noteDate` to "", and `page.dayNote`
  then turns off what only a day has:
  - binding a dated checkbox (the cue's light, leaving the line, Ctrl+D);
  - the check;
  - who made each line and the threads;
  - the private mark;
  - the agent's state and records (`AgentState.off`, which otherwise read
    *today's* records onto the file's lines);
  - sending, and the agent's pane, which closes with a hint.
- The header names the file, cut short before the seal; the tree shows where
  it is. The header's "back to today" goes home.
- The agent's files open with `NoteEditor.readOnly`: nothing typed, pasted,
  ticked, moved or undone reaches them, and `Service.save` refuses them.

**The write guard.** It refuses anything under the notes root except the
agent's own folder. When the notes are the vault itself it keeps the daily
folder's rule only, because the projects' documents sit beside the notes.

Tests: `tests/page/run.py` 12h (spaces, tree, a file edited, the filter,
an agent file read only, home, a fresh open) and `tests/test_search.py`
(the guard).

## Talking about a note

- `Ctrl+Shift+Enter` opens the note's chat, the whole of it (2026-10-27:
  the Shift of a key is the whole, [keys-proposal.md](keys-proposal.md),
  rule 6; it pointed at the cursor's block until then, which `@` does now).
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

### How it is built (2026-10-27)

**The runner.** `longhand-agent note --file REL --message M [--block H]`.
- One conversation per note, at `agents/longhand/notes/<md5 of the path,
  16>.json` (`path`, `session`, `turns`, `seen`). The page computes the same
  name with `Qt.md5`, which agrees on non-ASCII paths ("FHOÖ").
- The first message tells the day agent what this conversation is, and
  carries the note whole, the notebook and what may be searched. A later one
  carries the note again only when it changed. A block pointed at goes
  along either way.
- No prompt change: the instructions travel in the payload.
- Proposals are ignored. Search and read work as in the day conversation.
- The note is never written. Every message is logged before inference.

**What is never sent, even when asked about.**
- `[!private]` callouts and frontmatter.
- Anything search's never-list refuses: `_Secrets`, documents named for
  identity, money, health, contracts or secrets.
- What gitleaks flags (withheld) and IBAN- or card-shaped strings (masked).
- Anything outside the vault.

A note marked private, or a day before the horizon, is shown, because
asking is the consent.

**The page.** The agent's pane gains a room, `noteRoom`: the day pane's
view, reading the note's conversation instead of the day's.
- It opens from **chat about this note** in the header (it said "ask about
  this note" until 2026-10-27). The word becomes "this note's chat · n" once
  a chat exists.
- It also opens from the pane's key or the seal while a file is in the
  sheet, and from Ctrl+Shift+Enter anywhere in a file.
- The header word shows only where the agent does not already read the
  note: a file, a day before the horizon, a private day.
- A note's answers have no helpful / not-helpful yet. Opening another note
  or day closes the room.

**The blip.** When the keys go from the note into the agent's pane, what
goes with them lights once under the words, an accent wash that fades in
about 0.8 s:
- the block pointed at;
- else the block a margin conversation is on;
- else the whole visible note, for the note's room or today's conversation.

Nothing lights over the dashboard, keys or settings. A dashboard row
talked about already stays faintly marked.

Tests: `tests/test_note.py`, and `tests/page/run.py` 12h.

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

**Private blocks.** A `[!private]` block is a magenta bar at its left with
the label "private · never sent", over ordinary text. A block with an answer
is also a thin bar at the left: in the gutter, accent until read, then dim.
(The veil over seen blocks was dropped before this, because it made a note
hard to read.) So privacy and the agent's answers both read as "a bar at the
left", which makes them easy to confuse.

**What needs designing.** How a private *note*, a private *block*, a day
*before the horizon* and a block the agent *has seen* are told apart. The
one rule so far: **private and seen never share a look.** Candidates:

- a different material: another paper tone for a private sheet, and an inset
  of that tone for a private block;
- a lock in the gutter where the agent's marks would go;
- the header's "ask" replaced by "private".

**Mockups (2026-10-27).** The canvas "How private looks", in Birnbaum with
iA Writer Quattro, has five rows. Each shows three sheets: a day with an
answered block and a private block, a private day, and a day before the
horizon.
- **A, as built:** the baseline.
- **B, Paper:** private is sunk into a darker paper, with a lock in the
  gutter.
- **C, Marks:** the paper is unchanged; a lock and a dotted rule in the
  gutter.
- **D, Sealed:** a hairline frame with its word on the edge.
- **E, Ink:** the private words are in a rose italic ink, and a day before
  the horizon in a sage one.

In every row an answer keeps its solid accent bar in the gutter. None of B
to E uses a solid bar for privacy, so "private" and "answered" no longer
share a look.

**Chosen and built (2026-10-27): B · Paper.**
- **The paper.** `ThemeColors.sunk` is the theme's `dark_background`, but
  only when it is a shade darker than the page's actual ground (contrast
  under 1.35). Else the ground darkened. A page caught between two themes
  once sank light paper under light words; this rules that out.
- **A private block** (`> [!private]`): `privatePaint`, from `repaint()`,
  draws it under the words as an inset of that paper, reaching a little
  into the gutter.
  - A magenta `LockMark` stands left of it, in the gutter.
  - The editor no longer draws it as a quote: no bar, no label, its words
    aligned with the prose.
  - An empty `> [!private]` line is only the paper's top edge.
- **A private day, or a day before the horizon:** the whole sheet, and the
  window in the window shape, is that paper (`sheetSunk`). The header shows
  a magenta lock and "private", or a grey lock and "before the horizon".
- **The keys.** `Ctrl+P` makes the block the cursor is in private, or the
  blocks a selection spans, by wrapping them in `> [!private]`; on a
  private block it unwraps it. `Ctrl+Shift+P` does the whole note.
  - Only the markers are written, and one undo takes them back.
  - A quote only gains the naming line.
  - A callout touching the block is kept apart by a blank line.
- **Checked.** Tests: `tests/page/run.py` (a private block sunk, a note
  marked private sunk whole, a day before the horizon sunk, `Ctrl+P` and
  back, unwrapping, undo). Photographed in Birnbaum.
- **Not yet seen in a real light theme.** The test harness cannot replay
  the shell's own theme switch.

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

### How it is built (2026-10-27): images, links, tables

The research came first: Obsidian 1.13–1.15, Typora, Bear 2, iA Writer, and
two local checks against Qt 6.12. Rendering follows one rule throughout:
**drawn, and the source shown where the cursor is**, as Obsidian's Live
Preview does.

**Links.js** reads the three forms (`[[…]]`, `![[…]]`, `[…](…)`) and
resolves a target by Obsidian's rule:
- a path from the root when it has a folder, or a partial path that ends a
  real one;
- else a bare name, case aside;
- when several files share it: the vault's root first (Obsidian's own,
  deliberately), then the note's folder, then the shortest path;
- a markdown path is relative to the note, decoded.

It resolves against an index of the vault's paths, read by one `find` when
a note first needs it and read again on a fresh open. `tests/tst_links.qml`
covers it.

**Images.** A line that is only an image becomes an `image` row: the picture
at the column's width, never wider than it is.
- Its size is read from the file's header by one `file` call per batch
  (`imageSizes`), so its room is kept before it loads and the note does not
  jump. Qt's own size is no help here: on a 2× screen it reports the size it
  decoded at.
- It is decoded no larger than it is drawn (`sourceSize`), loaded only
  within a screen of the view, and let go of further away.
- With the cursor on the line, its source shows above it, dim.
- A picture the vault does not have says so in a faint line.

**Links.**
- Drawn in the theme's blue and underlined. The brackets and the target
  stay in the text, one pixel and transparent, with `letter-spacing:
  -0.48px`, which cancels the half pixel each hidden character would
  otherwise take. That also tightens emphasis.
- A link the vault cannot resolve is faint, with no underline.
- With the cursor inside a link, it is drawn as written, dim, so it can be
  edited.
- A click follows it, and so does `Alt+Enter` at the cursor.
- `Ctrl+Alt+←` / `Ctrl+Alt+→` go back and on (Obsidian's keys), landing
  where the cursor was. A `#heading` or `^block` lands on its line.
- A day's note opens as a day, a note in `agents/` opens read-only, a file
  that is not a note opens in its own application, a web address in the
  browser.

**Tables.** A GFM table (a line of cells, then the line of dashes) is one
block, `table` rows.
- Drawn, it has a semi-bold header and a hairline under it, faint hairlines
  between rows, no rules down, and alignment from the `:--:` line.
- Each column is as wide as its widest cell. When the row would not fit,
  the narrow columns keep their width and the wide ones share the rest and
  wrap.
- Cells draw emphasis and links.
- With the cursor anywhere in it, every line shows as written.

**Not yet.** Ideas from the research, in the order they seem worth doing:
- `Space` on a picture's line for a lightbox, and arrows between the
  pictures (Obsidian 1.13.2).
- Tab between links, with `Space` to preview one and Enter to go.
- A table too wide even at its narrowest scrolls sideways in its block.
- A cell editor; the pipes lined up while the source shows.
- Embedded notes and blocks (`![[Note#^id]]`) drawn inline with a quiet
  rule.
- Footnote previews.

**Mermaid** is parked (2026-10-27): plan.md, *Not built, on purpose*.

### PDFs (built 2026-10-27)

- **Opening.** Your side of the Files tree lists PDFs beside the notes (the
  agent's side lists notes only), and the filter finds them. A link to a
  PDF opens it too, remembered in the way back.
- **Where it shows.** In the note's place, in `PdfPane.qml`: Qt's own
  `PdfMultiPageView`, fitted to the column, pages drawn as they come into
  view. It is in a `Loader`, active only while a PDF is open, so the
  document and its pages are let go of when it closes.
- **The note underneath.** The note stays loaded under it. While a PDF
  shows, the header names it, and its words for the note (private, ask,
  ask about this note, the agent's mark) step aside.
- **Keys** (the "in a PDF" place; a PDF is read-only here, so bare letters
  are free):
  - ↑↓ or j/k scroll;
  - PgUp/PgDn and Space/Shift+Space turn a page; Home/End go to the ends;
  - `Ctrl+F` or `/` finds (Enter for the next match, Shift+Enter the one
    before);
  - `+` / `-` / `0` size it;
  - `o` opens it in its own application;
  - Esc closes it, back to the note.
- **A known shortcut.** Qt's view keeps its scroller to itself, so the pane
  finds it among the view's children to scroll by keys.

**Not yet:**
- asking the agent about a PDF (the runner reads PDFs already, through
  pdftotext);
- a dark reading mode for white pages;
- keeping your place in a PDF between openings.

Tests: `tests/page/run.py` 12h. Pele can't run in Qt's own JavaScript
engine (ES2022: `matchAll`, `replaceAll`, `\p{}`, `Intl`), so it needs
Node, and its npm package fetched once. No note in the vault has a diagram
yet.

## Open, and documented as open

- **The middle ground.** `projects/`, `reference/` and `inbox/` are mixed
  authorship: the person's projects with agent-written handoffs. They fit
  neither "yours" nor "the agent's", so they are left out of the Files space
  for now. Deciding how they show is a decision of its own.
- **Tabs.** Following a link replaces the view. Several notes open at once,
  as tabs, is a later discussion.
- **A fuzzy switcher** across the notes root, if the tree's filter is not
  enough.
