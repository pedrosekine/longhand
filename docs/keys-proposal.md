# Keys: a proposal after the benchmark apps

_Proposed and grilled 2026-10-27; decided. Slices 1 and 2 built 2026-10-28,
the rest not yet. Building moves each row into `plugin-page/Shortcuts.js`, and
`tools/keys_guide.py` rewrites [keys.md](keys.md); navigation.md, the
agent's manual and the keys sheet follow._

The aim: someone arriving from Obsidian, Todoist, Notion or Craft finds their
hands already know most of the page, and the rest can be guessed from the
words on screen.

## The rules

1. **A benchmark app's key wins** when one exists for the same action. When
   the apps disagree, the one closest to the place wins: Todoist for the
   dashboard and lists, Obsidian for the note's Markdown, Notion and Craft
   for formatting and the page's frame.
2. **With no benchmark, the key is the first letter of the word on screen,**
   and that word is the same in the row, the hint line, the tooltip and the
   keys sheet. One action, one word.
3. **Lists use bare letters** (Todoist, Linear). Where you type, an action
   uses a modifier, and an action that exists in both places has the same
   modifier in both (tick is `Ctrl+L` in the note and on the dashboard).
4. **A word never changes with state.** State is shown by a mark, never by
   a new word, so the key under the word never changes either.
5. **One key, one action, in one place.** A key may mean different things in
   different places only when the benchmark apps do the same (Enter, Esc,
   Shift+Enter).
6. **The key acts on this block; Shift and the key, on the whole** (the
   note, the day). Added 2026-10-27: privacy and chat follow it. It governs
   new pairs only; no Shift pairs are made for the sake of it. To reflect
   on: scope may come in more than two levels (a line, a block, a section,
   the note, the day), and the rule may grow into one about those levels.
   For now it is block and note.

## The page: views and panes

