# The diary — reference plan

**Status:** decided 2026-09-17 after a full design review. This is the
reference for building. Supersedes `todo-capture.md` (deleted) and the
"agent side" sketches in `student-os.md`, whose open questions are resolved
here. Nothing below is built yet unless a phase is ticked in `plan.md`.

## What it is

A blank page inside the Omarchy shell where a student writes the day, and an
agent that reads it and answers in the margin. Sessions and deadlines are
features inside that page. The shipped timer and deadline work is the
structured layer underneath.

Built for one student first, installable by others later. Hard dependencies:
Omarchy and opencode. The student brings one model key. Every path (vault,
daily folder, curriculum folder, agent folder) lives in one config file, never
in code, and the vault path is never recorded in this public repo.

## Principles

1. **Agentic-first.** Plain files plus one command. No daemon, no API, no auth.
2. **The canvas is the student's, the store is the system's.** Every
   thought and every word in a note is written by the student, only ever by
   the student; the agent talks in its own place (the margin, the chat),
   never in the canvas. Structured facts (due dates, status, project) live
   in the store the CLI owns, and when they disagree the store wins — so the
   page may change the *facts* on a line that stands for a deadline (its
   tick, its date, its anchor), never its words. (Amended 2026-10-11.)
3. **Consent is an allowlist, enforced locally.** The model sees exactly what
   local code assembled: today's note minus private blocks, the agent's own
   knowledge files, the curriculum folder, the timer report. Nothing else on
   disk, ever. Every payload is logged before inference, so "the private block
   was not sent" is a test, not a promise.
4. **Never out of nowhere.** The agent runs only when the student acts in the
   page. It may be proactive *inside* that moment — surface an observation, a
   missed task, an opportunity — but it never notifies, never schedules itself.
5. **Speak with evidence.** Every observation or suggestion carries the
   evidence it rests on. "Two sessions on DORO, none on the seminar paper due
   Friday" is allowed. "Time to study" is not.
6. **Design to become less needed.** Dismissing a suggestion is memory: the
   same point is not raised again unless the evidence changes. Success is
   commitments met and self-initiated sessions, never time in the page.
7. **One device is enough.** No relay, no server, no second machine in the
   loop. Syncthing may exist on the machine; it is not part of the design.
8. **Rich on the surface, plain underneath.** The page may be as polished as
   we like, but the note stays GFM markdown plus callouts, readable by git,
   Obsidian, and the agent alike.
9. **The agent reads everything it is allowed, produces nothing submittable.**
   Questions, plans, observations, proposals. Never an essay.

## Files

All paths relative to the vault unless stated. Names of folders are config.

| What | Where | Written by |
|---|---|---|
| Today's note | `inbox/Daily/YYYY.MM.DD.md` | the student, through the page |
| Day transcript | `agents/student/daily/YYYY.MM.DD.md` | the runner |
| Day state | `agents/student/daily/YYYY.MM.DD.json` | the runner, rendered by the page |
| Knowledge | `agents/student/knowledge/` | the runner; the student may edit |
| Curriculum | folder named in config | the student; read-only for the agent |
| Deadlines, sessions | `~/.local/state/omarchy-student/` (existing) | the CLI only |
| Payload log | `~/.local/state/omarchy-student/payloads/` | the runner; never synced |
| Cost ledger | `~/.local/state/omarchy-student/cost.tsv` | the runner |

**The note.** Created from a template by whoever gets there first (page or
Obsidian); both check for existence. The template is one line: a link to the
day's transcript, `[[agents/student/daily/YYYY.MM.DD|agent]]`, unresolved until
the first reply creates it. No code path except create-if-missing ever writes
this folder. The page is the one program that edits the note: the student's
typing and ticking, and — under principle 2 — a bound line's tick, date and
anchor brought in line with the store. The only line the page writes whole
is a deadline's, when the student asks for it from what's next.

**The transcript.** For the student. One section per block: the quoted block,
the reply, proposals as checkboxes, and the dive-in dialogue if there was one.
Cost of each run in the section header.

**The state file.** For the page. Per block hash: state (`seen` | `reply`),
reply text, proposals, opencode session id, timestamps. Plus the day's
suggestions. Not pretty; the page renders it.

**Knowledge, three kinds only.** `profile.md` (who the student is, courses,
how they want to be spoken to); `subjects/<name>.md` (deliverables, what is
going on); `patterns.md` (intention→outcome record, observed habits — the
runner computes the facts from the notes' checkboxes and puts them in the
payload; the model writes what they show). A file whose purpose the agent
cannot state does not exist. One exception, system-owned:
`knowledge/dismissed.md`, written by the runner when the student waves a
suggestion off, read by the model, never written by it.

