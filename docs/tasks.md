# Where a task comes from and where it goes

**Status:** decided 2026-10-17, after an investigation and a grilling
(2026-10-16/17). This is the reference for how tasks stay consistent across
the note, the dashboard, the bar popup and `pomo`. It amends principle 2 of
`diary.md` and retires the 2026-10-10 "remove it too?" prompt.

## Why this exists

The student found tasks in the dashboard with no project that could be
neither opened nor deleted, and asked for a system that can be trusted:
where every task comes from and where it goes, and a deleted block taking
its tasks with it everywhere. Reading the code and the live store turned up
one cause under several symptoms — the same task kept in two copies (the
note line and `deadlines.tsv`) with a sync between them, and the sync was
where tasks went missing:

- **Two answers to "which project".** The store learned a project only from
  a `#tag` on the line; the notes also let a heading claim it. Five
  deadlines under `# Research Proficiency #respro › Building blocks` were
  respro to the notes and nothing to the store, and the dashboard showed the
  store's answer.
- **Enter did not go to a line on another day.** It unfolded a preview, while
  the keys sheet said "Go to the line". Every row of the "No project" band
  was from an earlier day, so none could be reached.
- **Delete did nothing on a deadline row**, silently.
- **Three ways of finding a line again.** Ticking matched the exact words,
  the list trimmed trailing spaces, dropping compared normalised words — so a
  line ending in a space could be dropped but not ticked.
- **Deleting a bound line asked "remove it too?", default no**, and typing
  past it counted as no; the deadline stayed, pointing at nothing (it
  happened once, 2026-10-13). **Deleting a block with several bound lines
  asked about the last one only** — the prompt was overwritten in a loop and
  the rest stayed silently. **A cut line never asked.** **Edits outside the
  page** (Obsidian, a deleted note) were never noticed. **A deadline whose
  line was gone** opened its note and put the cursor nowhere.

## Three ways to have "the same task" in many places

| | Where the task lives | How a block is known | Plain files? |
|---|---|---|---|
| **Org-mode agenda, Obsidian Tasks, Obsidian Bases** | The line in a file; lists are views that write back to it | By place and words | Yes |
| **Logseq (file version), Obsidian block links** | The line in a file | A stable id written into the file (`id::`, `^abc`), only on blocks something refers to | Yes |
| **Tana, Roam, Logseq's database version, Notion** | A record in a database; the page is a view of it | Every block has an id from birth; a block can be shown in many places, with typed fields | No |

The fourth arrangement — two copies kept in sync, what the Todoist and
TickTick integrations for Obsidian do, and what Longhand did — is the one
that drifts. In software terms: a single source of truth with derived views
does not drift, and two writable copies only stay reliable with machinery
(CRDTs, an event log) a notes tool does not need.

The database model is the most capable: a project's notes are a saved
search, a block shown in two places is one block, and an agent's
conversation hangs off a block's id and survives any edit. It is also the
one that breaks what Longhand is: notes Obsidian reads (the README),
principle 1 (plain files, no daemon), files a sync tool can carry, and
privacy that is easy to prove because the payload is assembled from files.
**Longhand takes the middle row**: the files are the truth, and the blocks
something refers to carry an id, so the views can feel like Tana without a
database.

## Two layers and their contract

- **The markdown layer** is the notes. Obsidian reads and edits them fully.
- **Longhand's layer** is everything around them: the deadline store, the
  ledger (`~/.local/state/longhand/ledger.json`), the agent's conversations
  (`agents/longhand/daily/<date>.json`), the usage log, the dashboard and the
  project views. Obsidian never sees it and never has to.
- **Between them**, marks that are plain markdown but mean more here:
  `#respro`, `📅 2026-11-20`, `⏳`, `^d30`, `[est:: 2h]`.

The contract that keeps the two compatible, however rich the layer grows:

1. **The person's words only ever live in markdown.** The layer holds what
   the system records or works out — ids, history (done, cancelled, grades),
   the agent's conversations, indexes, views — never a sentence the person
   wrote that is not also in a note.
2. **Marks read as plain text.** Strip Longhand away and every note still
   says everything that was written.
3. **The layer comes after the markdown and repairs itself.** An outside edit
   can break a link in the layer, never the words; Longhand notices and
   brings the layer in line.

Ids are never seen in Longhand (the page lifts `📅 … ^d30` off a line and
draws a date pill); Obsidian shows them as text. Simplicity is a
constraint: nothing here may put ids, or any new mark, in front of the
person inside Longhand.

## The rules

1. **The note line is the task.** The page, the bar popup and `pomo` all
   change a line through one line-writer, so editing in one place edits it
   everywhere. The store becomes a ledger of what a line cannot hold.
2. **Who owns which fact.** The line owns whether a deadline exists, its
   words and its project; the date and done/not-done may change on either
   side (the popup ticks while the page is closed, Obsidian ticks while
   Longhand is closed), and the side that changed since the two last agreed
   wins. The ledger keeps what they last agreed on. Grades and the time a
   deadline was done or cancelled are the ledger's alone.