Today the panes are three brackets (`Ctrl+[` `Ctrl+\` `Ctrl+]`). In Notion
and Craft, `Ctrl+[`/`Ctrl+]` mean back and forward, and `Ctrl+\` toggles the
sidebar; on Spanish, German or Danish layouts the brackets and `\` need
AltGr. The panes move to the digits, left to right, which are the same key on
every layout.

| Action | Now | Decided | Benchmark |
|---|---|---|---|
| The left pane: go there; in it, calendar ↔ files | `Ctrl+[` · `Ctrl+{`/`Ctrl+}` | **`Ctrl+1`** | Todoist and Craft switch views by number; here the number is the pane's place |
| The middle: go there; in it, note ↔ dashboard | `Ctrl+\` · `Ctrl+T` | **`Ctrl+2`** | As above. `Ctrl+T` is "new tab" in Notion, Craft and every browser |
| The right pane: go there; in it, the day's chat ↔ this block's or task's chat | `Ctrl+]` | **`Ctrl+3`** | As above |
| The sidebar: open or close | `Ctrl+[` · `Ctrl+Shift+B` | **`Ctrl+\`** | Notion, Craft `Cmd+\`; Todoist `M` |
| The agent's pane: open or close | `Ctrl+]` · `Ctrl+J` | **`Ctrl+Shift+\`** | VS Code pairs `Ctrl+B` / `Ctrl+Alt+B` for the two sidebars |
| Today's note | `Ctrl+H` · `Alt+Home` | unchanged | Todoist `H` home |
| Back / forward | `Ctrl+Alt+←` / `→` (links only) | `Ctrl+Alt+←` / `→` · **`Ctrl+[` / `Ctrl+]`**, through links, views and days | Obsidian `Ctrl+Alt+←→`; Notion, Craft `Ctrl+[ ]` |
| Move between open panes | `Alt+←` / `Alt+→` | unchanged | Hyprland's `Super+arrows` |
| The day before / after | `Alt+[` / `Alt+]` · `Ctrl+PgUp` / `PgDn` | unchanged | No benchmark (Obsidian's daily notes leave it unassigned) |
| Settings | `Ctrl+,` | unchanged | All four |
| The keys | `Ctrl+/` | `Ctrl+/` · **`?`** in lists | Todoist `?`; Google apps `Ctrl+/` |
| Find anything (notes, tasks, actions) | — | **`Ctrl+O`**, not built | Obsidian palette `Ctrl+P`, quick switcher `Ctrl+O`; Notion `Ctrl+P`/`Ctrl+K`; Craft quick open `Cmd+O` |
| Overlay or window | `F11` · `Ctrl+Alt+P` | unchanged | Fullscreen convention |

Dropped: `Ctrl+T`, `Ctrl+Shift+B`, `Ctrl+{`/`Ctrl+}`, and the brackets as
panes.

**Decided (grilling, 2026-10-27):**
- **A number per pane, left to right** (Pedro's, over a number per view):
  the screen is the map, and each pane holds two things. From outside a
  pane its number goes there, opening it on what it showed last; from
  inside it switches to the other thing (as `Ctrl+\` "go there; in it,
  flip" works today). In the right pane, "this chat" is the cursor's block
  in the note, or the selected task on the dashboard. Reaching files takes
  a second press when the left pane shows the calendar: accepted.
- **The note `Ctrl+2` brings back is the day you were on;** `Ctrl+H` and
  `Alt+Home` stay "today".
- **Back and forward go through one history** of what the middle shows:
  links followed, note ↔ dashboard, a day before or after, a file opened.
  Opening or closing a side pane is not a step.
- **The toggles close the panes:** `Ctrl+\` the sidebar, `Ctrl+Shift+\`
  the agent's pane. Esc still only gives the keys back to the
  middle (2026-10-24).
- **`Alt+←`/`Alt+→` keep moving between panes,** as Super+arrows move
  between Hyprland's windows.
- **The agent's pane opens and closes on `Ctrl+Shift+\`,** the mirror of
  the sidebar's `Ctrl+\` (as VS Code pairs `Ctrl+B` and `Ctrl+Alt+B`).
  `Ctrl+J` was kept at first, then dropped once `Ctrl+3`, `Ctrl+Enter` and
  `Ctrl+Shift+Enter` all reached the pane: Notion's documented AI key is
  `Ctrl+Shift+J`, so `Ctrl+J` taught nobody anything. Hovering
  over what opens each pane (the date for the sidebar, the seal for the
  agent's pane) shows its keys, so the pair is remembered.
- **"Find anything" is built as a task of its own** after this key work.
  Its key was first reserved as `Ctrl+K`; then `Ctrl+K` went to links (the
  note, below). **The switcher is `Ctrl+O`,** Obsidian's quick switcher
  and Craft's quick open; `Ctrl+P` stays privacy's (rule 6).
- **`?` shows the keys wherever bare letters work** (the dashboard, the
  sidebar's lists, files), beside `Ctrl+/` everywhere.
- **A `/` menu in the note,** as in Notion: one list in two groups, the
  actions on this block (chat, tick, date, private, move, copy a link) and
  what the block can become (a checkbox, a heading, a quote, a callout).
  It opens only at a line's start or after a space and closes when nothing
  matches what is typed. **Esc leaves the `/` as typed,** an ordinary
  character. It shares one engine with the switcher (page-wide
  there, this block here), built in the same task, and every item shows its
  key.
- **Checked: why `Ctrl+\` seemed to open the agent's pane.** Not the
  keyboard: the US international layout gives `\` plainly, and no Hyprland
  bind takes `Ctrl+\`. It is the rooms coming back with their views
  (navigation.md): `Ctrl+\` flips the middle, and the agent's pane follows.
  The day's chat, once opened, stays open beside the dashboard, wider than
  beside the note; a block's chat, hidden while the dashboard is up, comes
  back with the note. The usage log shows it that way (the day opened, then
  the dashboard). The decided keys keep the rule, now said by `Ctrl+3`'s
  "this chat": the cursor's block beside the note, the selected task beside
  the dashboard, the day's chat beside either. **Decided: `Ctrl+2` keeps
  the rule;** the agent's pane follows the middle.

## Talking to the agent: one word, one key

| Action | Now | Proposed | Benchmark |
|---|---|---|---|
| Chat about this (the block, the task, the proposal) | note: `Ctrl+Enter` (needs a sign), `Alt+→`; dashboard: `Ctrl+Shift+Enter`, `Enter` on a proposal | **`Ctrl+Enter`** everywhere, and **`C`** in lists | Craft `Cmd+Return` opens the AI assistant; Todoist `C` opens a task's comments; `Ctrl+Enter` sends in chat and mail |
| The day's chat | `Ctrl+Shift+Enter` (note: pointing at this block; dashboard: the task's chat) | **`Ctrl+Shift+Enter`, the day's chat everywhere** | Rule 6 |

- **The word is "chat"** in the note's header, on the dashboard row and in
  the sheet, in place of "ask" (and "reply" once answered), "talk" and "the
  conversation". It names the thing, not a turn in it, so it doesn't change
  once the agent has answered. Rule 4.
- **`Ctrl+Enter` with no sign** opens the block's chat with the box ready,
  as `Alt+→` does now. With a sign (a checkbox, a `?`, a tick) it sends, as
  now, and the agent speaks first.
- **What it's about shows as a mark, not a new word:** the gutter bar the
  note already uses. Accent: a reply you haven't read. Dim: read. A moving
  light: the agent is thinking. Nothing: no chat yet.

**Decided (grilling, 2026-10-27):**
- **The word is "chat",** everywhere and in every state: the note's header
  (in place of "ask"/"reply"), the dashboard row, the right pane ("the
  day's chat", "this block's chat"), tooltips and the keys sheet.
- **`Ctrl+Enter` with no sign opens the block's chat,** box ready, you
  speak first; with a sign it sends as now and the agent speaks first. The
  signs keep their other jobs (what kind of help, the automatic pass).
- **`Ctrl+Shift+Enter` is the day's chat, everywhere** (rule 6, decided
  after first dropping it: its fault was two meanings, not the key). In a
  note from Files, the whole is that note, so it opens the note's chat
  ("ask about this note", built 2026-10-27, already on this key). `@`
  still points at a block from the day's box.
- **Enter on a proposal or question opens its chat,** as now; `C` and
  `Ctrl+Enter` do the same. Enter never commits; Space and `E` accept.
- **The keys: `C` in lists and `Ctrl+Enter` everywhere,** both opening the
  same chat. On the dashboard `Ctrl+Enter` therefore no longer means done.
- **Where the word shows on a row:** at the row's end, on the selected row
  and the row under the mouse only ("chat C"). Once a task has a chat, its
  selected row also shows the chat's last line under the task; a row with
  no chat stays one line. Every other row says only what its gutter bar
  says.
- **`Alt+→` in the note, with nothing to its right, still opens the
  block's chat:** the pane to the right is where the chat lives.

## The note

| Action | Now | Proposed | Benchmark |
|---|---|---|---|
| Bold, italic | `Ctrl+B`, `Ctrl+I` | unchanged | All |
| Inline code | `Ctrl+E` · ``Ctrl+` `` | unchanged | Notion `Ctrl+E` |
| Strikethrough | `Ctrl+Shift+S` | unchanged | Notion `Ctrl+Shift+S` |
| Tick a checkbox | `Ctrl+L` | unchanged | Obsidian `Ctrl+L` (its current default) |
| A date: bind, move, unbind | `Ctrl+D` | unchanged | None agree: Notion duplicates, Obsidian deleted a paragraph, Craft uses `Cmd+Shift+D` for a deadline |
| Move the line | `Alt+↑` / `Alt+↓` | unchanged | VS Code; Craft `Cmd+Opt+↑↓` |
| Follow a link | `Alt+Enter` | unchanged | Obsidian `Alt+Enter` |
| Private block / note | `Ctrl+P` / `Ctrl+Shift+P` | unchanged (rule 6) | `Ctrl+P` is Obsidian's command palette; the switcher takes `Ctrl+O` instead |
| Make a link | — | **`Ctrl+K`** | Notion, Craft, Obsidian |
| Find, undo, redo, select | as now | unchanged | All |