**Curriculum.** Student-provided course material. PDFs are converted to
markdown once on arrival by local code, so payloads are always text and always
logged. Always in the allowlist.

**Store additions.** `deadlines.tsv` gains `subject` and `link` columns. A
project *is* a subject; milestones are simply deadlines under a subject. No new
record type. Sessions gain an optional `--for <deadline id>` on `pomo start`.
An unlogged session is never treated as neglect — group work goes unlogged, and
that is fine — only as something to ask about.

## Blocks

A block is a paragraph or a list item with its indented children, identified
by a hash of its text. No ids are written into the note. Editing a block makes
it new and unprocessed, which is the honest behaviour. Block splitting is a
pure function shared by the page and the runner.

**Private.** A `> [!private]` callout hides a block. Frontmatter `agent: false`
hides the day. Both are removed by local code before the payload is built.

## The loop

**Triggers, all from the page, never by accident.** No file watcher. Two
things must both be true for a block to reach the model: it carries a
**sign** for the agent, and the student **says so**.
- The signs: a checkbox line (`- [ ] …`), a line starting with `@`, a line
  ending with `?`, a tick. Finishing an `@` or `?` line with Enter
  **stages** the block — hollow accent mark in the gutter — and shows a
  washed prompt under the cursor, "send to agent? [no] yes". An arrow then
  Enter sends; Enter again or Esc ignores it and the page behaves as usual.
  No letter answers a prompt (since 2026-10-11): a typed "y" is writing —
  in Spanish it is a word.
- **A checkbox list is one submission.** Enter on an item just gives the
  next bullet. Leaving the list (Enter on an empty bullet) stages the whole
  run of adjacent items as a group with one prompt; the reply attaches to
  every item, so ticking one later does not lose it for the others. A tick
  stages the list the same way. Typing `- []` becomes `- [ ] `.
- `Ctrl+Enter` sends the staged block or list under the cursor at any later
  moment. On a block without a sign it sends nothing and a washed line under
  the cursor says why.
- Opening the page runs one automatic pass (skipped when nothing is new), so
  answers are waiting when the student comes back. Its observations have no
  block; they are kept in the state file for the suggestions panel.
- Decided 2026-09-17 after the first day of use: automatic sends on Enter
  fired on ordinary journaling questions; the sign + confirmation pair is
  the safety mechanism.

**Memory across a day.** Each call is stateless on the provider side and
opencode only replays a session's history; nothing is remembered for free.
So every payload carries a compact "what you already said today" section
(one line per answered block, replies trimmed, suggestions folded) and the
prompt forbids answering twice. Sessions stay per block; a per-day session
would replay the whole day on every call for the same effect at more cost.

**Language.** `languages` in the config, first is the default. The runner
detects which of them the triggering block is written in (a stopword check,
no dependencies) and states it as a fact at the top of the payload: "the
student wrote this in German, answer in German; never any language outside
the list". A small model asked to "use the student's language" answered in
Dutch to an English note; told beats inferred.

**Run.** The page saves the note and calls the runner with the block that
fired. The runner:
1. builds the context from the allowlist, strips private blocks, writes the
   payload log;
2. runs `opencode run` with a dedicated agent that has **no tools** — the
   permission block denies everything — with DeepSeek 4.1 flash via OpenCode
   Go, one config line;
3. receives one structured message: reply text, proposals, knowledge updates,
   suggestions;
4. applies it locally: appends to the transcript, updates the state file,
   writes knowledge files, records cost;
5. exits. Nothing is resident between runs.

Adding tools later is one line in the agent definition; starting without them
is what keeps the audit trail complete and reversible.

**What a fresh checkbox produces.** A proposal to the deadlines panel when the
line carries a date or a known subject; one question when it lacks both;
never silence. Ticking a proposal makes local code run `pomo deadline add`.
The model never touches the store.

**What a tick produces.** Possibly a follow-up: a grade reminder, a cross-check
("what about x and y, did you deliver those?"). Possibly nothing.

**Never** asks about unticked boxes. The open-checkboxes panel is the reminder.

**Suggestions.** Found during any run: upcoming tasks, late tasks with a
deadline, recently added tasks without one, opportunities in the curriculum.
Evidence attached. Shown in the page only (`Ctrl+T`, under the open tasks),
never as a notification. Near-duplicates are folded by content-word overlap.
Dismissal is written to `knowledge/dismissed.md` and hides every variant.