3. **Identity by kind.** A deadline keeps its tag in the line (`^d30`): it
   survives any edit, Obsidian included, and Obsidian can link to it. A block
   sent to the agent is known only in the layer (its words and place,
   followed through every edit in the page), so prose never carries a tag;
   a heavy rewrite in Obsidian may lose its conversation, which costs little.
4. **A deadline is cancelled exactly while no note holds its tag.** Deleting a
   line or a block cancels its deadlines; pasting the line anywhere, or
   undoing, brings them back as they were. Cutting and moving need no rule of
   their own. Nothing is erased from the store: cancelled is history.
5. **The person is told, never stopped.** A passing word under the cursor,
   where the page already says such things ("2 deadlines cancelled with
   their lines · Ctrl+Z brings them back"), that waits for nothing,
   and cancelled rows that stay in the dashboard until tomorrow, as done ones
   do. The yes/no prompt is gone.
6. **Edits made elsewhere are caught when the page or the bar popup opens.**
   Nothing watches in the background (the watcher was refused on
   2026-09-17).
7. **A deadline born without a line** (an accepted agent proposal that
   matched no checkbox, `pomo deadline add`) waits in a "not in a note yet"
   band and counts as the agent's. Renaming it lets the person write over the
   agent's words; Enter writes it into today's note, which makes the act the
   person's. The ledger keeps its origin and the agent's first wording, and
   the row says "from the agent · rewritten by you" once it has been. A done
   deadline that never had a line (the first two, from before binding) is
   history and stays out of the way.
8. **The dashboard acts on every row the same way.** Enter goes to the line,
   on any day. Delete cancels it: the line becomes `- [-] … ❌ <today>` and
   stays in the note, because deleting words happens only in the note.
   `Ctrl+E` or `F2` renames in place (Todoist's and Obsidian's keys for it;
   F2 since 2026-10-28) — the one other place
   besides `t` where the dashboard takes typed words; details stay in the
   note, as indented lines under the task, and the row says how many lines
   it has. One way of finding a line again everywhere.
9. **Project:** the line's own `#tag`, else the nearest tagged heading above
   it, else none. The store's project is copied from this, never set apart
   from it.
10. **An empty box is not a task.** `- [ ]` with no words is a leftover.

## Where a task comes from, and where it goes

| Born | Lives | Ends |
|---|---|---|
| A checkbox typed in a note | the line, and its silence clock in the layer | ticked, cancelled (`[-]`), or the line deleted; out of the dashboard (never the note) after 7 silent days, 30 for a task |
| A checkbox with a date at its end (bound as the line is left, or at once with Tab), or Ctrl+D | the line, tagged `^dN`, plus its ledger entry | done; cancelled by Delete; cancelled while its line is gone; stepped aside (hidden) when still open a fortnight past its date |
| An agent proposal accepted, matched to a checkbox | that line, as above | as above |
| An agent proposal accepted, no checkbox matches | "not in a note yet", origin agent | written into today's note (then as above), or cancelled |
| `pomo deadline add` | "not in a note yet" | as above |

## Boxes inside quotes and callouts (2026-10-27)

A box can stand inside a quote or a callout (`> - [ ] call mum`). Its `> `
layers are part of its lead and never of its nesting: nesting holds inside
the quote and never crosses its edge, and a box's details stay inside its
quote. `task.py` and `Task.js` read it the same way, as twins, and
`test_task.py` holds them to it.

A box inside a `> [!private]` callout is **private**. So is a box on a day
marked private, or on a day before the agent's horizon.
- **The dashboard** lists it, with a lock.
- **Nothing of the agent's** is offered on it: its row shows no "chat", and
  Ctrl+Enter, C and Alt+→ say so instead.
- **The agent's readers** (`visible_only`) never carry it.
- **Deadlines** (the student's call): a box in a private block never
  becomes one, however it is dated. The date stays words on the line, so
  nothing of it reaches the deadline list the agent reads.
- **A box that was already a deadline** when its block became private stays
  one. Ctrl+P says so rather than quietly unbinding it.

## How it is built

- **`longhand-check`** (`cli/longhand-check`, Python) is the line-writer and
  the check: it reads every daily note, finds each tagged line, and brings
  the store, the ledger and the lines in line with each other by the rules
  above. It changes only a line's facts (its tick, its date tail, a stale
  tag) and never its words. It is a program of its own, not the agent
  runner: `longhand-agent` keeps refusing to write under the daily folder,
  which is how the agent can say it never touched the prose.
- The page runs it when it opens and after an edit takes a tagged line away
  or brings one back, telling it which note is open so the page writes that
  one itself (it is live in the editor). The bar popup runs it when it opens
  and after it changes a deadline. `pomo`, run by hand in a terminal, runs it
  after a change.
- `cancelled` is a status of the store, beside open, done and hidden, with
  the time it was cancelled in the done-at column.

## Parked

- **A project as one continuous page:** every section of a project in one
  scroll, newest first, editable in place, each edit written to its day's
  note. It needs what this builds (writing another day's note while it is on
  screen, finding blocks by identity), so it comes after.
- **A sent block's identity in the layer** (rule 3's second half) — the
  agent's conversations are still keyed by a hash of the block's words, so
  an edit detaches them. Its own piece of work.