**Decided (grilling, 2026-10-27):**
- **`Ctrl+K` makes a link,** as in Notion, Craft and Obsidian, and only
  that: one key, one action (Pedro, over Notion's split with the switcher).
- **The rest of the note's keys stay** (`Ctrl+B`, `Ctrl+I`, `Ctrl+E`,
  `Ctrl+Shift+S`, `Ctrl+L`, `Ctrl+D`, `Alt+↑↓`, `Alt+Enter`).

## The dashboard (Todoist's keys)

| Action | Now | Proposed | Benchmark |
|---|---|---|---|
| Move | `↑↓` · `J` `K` · `Home` `End` | unchanged | Todoist |
| Open: go to the line (a proposal: its chat) | `Enter` | unchanged | Todoist `Enter` opens the task |
| Done | `Space` · `E` · `Ctrl+Enter` · `Ctrl+L` | `E` · `Space` · `Ctrl+L` | Todoist `E`. `Ctrl+Enter` goes to chat |
| Schedule | `T` · `Ctrl+D` | `T` · `Ctrl+D`; **`Shift+T`** removes the date | Todoist `T`, `Shift+T` |
| Priority | `P` cycles | unchanged | Linear `P`. Todoist's `1`–`4` assume four levels; ours are three |
| Chat | `Ctrl+Shift+Enter` | **`C`** · `Ctrl+Enter` | Todoist `C` comment |
| Rename | `Ctrl+E` | `Ctrl+E` · **`F2`** | Todoist `Ctrl+E` edit; Obsidian `F2` edit the title |
| Cancel; on a proposal, decline | `Del` · `Backspace` | unchanged | Craft `Delete`; Todoist `Shift+Delete` |
| Put aside (again: back) | `S`, shown as "not now" | `S`, shown as **"set aside"** | No benchmark; rule 2 |
| Its clock starts again | `R`, shown as "keep" | `R`, shown as **"renew"** | No benchmark; rule 2 |
| Grade | `G` | unchanged | Rule 2. Todoist and Gmail use `G` to start "go to", which the views by number make unneeded |
| Next / previous from the agent | `N` / `Shift+N` | unchanged | Gmail `N` next |
| Plan now | `Ctrl+R` | unchanged | "Refresh" |
| Undo, back | `Ctrl+Z`, `Esc` | unchanged | Todoist |