**Dive-in.** A plain chat about one block, continuing that block's opencode
session (`--session`), persisted into the same transcript section. May produce
the same proposals as a reply.

**Cost.** No caps at first. Every run's cost and tokens go to the transcript
and the ledger; limits are decided from usage, not guessed.

## The page

- A Quickshell panel in `omarchy-shell`, full screen, summoned by a Hypr key.
  Fully bound to the Omarchy theme, the way `student.pomo` and
  `student.deadline` already are. No Chromium.
- Today's note only. No hierarchy, no file tree. A blank page.
- Save after every keystroke, coalesced over ~300 ms, flushed on Enter and on
  close. Escape closes.
- The template's link line never enters the editor: the page holds it apart,
  shows a faded "agent" mark in the header, and writes the line back
  unchanged on every save. That mark becomes the reply-waiting marker.
- Blocks painted from the state file: **faded** means seen, a **filled
  mark** means a reply (accent until read), a **hollow mark** means staged.
  That is all that is on screen while writing. The margin — reply,
  proposals, chat — exists only while asked for: `Alt+Right` opens it for
  the block under the cursor, `Alt+Left` or `Esc` closes it. `Ctrl+T` opens
  the tasks panel in the same place.
  `Alt+Up/Down` move between blocks, `Ctrl+Up/Down` go to the start and
  end of the current block, `Alt+Right` goes into the chat about the
  current block ready to type, `Alt+Left` or `Esc` comes back, `Ctrl+Enter`
  sends a staged block.
- A block is a paragraph (consecutive lines, blank line ends it), a
  top-level list item with its indented children, a heading, or a callout.
  Two lines with no blank between them are one block.
- A bar glyph toggles the page with the mouse — the quick-add gesture — and
  carries the reply-waiting state (the plugin declares both `overlay` and
  `bar-widget`). Ships with the overlay phase.