**Decided (grilling, 2026-10-27):**
- **"Not now" becomes "set aside"** (`S`), so the word starts with its key.
- **"Keep" becomes "renew"** (`R`). Bump, hold, reset and wake were
  weighed; renew answers "goes quiet in 3 days" and keeps its letter.
- **`Shift+T` removes the date, `F2` renames beside `Ctrl+E`, and done is
  `E`, `Space` and `Ctrl+L`** (no longer `Ctrl+Enter`, which is chat).
- **Priority stays on `P`,** cycling three levels. No digits: bare digits
  beside `Ctrl+1`–`3` would be easy to confuse.

## Elsewhere

- **Sidebar lists:** `Ctrl+Enter` (put the #tag) becomes **`#`**, the tag's
  own sign (Todoist types `#` for a project). "Start the class" becomes
  **"new section"** on **`S`**.
- **Calendar:** `T` today (Todoist's calendar, Google Calendar), arrows,
  `Enter`, `PgUp`/`PgDn`: unchanged.
- **Settings:** the `Ctrl+Shift+` letters on single settings (sound, pointer)
  give way to the list's own keys: `↑↓` to a setting, `Space`/`Enter`
  changes it, as in any settings list. `Ctrl+Shift+S` then means
  strikethrough only.
- **Decided (grilling, 2026-10-27):** the sidebar's `#` puts the tag, and
  settings becomes a list. Found while deciding: `↑↓` in settings walks
  only the calendars today; the sound, the pointer, the notebook, what the
  agent may do and what it may search are reached only by their own
  `Ctrl` letters. So "settings as a list" means `↑↓` walking every setting,
  `Space`/`Enter` changing or opening it, and those letters going.
- **"Start the class" gets a neutral name** (Pedro: Longhand is not only
  for students). "New note" was weighed and kept for a real new note file,
  which is not built: parked in `docs/plan.md` (Notes beyond the calendar),
  with `Ctrl+N` kept free for it. **It is "new section", on `S` in the
  sidebar's lists** (Todoist's `S` adds a section): it writes `# Name #tag`
  into today's note. `Shift+Enter` stays in the `@` list, and the `/` menu
  lists it by name. "Insert the tag" was weighed and left to the `#` key,
  which puts the tag at the cursor.
- **Removing in settings is `Del`,** as everywhere else (a calendar, a
  notebook note), in place of `Ctrl+Shift+Backspace`. The row asks first,
  "Remove this calendar? Enter / Esc", as the page asks before deleting a
  line's deadline. Its other keys stay (`Ctrl+E` renames, `Ctrl+R`
  fetches).
- **Files in the sidebar keep their keys** (`J`/`K`, `H`/`L`, `/`, `Enter`,
  `Esc`), with `?` added.
- **The calendar, find, the chat box, a PDF and the margin stay as they
  are** (decided). They already follow the conventions (Enter /
  Shift+Enter, Esc).

## Build plan

Five slices, in this order, each shippable alone and each ending the same
way: every suite passing (`python3 tests/run_all.py`), the page installed
into the live shell and the shell restarted. They run one after another,
not side by side: every slice edits `Shortcuts.js`, `Page.qml` and
`tests/page/run.py`.

What every slice touches, beyond its own code:
- **`plugin-page/Shortcuts.js`:** an action keeps its id when its meaning
  stays and only its key moves; a new meaning gets a new id. An id that
  goes is simply dropped: `load()` already skips ids it does not know, so
  an old `keys.json` cannot break (Pedro's is empty).
- **`agent/manual.md`:** its `{key:<id>}` follow the ids;
  `tests/test_manual.py` fails on an id that is gone.
- **`docs/keys.md`:** rewritten by `tools/keys_guide.py`;
  `tests/test_keys_guide.py` fails while it is stale.
- **The docs that describe the keys:** `navigation.md` (panes, Esc,
  history), `agent.md` ("Talking about a proposal", the day's chat),
  `diary.md` (the signs rule), `tasks.md` (the dashboard), and a line in
  `plan.md`'s *Built — to evaluate in use* for what to watch.
- **`tests/page/run.py`:** the checks that press the old keys are rewritten
  to the new ones, each new behaviour gets a check, and each check is proven
  by breaking the code it guards, as the suite does now.

### 1 · Chat on a task (the reason this started)

_Built 2026-10-28._

Keys and words only; nothing new is fetched.
- **The word "chat":** the note header's "ask"/"reply" becomes "chat"; the
  tooltips, the hint lines, the keys sheet, the margin's empty line and the
  day pane's lines say "chat" where they say ask, talk or conversation.
- **`Ctrl+Enter` in the note:** without a sign it opens the block's chat,
  box ready (as `diveIn(true)`); with a sign it sends as now
  (`sendCurrent`, [Page.qml](../plugin-page/Page.qml) `noSignHint` goes).
- **`Ctrl+Shift+Enter`:** the day's chat everywhere (`dayHere` in the note
  stops pointing at the block; `dashTalk` stops opening the task's chat);
  in a note from Files, that note's chat, as now.
- **The dashboard:** `C` and `Ctrl+Enter` open the selected row's chat
  (`talkFocused`); done loses `Ctrl+Enter`. The row shows "chat C" at its
  end on the selected row and under the mouse; the hint line and the row's
  tooltip name it.

### 2 · What a row's chat shows

_Built 2026-10-28._ As planned, with two details settled while building:
unread is kept per chat (the thread's key, which a box under another
shares), and a margin reply already read in the note is not unread on the
dashboard. The moving light has no check: it lasts as long as an answer
takes, which the suite cannot hold still.

Needs data the dashboard does not have: a row cannot tell today whether its
task has a chat (that is fetched only when one opens, `thread --key`).
- **The runner:** `longhand-agent next` gives each task and deadline a
  `chat` field: how many turns, the last one (who, its first line, when),
  and whether the agent is answering it now. It reads the same two sources
  the thread view merges: the ledger's `threads` and the margin records in
  the day's state.
- **Unread:** a chat is unread while its last turn is the agent's and came
  after the chat was last opened; the page keeps the last opening per task
  in `page.json`, as it keeps the last proposal seen.
- **The row:** the gutter bar as in the note (accent unread, dim read, a
  moving light while answering, nothing without a chat), and on the
  selected row with a chat, its last line under the task.
- Tests: `tests/test_agent.py` (or its own file) for the `chat` field;
  the page suite for the bar's states and the last line.

### 3 · Panes by number

- **`Ctrl+1` / `Ctrl+2` / `Ctrl+3`:** from outside a pane, go there,
  opening it on what it showed last; inside, switch between its two
  things (the sidebar's spaces; the note and the dashboard; the day's chat
  and this block's or task's chat). `paneKey` grows the switch for the left
  and right panes as the middle has it now.
- **`Ctrl+\` / `Ctrl+Shift+\`:** open or close the sidebar / the agent's
  pane.
- **Gone:** the brackets as panes, `Ctrl+T`, `Ctrl+Shift+B`,
  `Ctrl+{`/`Ctrl+}`, `Ctrl+J`. `Alt+←`/`Alt+→` and Esc as they are.
- **The rule kept:** the agent's pane follows the middle.
- **Hover:** the date and the seal name their pane's keys.
- Rewrites the page suite's 12b ("The panes"), and the calendar checks
  that use `Ctrl+[`.

### 4 · One history: back and forward

- `Ctrl+[` / `Ctrl+]` beside `Ctrl+Alt+←`/`→`.
- **What is a step:** a link followed (as now), the note ↔ the dashboard, a
  day before or after, a file opened. `placeNow()` learns the middle's view
  (note or dashboard) as well as the note and the cursor; `goTo()` puts it
  back. Opening or closing a side pane is not a step.
- Depends on slice 3 (the brackets free).

### 5 · The rest of the map

- **The dashboard:** `Shift+T` removes the date; `F2` renames; "not now"
  reads "set aside", "keep" reads "renew"; `?` opens the keys.
- **The note:** `Ctrl+K` makes a link: with words selected, `[words]()`
  with the cursor in the parentheses for the address, as Obsidian does;
  with none, `[]()` with the cursor in the brackets.
- **The sidebar's lists:** `#` puts the tag; "start the class" becomes "new
  section" on `S` (and `Shift+Enter` in the `@` list); `?` opens the keys.
- **Settings as a list:** `↑↓` walks every setting, not only the calendars;
  `Space`/`Enter` changes or opens it; `Del` removes a calendar or forgets
  a notebook note, after "Remove this calendar? Enter / Esc". The settings
  sheet's own letters go (`Ctrl+Shift+S`, `Ctrl+Shift+M`, `Ctrl+K`,
  `Ctrl+M`, `Ctrl+F` there; `Ctrl+Shift+A`, `Ctrl+E`, `Ctrl+R` on a calendar
  row stay).

### After, each a task of its own

- **The switcher (`Ctrl+O`) and the `/` menu,** one engine: the actions
  table in `Shortcuts.js` is already the list of what can be done, with a
  key for each.
- **A new note** (`Ctrl+N`), parked in `plan.md`.

## Sources

Todoist's keyboard shortcuts (help page, Windows); Notion's keyboard
shortcuts (help page); Craft's shortcuts (support.craft.do); Obsidian's
editing shortcuts (obsidian.md/help) and the forum note that "Toggle
checkbox status" moved to `Ctrl+L`, with `Ctrl+Enter` opening a link in a
new tab.