**Three shapes of one page.** Same sheet, same save logic, same block state;
only the window and the panels around it differ.
- **Overlay** — what exists now. `SUPER+ALT+=` (the plus key). Esc leaves.
- **Alongside** — the sheet as a normal Hyprland window, tiled beside slides
  or a PDF, moved with the keys the student already has. Not a reserved-space
  dock. `SUPER+ALT+\` opens it directly; `Ctrl+P` inside the overlay pins it
  into this shape. A pin icon in the header, as quiet as the agent light,
  shows which shape you are in. Esc here drops focus, never closes. Ships
  after the overlay phase.
- **Homebase** — full screen: the sheet in the middle, panels around it (the
  dialogue, open checkboxes, suggestions, deadlines, the timer). Grows one
  panel per phase; its layout and key are decided once the panels exist.
- Open-checkboxes panel (`Ctrl+T`): every unticked box across daily notes,
  last seven days open, older collapsed. Enter goes to the task (today: the
  cursor lands on its line; another day: its surrounding block unfolds in
  the panel). Space ticks, Ctrl+Z takes the last tick back; both edit the
  original line (the page is the one writer). Merges with the deadlines popup in the
  homebase: a task with a date and a task without one are the same thing to
  a student.
- Proposals live in the margin under the reply. `Alt+Right` focuses them,
  Enter accepts: local code runs the CLI and records the result; the model
  never touches the store.
- Suggestions panel: the day's suggestions with evidence, dismissable. Same
  "what's next" view as the checkboxes.
- Class notes taken during the day go in their own files, linked from the
  note. The agent reads a linked note only when an `@` line points at it.
- Sessions: pick a deadline when starting, or don't. The agent may propose one
  from the last checkbox line.
- Checkboxes replace the post-session keystroke from `student-os.md` D3: a
  checkbox line is the intention, the tick is the outcome.

## Modes (later)

- **Companion** — the page as above.
- **Focus** — full screen, timer as the frame, the agent quietly facilitates.
- **Study** — the drill pattern from the exam system (an outside assessor
  scores, the student never rates themself), as a mode of the same page.

## Acceptance tests

- Typing a line that ends in `?` and pressing Enter produces a reply marker on
  that block in under a minute. Typing a plain line produces nothing.
- A block inside `> [!private]` is provably absent from the payload log. A
  day with `agent: false` produces no payload at all.
- No file under the daily folder is ever opened for writing by the runner
  (asserted by test, not convention).
- The opencode agent has no tools: a payload that asks it to read or write a
  file yields text only.
- Each run's cost appears in the transcript and the ledger.
- Nothing is resident between runs.
- Suspend mid-run: the run completes or is retried on resume; no trigger lost.

## Phases

1. **The page** — Quickshell panel, today's note, plain text, per-keystroke
   save, Hypr key, theme-bound. Block splitting as shared code. No agent.
2. **The loop** — runner with allowlist and payload log, tool-less opencode
   agent, transcript and state file, triggered by the page. The allowlist and
   no-write tests ship in the same phase. `subject` and `link` on deadlines,
   `--for` on sessions.
3. **The overlay** — faded and reply-waiting states, block navigation, dive-in
   as a plain chat continuing the block's session.
4. **Proposals** — tick to execute, deadlines with subject and link, conflict
   flagging, the open-checkboxes panel.
5. **Knowledge** — the three file kinds accumulate, intention→outcome from
   checkboxes, suggestions with evidence and remembered dismissals, curriculum
   folder.
6. **Rendering** — headings, checkboxes, private callouts drawn properly in
   the page; space between blocks visibly larger than between lines, so the
   block rule is legible without knowing it.
7. **Focus mode.**
8. **Study mode.**
9. **Phone capture**, then **external reading** (portal deep links, reading
   time estimates, suggested slots, interpretation questions). Last, gated,
   read-only.

## Decisions log

- 2026-09-16: pivot from todo app to daily note; consent per block; cloud
  model via opencode; laptop only.
- 2026-09-17: full review. Own editor in the shell, not Obsidian (blank page,
  no hierarchy). Page comes first, loop second. Agent never writes the note;
  one template link is the only touch. Editor is the trigger, no watcher.
  Signals: checkbox, `@`, `?`, tick, page open — never a schedule. No tools
  for the model; structured reply applied locally. DeepSeek 4.1 flash via
  OpenCode Go. Allowlist replaces "human/ default private": `human/` is
  simply not on the list. Store wins over note. Project = subject, milestones
  = deadlines. Sessions optionally attach; absence is never evidence. Unticked
  boxes go to a panel, never to a question. Suggestions with evidence, shown
  in page only, dismissals remembered. No cost caps until usage is known.
  Syncthing and the Mac are out of the design. Phone and study mode later.
- 2026-09-17, after the first build: template link collapsed to a header
  mark; bar glyph joins phase 3. Three shapes of one page — overlay
  (`SUPER+ALT+=`), alongside (`SUPER+ALT+\`, `Ctrl+P` to pin, a normal
  Hyprland window because a side dock is legal layer-shell but not the
  Hyprland idiom), homebase (full screen with panels, designed once the
  panels exist).
- 2026-10-09: a sidebar after all, on the page's own terms. "No file
  hierarchy" now means none *on screen unless asked*: Ctrl+B shows the daily
  notes (newest first, by month; markdown only, no other folders), the page
  still opens blank on today, and fresh opens close it. Any day opens in the
  same sheet, editable; the agent works on it through `--date`, except on
  notes named in an older date format, which the runner cannot read.
- 2026-10-10: the sidebar is a month calendar instead of a list, faded
  numbers for days without a note. Opening such a day writes nothing until
  something is typed in it.
- 2026-10-10: deadlines and notes become one thing; focus mode shelved.
  "Subject" becomes "project" (the tool should outlast university). One
  store, many ways in: a checkbox line with a date at its end, Ctrl+D, an
  accepted agent proposal. A bound line ends in `📅 date ^dN` (Obsidian
  Tasks date, Obsidian block id) — the one place the page rewrites typed
  words, and only after a yes. The store wins over the line; deleting a
  bound line asks before deleting the deadline (default no). A #tag sets
  the project. Calendar marks deadlines apart from note fading; what's next
  leads with them; the popup stays as the glance and opens lines. Done
  deadlines leave lists the day after; ungraded ones wait to be graded.
  Organising notes around projects is parked for its own conversation.
- 2026-10-11: assessment and a freeze. Principle 2 amended to the student's
  own line: the content of the canvas is only ever the student's; the page
  may bring a deadline line's facts in line with the store, and the agent
  speaks in its own interface. Prompts no longer take `y`/`n` (Spanish "y"
  is a word); deleting a bound line hides the deadline instead of removing
  it. Features are frozen for two weeks of real use, measured by
  `student-agent stats` (local only). Decided for after the freeze:
  projects first — class notes must be findable by course without knowing
  the date; multi-language cue words and prompts, provided they cost no
  speed; the pomodoro stays a separate module and resurfaces with focus
  mode; abstracting for other students waits until this is a daily tool.
