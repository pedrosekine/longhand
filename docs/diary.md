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
   never in the canvas. The line is the task: it says whether a deadline
   exists, its words and its project; the store is a ledger of what a line
   cannot hold (when it was done or cancelled, its grade), and a date or a
   tick changed on either side wins over the side that did not change. The
   page and `longhand-check` may change the *facts* on a line that stands
   for a deadline (its tick, its date, its anchor), never its words.
   (Amended 2026-10-11; 2026-10-17, see `tasks.md`: the store no longer
   wins.)
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
| Day transcript | `agents/longhand/daily/YYYY.MM.DD.md` | the runner |
| Day state | `agents/longhand/daily/YYYY.MM.DD.json` | the runner, rendered by the page |
| Knowledge | `agents/longhand/knowledge/` | the runner; the student may edit |
| Curriculum | folder named in config | the student; read-only for the agent |
| Box clocks | `~/.local/state/longhand/silence.json` | the runner (`lifespan.py`); never the note |
| Deadlines, sessions | `~/.local/state/longhand/` (existing) | the CLI only |
| Payload log | `~/.local/state/longhand/payloads/` | the runner; never synced |
| Cost ledger | `~/.local/state/longhand/cost.tsv` | the runner |

**The note.** Created from a template by whoever gets there first (page or
Obsidian); both check for existence. The template is one line: a link to the
day's transcript, `[[agents/longhand/daily/YYYY.MM.DD|agent]]`, unresolved until
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

**Private.** Two scopes, described in full under "Privacy" below.

## Privacy

Two mechanisms, two scopes. Neither is a setting: both are marks in the note
itself, so the note carries its own answer and nothing has to be looked up.

| | scope | the mark | who writes it | who enforces it |
|---|---|---|---|---|
| **A private day** | the whole note | `agent: false` in the note's frontmatter | the page (`Service.setPrivate`, header word **private** / `Ctrl+Shift+P`) | the page refuses to run at all (`agentOn`); the runner refuses the note (`note_is_private` → `Fail`) |
| **A private block** | one block | a `> [!private]` callout | the student, by typing it | `blocks.py` marks the block `private`; `visible_blocks()` drops it before the payload exists |

Both are enforced by local code *before* inference, and every payload is
written to `~/.local/state/longhand/payloads/` first, so "it was not
sent" is checkable after the fact rather than promised. A private block is
also absent from the day's state file and is refused outright as a trigger.
Frontmatter is page-owned like the agent link line: it never enters the
editor and is written back untouched apart from the `agent:` line, so
Obsidian properties survive and an emptied block is removed rather than left
as two bare rules.

Tested, by name: `private callout absent from payload`, `model received no
private text`, `private block not in state`, `private block refused as
trigger`, `a private callout in an earlier note stays private` (the project
history of another day), `a day marked agent: false is left out whole`
(ditto), and live: `asking on a private note runs nothing`.

**What this does not cover.** Worth knowing before trusting it further, and
none of it is decided yet:

1. **The deadline store is not private.** A dated checkbox written in a
   private note still binds: the page's `leftLine` has no privacy gate, so
   the title, project and date land in `deadlines.tsv` — and every payload
   carries the store whole (`pomo report --json`). Verified 2026-10-15: in a
   note marked private, `- [ ] therapy appointment by friday 17:00` became
   deadline #1, whose title the model would see on any later pass. The words
   around it stayed private; the commitment did not.
2. **Private is forward-looking.** Marking a note private stops the next
   pass; it does not retract passes already made. What was sent is in the
   transcript, the state file and the payload log, and the agent's replies
   for that day stay where they are.
3. **A private block has no control.** It is typed by hand; there is no
   keystroke and nothing on screen that says "the agent cannot see this" —
   the page draws it as a callout in the theme's magenta, which reads as a
   callout and not as a guarantee. The 2026-10-15 question offered one and
   the student took the day-scope control first.
4. **A private day is still a day.** It is listed in the calendar, its
   sections still appear under their project, and its words are still
   searched — the privacy is from the *agent*, not from the student.
5. The usage log (`usage.tsv`) records event names and counts only, never a
   word of a note; it is local and sent nowhere.

## The loop

**Triggers, all from the page, never by accident.** No file watcher. Two
things must both be true for a block to reach the model: it carries a
**sign** for the agent, and the student **says so**.
- The signs: a checkbox line (`- [ ] …`), a line ending with `?`, a ticked
  box. (`@` was a sign until 2026-10-15; it calls a project now.) The student says so with `Ctrl+Enter` or
  the header's **ask**, both of which send the block the cursor is in.
  Nothing is offered while writing: the washed "send to agent?" prompt that
  used to appear on finishing an `@` or `?` line went on 2026-10-15, and
  staging with it. (Prompts that remain — deleting the deadline of a line
  that went — take arrows and Enter, never a letter: since 2026-10-11, a
  typed "y" is writing, and in Spanish it is a word.)
- **A checkbox list is one submission.** Enter on an item just gives the
  next bullet. Leaving the list (Enter on an empty bullet) asks about the
  whole run of adjacent items as a group with one prompt; the reply attaches
  to every item, so ticking one later does not lose it for the others.
  Typing `- []` becomes `- [ ] `.
- `Ctrl+Enter` sends the block or list under the cursor at any later moment,
  asked about or not. On a block without a sign it sends nothing and a washed
  line under the cursor says why. A ticked box is a sign of its own, so a
  tick can be sent this way too.
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
  Fully bound to the Omarchy theme, the way `longhand.pomo` and
  `longhand.deadline` already are. No Chromium.
- Today's note only. No hierarchy, no file tree. A blank page.
- Save after every keystroke, coalesced over ~300 ms, flushed on Enter and on
  close. Escape closes.
- The template's link line never enters the editor: the page holds it apart,
  shows a faded "agent" mark in the header, and writes the line back
  unchanged on every save. That mark becomes the reply-waiting marker.
- Blocks painted from the state file: a **filled mark** means a reply
  (accent until read, dim after). That is all that is on screen while
  writing — see the 2026-10-15 entry in the decisions log for why nothing
  marks a block as sendable, and 2026-10-12 for why nothing is faded. The margin — reply,
  proposals, chat — exists only while asked for: `Alt+Right` opens it for
  the block under the cursor, `Alt+Left` or `Esc` closes it. `Ctrl+T` opens
  the tasks panel in the same place.
  `Alt+Up/Down` move between blocks, `Ctrl+Up/Down` go to the start and
  end of the current block, `Alt+Right` goes into the chat about the
  current block ready to type, `Alt+Left` or `Esc` comes back, `Ctrl+Enter`
  sends the block under the cursor.
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
- **Dashboard** — full screen, every open box and deadline in one place,
  worked with keys (decided 2026-10-15; the pinned twin of the bar's
  deadline popup, and a shape of the page because the page is the one
  writer). See the decisions log and item 2 of the plan's order.
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
  `longhand-agent stats` (local only). Decided for after the freeze:
  projects first — class notes must be findable by course without knowing
  the date; multi-language cue words and prompts, provided they cost no
  speed; the pomodoro stays a separate module and resurfaces with focus
  mode; abstracting for other students waits until this is a daily tool.
- 2026-10-15: the freeze lifts ten days early, and the stats decide. A week
  of classes made the habit (4/5 days, 20 opens, 371 min, 1324 words) and
  the deadlines (29, 18 bound from a note line), but the agent was offered
  nine blocks in the whole week: the send prompt was answered yes once
  against no 41 times, 31 of those deliberate. Multi-language and focus mode
  are refuted by the counts they were waiting for (61 English blocks to 3
  Portuguese; 0 pomodoro sessions in a month); projects for notes is
  confirmed (the calendar opened 31 times, past days 11) and is built first.
  Three things no count showed, in the student's words: a checkbox has no
  depth, so it needs a parent or enough context to survive a few days (not
  solved — the shape comes first); the agent knows nothing when asked, so it
  feels useless and must get smarter *within* the allowlist, not with a
  shell or a `read` tool; and **staging is not a useful state** — once the
  student has decided not to send a block, a mark saying it still "could be
  sent" is noise, `Ctrl+Enter` already sends on demand, and the hollow mark
  read as the running indicator. So staging is gone: nothing is held between
  the prompt and the send, every block is sendable from where the cursor is,
  and the only mark on the student's words is a reply. A ticked box became a
  sign of its own so the tick trigger survives without it.
- 2026-10-15: the agent may see one project's past, and nothing more. The
  student's note was that an agent which knows nothing when asked feels
  useless; the mechanical cause was that the payload held today's note and
  no other day. So a block the student *deliberately* sends, written under a
  `# Course #tag` heading, now carries that project's own sections of the
  earlier daily notes — the most recent few in full, older ones named only,
  so the model can ask rather than be handed the term. The narrowing is the
  point and is tested: that project's sections only, never the rest of those
  days; private callouts and the link line dropped block by block by the
  same code that strips today's; a day marked `agent: false` skipped whole;
  and the automatic open pass not widened at all, because nobody asked it
  to look. Local code gathers it and the payload log still holds everything
  before inference, so principle 3 stands — no `read` tool, no shell.
- 2026-10-15: the agent gets a visible way in, and the prompt goes. Asked
  whether the send prompt should stay, the student put the real question
  instead: "how to trigger the agent in a visual way aside from keyboard
  shortcuts? This is a core feature that should not be only under a
  specific trigger." So the header — outside the canvas, where the date,
  the pin and the agent mark already live — gained **ask**: it sends the
  block the cursor is in, dim when that block carries a sign and faint when
  it does not, and a click with no sign says why instead of doing nothing.
  Principle 2 is why it is in the header and not in the gutter: a control
  beside the words would put a mark back on them, which is what staging
  taught us to avoid. With a visible way in, the prompt is pure
  interruption (31 deliberate no's in one week), so it is gone: writing a
  line, leaving a list and ticking a box no longer ask anything. One path
  now carries every send — `sendCurrent` — and it still waits for the
  deadline queue to settle, so a list reaches the agent with its dates
  already bound and no duplicate proposals (the 2026-10-13 fix).
- 2026-10-15: a project's notes belong on the left. They first opened in the
  margin, which was the nearest panel rather than a decision; the margin is
  the *agent's* side (reply, proposals, chat, what's next) and a project's
  sections are the student's own writing, so finding them is navigation and
  navigation lives in the sidebar with the calendar and the deadlines. The
  projects list drills into the project in place, `←` or Esc comes back, and
  the sidebar widens while a project is open only where the note can still
  have its full measure beside it. A second left-hand column was weighed and
  dropped: it would spend the width the measure needs. With that, the way in
  inverts — a click or Enter on a project *opens* it, and writing one into
  the note moves to Shift+Enter (start a class) and Ctrl+Enter (its tag),
  with `@` to come. The list is for finding; the note is for writing.
- 2026-10-15: journaling needs a guarantee you can see. Asked how to be
  certain a note is unseen, the honest answer was that `agent: false` worked
  in the runner but the page could neither set it nor show it, so the only
  way to be sure was to hand-edit frontmatter and trust. Now the header
  carries **private** beside the date: always in sight, one click or
  `Ctrl+Shift+P`, and while it is on the word reads "private · the agent
  sees nothing here" and **ask** and the agent mark are gone — not greyed,
  gone, because there is nothing to offer. Every run is gated on `agentOn`
  (the day is the agent's *and* the note is not private), which stops the
  automatic open pass too; `longhand-agent` refuses such a note as well, so
  the page simply never asks. The mark is one line of frontmatter because
  that is what the runner reads; any other property the student or Obsidian
  put there survives, and an emptied block is removed rather than left as
  two bare rules.
- 2026-10-15: `@` calls a project. The student asked for one way to say
  "this is about that course" wherever their hands are — "this guarantees
  the consistency" — and `@` was nearly free: it had been the agent's fourth
  sign and had been used once in a month, against `#tag` in every note. So
  typing `@` offers the projects, narrowing as you type; Enter leaves the
  project's own `#tag` where the `@` was, and Shift+Enter, on a line the `@`
  opened, writes the `# Course #tag` heading instead. What lands in the note
  is always the tag the store, the payload and the sidebar already read —
  `@` is a way of writing, not a new thing to parse. An address is never a
  call, because `@` only counts at a word's start. The agent keeps three
  signs (checkbox, `?`, tick) and the margin chat for anything free-form.
- 2026-10-15: the page is set in a face for prose. It had drawn in the
  shell's monospace since the beginning, which is right for a terminal and
  wrong for a page of class notes; the three candidates were rendered with a
  real note in them and compared rather than argued about, and iA Writer
  Quattro S won on the obvious grounds — headings stop wrapping, lines carry
  more words, prose stops looking like code. Fenced code and frontmatter
  keep a monospace, where columns mean something, and the chrome follows the
  note so the page reads as one surface. The face is a config key with a
  fallback chain, not a hard-coded name, because the tool is meant for other
  students' machines too. Two things came out of it: the measure is counted
  on a lowercase alphabet now (the unit typography has always used; 72
  characters is 2.8 alphabets), which is identical for a monospace and
  honest for a proportional face; and the first attempt silently broke the
  zoom, because `advanceWidth` is a method call and QML saw no dependency on
  the font — a binding that reads `font.pixelSize` first fixed it, and the
  live measure tests caught it.
- 2026-10-15: two answers to "it feels too bold". The first was that
  emphasis would not fix it — the weight of a regular paragraph is the
  face's and the contrast's, and adding bold only gives the eye something
  heavier to compare against. The real cause was measured: the stock theme
  puts #F0EEE9 on #322D2A, 11.7:1, and light text on a dark ground blooms.
  Text now sits a fifth of the way back toward the background, near 8:1 —
  above the 4.5:1 the page holds itself to, and never allowed below 7:1, so
  a theme that is already gentle keeps full strength. Native rasterising was
  tried first and changed nothing, so it was dropped rather than left in.
  The second answer was that the gap was real: there was no way to write
  bold or italic at all. `Ctrl+B` / `Ctrl+I` / `` Ctrl+` `` / `Ctrl+Shift+S`
  wrap the selection or the word under the cursor and take the markers off
  again; a one-character marker is never read as half of a two-character
  one, so asking for italic on a bold word adds a pair instead of eating
  one. The markers go into the file as written: drawing them styled is
  parked, because every row is a plain-text field whose offsets the rest of
  the editor rests on. `Ctrl+B` was the sidebar; the sidebar moved to
  `Ctrl+Shift+B`, because on a writing surface Ctrl+B is bold.
- 2026-10-15, later: the boldness had one cause and it was neither of the two
  above. The `ttf-ia-writer` faces declare the same weight for *every* style,
  so a request for a normal weight resolves to the **Bold** file: the whole
  page was set in bold without anyone choosing it, and `**bold**` had nowhere
  heavier to go — which is why the emphasis keys written that morning looked
  like they did nothing. Asking for the cut by name (`font.styleName:
  "Regular"`) picks the real one; a family that has no style of that name is
  unaffected, tested against DejaVu, JetBrains Mono and a family that does
  not exist. With that in place the contrast softening of the morning was
  undone: it had been treating a symptom, and against a genuine Regular it
  only cost legibility. Text is back at the contrast the theme chose. The
  lesson worth keeping is the shape of the mistake: a plausible explanation
  (contrast, bloom) was measured and acted on without ever checking the
  simpler one — which font file was actually being drawn.
- 2026-10-15, later: emphasis is drawn. The parking-lot entry said this
  needed a mapping between drawn offsets and the body's, and that the mapping
  was the riskiest change in the editor. It needed no mapping at all. A row
  with emphasis becomes rich text whose *plain* text is the body character
  for character, the markers rendered in a span one pixel tall and
  transparent; Qt keeps one document position per character either way, so
  the cursor, selection, search painting and bound-line rewriting never learn
  anything changed, and a row without emphasis stays plain text on the old
  path. The open question — whether markers show while the cursor is in the
  span, as Obsidian does — answered itself: they are hidden only while they
  are doing a job, so breaking a pair brings them back at full size, which is
  how you see them to edit them. No focus-dependent reflow, no jiggle.
  `white-space:pre-wrap` is load-bearing: without it the renderer eats runs
  of spaces and the trailing space of a line being written, and every offset
  after them is off by one. The test that matters asserts the drawn text
  strips back to the body exactly, for a dozen bodies.
- 2026-10-15, later: the agent had not been working at all. opencode 2.0.29
  dropped `--pure`, `--dir` and `--variant`; it printed its usage to stdout
  and exited **0**, so every pass of the day failed and the page looked
  exactly as it does when the agent has nothing to say. Three things follow,
  and the third is the one worth keeping. The invocation moved on
  (`--standalone` for a server that dies with the pass, the working directory
  passed as the process's own, the variant riding on the model as
  `provider/model#variant`), and cost is read back from the session because
  the event stream no longer carries it. A run that produces no text, no
  session and no error is now recorded as a failure. And the page says so: a
  failed pass puts a line under the cursor. Silence from the agent is only
  ever an answer now, never a fault — a tool that fails invisibly teaches the
  student it is useless, which is exactly what the week's 31 declines were
  starting to say. The invocation itself is a tested contract now, not an
  implementation detail: the stub records how it was called, and the tests
  assert the flags, the empty working directory, and the absence of every
  flag opencode no longer knows.
- 2026-10-15, later: a pass in flight is visible. The block's gutter mark
  carries a light travelling down it, from the moment the student asks until
  the answer is back; the header's "agent" brightens for the same span. It is
  marked at the ask rather than at the launch, because a send waits for dates
  to bind and the note to be written, and "did that go?" is exactly the
  question in that gap. A mark that moves means still thinking, a mark that
  rests means answered — the state the student asked about is now a motion,
  not another colour to tell apart.
- 2026-10-15, correcting the entry above: "the markers come back when you
  break a pair, which is how you see them to edit them" did not survive an
  hour of use. It makes a character that is drawn to nothing deletable, so
  Backspace at the edge of an emphasised word spends one keystroke changing
  nothing visible except making the markdown pop into view — and on
  `***both***` the first Backspace demotes bold italic to bold with no
  feedback at all. The student's reading is better than mine: once the
  markers are in, they should never be seen again, and emphasis comes off by
  deleting the text or by pressing the key again on it. That makes the pair
  one thing to the cursor, which is arithmetic on top of the drawn row
  rather than a change to how it is drawn — `Emph.js` and the
  one-position-per-character guarantee are untouched by it. Written up as a
  bug with the measured behaviour per marker; not built yet.
- 2026-10-15: the in-flight mark now sits on the line the student asked
  from, not on every block of the submission. A run of list items is one
  submission and the marks honestly showed all of it leaving — but the
  question a moving mark answers is "did that register?", and that is one
  place; a whole list lighting up reads as the page leaving rather than the
  line. The reply still lands on the group, where it is information rather
  than noise. The optimistic mark is also pruned against the note now, so a
  line whose date bound between the ask and the send does not leave a mark
  behind on a hash that no longer exists.
- 2026-10-15, last of the day: the markers are now one thing to the cursor,
  which is what the student asked for and is better than what I argued for
  this evening. The rest position is the run's *inner* edge, against the
  words — so Left and Right cross a whole pair in one press, a click inside
  one lands beside it, and a selection's ends are already columns the cursor
  may hold, which is why Shift+Right out of a drawn word selects the word
  and the key unwraps exactly it. Backspace and Delete (and their Ctrl
  forms) step over a run and take the letter or word beyond it. Two rules
  keep a `**` nobody typed off the screen: emptying an emphasis takes the
  pair with it, cascading through `***word***`; and a deletion that would
  leave a space against a marker takes the space, because markdown does not
  read `**two **` as emphasis at all and the pair would come back for a
  space nobody can see. The line's own two ends stay valid columns whatever
  sits there, so a line that begins or ends in emphasis can still be written
  before and after and Backspace at a line's start still drops the kind.
  All of it is arithmetic over the drawn row — `Emph.hidden`, `validCol`,
  `collapse` — so the one-document-position-per-character guarantee that the
  whole editor rests on never moved. Two places still show markers, both on
  purpose: the key pressed with nothing to wrap writes `****` and stands
  inside it, the only way to say "the next letters are bold", and the first
  letter takes it away; and a selection dragged through one side of a pair
  and deleted leaves the other, which is an explicit act with an honest
  result.
- 2026-10-15: a block the agent has answered is not asked again. The
  question was the student's — "does it make sense to Ctrl+Enter it again?"
  — and the code answers it: a block's identity is the hash of its text, so
  a block that still carries its answer is text that has not changed, and
  `apply()` overwrites the record, so the second pass would send the
  identical payload and destroy the first answer with the second. Not two
  opinions to compare; one opinion, paid for twice, minus one. So the header
  word becomes "reply" and the key opens the conversation on that block with
  the cursor in the box, continuing the session the first pass opened — only
  the new message travels. No forced-rerun key: change the words and it is a
  new block that runs as usual, and if the answer was poor what you want is
  the follow-up.
- 2026-10-15: the chat shows what you sent, at once, and says it is
  thinking. The turns were read from the day's state file, which the runner
  writes only when the pass finishes — so the box emptied and nothing
  appeared for ten seconds, which reads as a message that did not send. The
  page now holds the turn it just sent, draws it immediately, and lets go of
  it when the runner's own copy lands. "thinking" breathes under it and
  starts counting seconds after four of them: a slow pass and a hung one
  look different now, which is the whole point of an indicator.
  Underneath that was a real bug, and a lesson worth keeping: **a binding is
  not refreshed until after the handlers of the property it depends on have
  run.** `AgentState.record()` read the `blocks` binding, and everything
  reached from `onStateChanged` — the chat settling, `checkAccept`, the
  unread count — was therefore looking at the state before the one that had
  just arrived. It surfaced as the sent message drawn twice, and only
  sometimes, because any other read of `blocks` in between would refresh it;
  the live check passed while the behaviour was broken, and only looking at
  the thing caught it. `record()` and `recount()` read `state` directly now.
  Next to the `advanceWidth` lesson: that was a dependency never captured,
  this is a captured dependency not yet up to date.
- 2026-10-15: tasks get lifespans, and the dashboard gets the screen. The
  weakest number in the tool is checkboxes closed — 2 of 22 in the week of
  classes, 0 of 17 before it — and the student's own reading was that a
  checkbox has no depth: it becomes a task with a deadline the moment it
  exists, so it has to be either a subtask of something that gives it
  meaning or self-contained enough to still mean something in a few days.
  Three things came out of the evening. **First, three kinds of box, not
  one.** A *note box* is part of thinking, lives inside class notes, and is
  not supposed to be closed at all; a *task* is self-contained and carried
  forward; a *deadline* is imposed from outside and has consequences.
  Todoist conflates the last two and cannot express the first, while
  markdown gives it away for free — and counting note boxes as unclosed is
  what makes 2/22 partly a measurement artefact. The rule that tells them
  apart adds no syntax: **a box becomes a task when it is given a date or a
  priority, and stays a note box otherwise**, which is already how deadlines
  are born. The safety net is age, never interrogation: nothing interrupts
  writing to ask a checkbox to justify itself. **Second, lifespans**, taken
  from the `entropy` model in Basecamp's Fizzy, whose source says it
  plainly: a card carries `last_active_at`, any activity resets the clock,
  and after the silence runs out an hourly sweep moves it to "not now" —
  attributed to a system user, recoverable, not deleted — with a bubble
  counting down through the last quarter of its life (30 days by default,
  and changing the setting touches every card so nobody is evicted by a
  knob). Here: 7 days of silence for a note box, 30 for a task, and no
  decay at all for a deadline, which is judged by its date — though a
  deadline a fortnight past its date with nothing done to it is auto-hidden,
  the state the store already has. One adjustment makes the idea better here
  than there: **the decay belongs to the view, not the file.** Fizzy can
  move a card because cards live in a database; a note box lives in a note
  from a day that already happened, which is history and is not rewritten.
  So a box that goes quiet simply stops being carried into the dashboard,
  stays where it was written, and stays findable through its project — which
  makes archival reversible for nothing. The rule kept verbatim is the
  warning: nothing may vanish that has not first appeared as about to.
  **Third, two dates — due and do.** The due date is a fact you receive; the
  do-date is the decision students avoid, so it is the first job worth
  giving the agent: workload across the fortnight by project, do-dates
  proposed for the empty days, and an effort estimate offered rather than
  asked for, because nobody fills those in. It needs no new access — the
  store and the task list are already in the payload — and it is the
  argument for fetching the timetable, without which "the 24th is free" is
  a guess. The dashboard itself is full screen, the pinned twin of
  `SUPER+ALT+D` as `SUPER+ALT+\` is of `SUPER+ALT+=`, and marking something
  done there ticks the line in the daily note, which forces it to be a shape
  of the page: the page is the one writer, and `longhand-agent tasks` is
  read-only for that reason. Vocabulary stays Obsidian Tasks' (📅 ⏳ 🛫 🔁,
  the priority arrows, ✅, `- [/]` and `- [-]`) so the file still reads on
  the Mac and in any editor — richness on disk, quiet on screen, since the
  page draws its own rows and can show a date as a pill and a priority as a
  colour. And the division of labour between the two ways in: in the note,
  language; in the dashboard, keys — with rescheduling the single place that
  takes typed words, through the note's own parser.
- 2026-10-15: the dashboard, and one meaning for Enter. The grammar having
  landed, the list got a place to live. It is full width and takes the
  sheet's place rather than sitting in the margin, because a list is not
  prose and does not want the 72-character measure — and because two
  surfaces for one list is part of what made the list easy to ignore, the
  narrow what's-next panel is gone rather than kept beside it. `Ctrl+T` is
  the way in; the bar's deadline popup (`SUPER+ALT+D`) stays the glance,
  which makes them the same pair as the overlay and the window. That
  pairing forced the architecture, pleasantly: marking something done in
  the dashboard ticks the line in the day it was written, so the dashboard
  had to be a shape of the page — the page is the only writer of notes, and
  `longhand-agent tasks` is read-only for exactly that reason. Rows group by
  what they ask of you (DUE, DOING, TO SCHEDULE) and then by project, never
  by the day the thought was written, which is not how it is looked for.
  Each row carries its heading path, so "draft the intro" reads as "Design
  Theory › Essay 2 · written yesterday" — the answer to "random text I will
  not understand later" being display, not a demand that the student write
  better boxes. The verbs settle the collision the week had been living
  with: **Enter opens the line, everywhere**, and the heavy action is
  elsewhere — `Ctrl+Enter` in the page, `d` in the popup, which gives no
  modifiers to work with. Enter used to mean *done* in the popup and *go to
  it* in the panel, one key doing two opposite things depending on which
  surface you had opened. `x` was worse: it ticked in one and deleted in the
  other, so it is retired and Delete does the destroying. Dropping is now a
  state and not a deletion (`- [-] … ❌ <day>`), because a box that is never
  going to happen deserves an answer that is not a lie, and `Ctrl+Z` takes
  it back. The one place the dashboard takes words instead of keys is `t`,
  the do-date, parsed by the note's own `Dates.js` so "friday" means there
  what it means here — in the note, language; in the dashboard, keys.
  Every line edit is surgical: `Task.js` rebuilds only the metadata tail and
  keeps the words byte for byte, so a marker it does not understand keeps
  its place rather than being quietly dropped by a re-render.
- 2026-10-15, the evening's second thing: the heading hierarchy was upside
  down, and the fix was to stop spending hue on rank. Until now each level
  took its own colour — the first four distinct of accent/blue/magenta/
  cyan/green — which drew four marks rather than four ranks: hue has no
  order, so nothing tells the eye that blue outranks magenta. Worse, the
  list began at the accent, and an accent is a UI tint chosen to sit under
  buttons and borders, mid-contrast by design. Measured across Omarchy's
  21 stock themes it made H1 the *quietest* heading on the page in most of
  them (rose-pine 3.1:1, barely above the floor), and under this one — a
  deliberately monochrome accent, #C9C3BC, chroma 0.05 — a title was a big
  grey line **dimmer than the paragraph under it**. That is what "H1 feels
  hidden" was: not a size problem, a colour problem, and a measurable one.
  Now the levels are one colour walking home to the text: H1 is the theme's
  one chromatic voice (its accent when the accent is a colour, else the
  first of blue/cyan/green/magenta/yellow/orange that is, lifted to 4.5:1
  if the theme set it fainter), H2 and H3 are that colour 40% and 72% of
  the way back to the prose, and H4–H6 are simply the prose. Rank is
  carried by the channels that have an order — size (1.6/1.3/1.15/1), the
  one Bold on the title, the clearing above it (2.0 ems, was 1.75) and the
  distance the colour has left to travel. Lifting moves a colour toward
  white or black rather than toward the foreground, because a foreground is
  often tinted (ethereal's peach) and mixing into it turns a blue to mauve
  on the way. A palette with no chroma to lend at all — vantablack, white,
  solitude — ramps the only ladder it has, the text down toward its grey.
  Checked on every stock theme before writing it: the four steps move one
  way only in all of them.
- 2026-10-15: the dashboard gets drawn, not just built. The first version
  was right and unappealing — "just a vertical list with data" — which is
  what happens when a view is assembled out of strings instead of out of
  the idiom the rest of the page already has. So it borrows that idiom
  rather than inventing one: a date is a **pill**, outlined for the day
  something is owed and filled for the day you mean to work on it, urgent
  when it is late, exactly as the note draws a bound line's date; a box is
  the note's own checkbox and takes a click; a priority is a mark beside
  the box rather than a word among the words — the same rule as the line
  itself, where the metadata is on disk and quiet on screen. Bands carry
  the course's **own name** with its tag beside it, taken from the
  curriculum when the sidebar knows it and otherwise from the heading the
  notes themselves use, and they are coloured from the theme's headings —
  one colour for the three bands that say what a row asks of you, another
  for the courses, which is the h1/h2 distinction the note already makes.
  The dated sections are banded by month, because a list that runs on needs
  somewhere for the eye to rest. Under each row, faint: the section it was
  written in and how long ago — with the course dropped when the band above
  already says it, since a subtitle that repeats its own heading is noise.
  Rows take their space from what they are, as `Rows.js` gives the note its
  vertical rhythm, and the column is 1.45 measures and centred: a row is a
  title, a place and a date rather than prose, so it wants more than 72
  characters, but it does not want the whole wall. Found by looking: a
  screenshot of the thing is worth more than a passing test here — the
  tests were green while the bands still read `#intsem` and every row
  repeated its own course.
- 2026-10-16, amending yesterday's heading ramp: right about hue, wrong
  about spacing. One colour in four even steps put three of them in the
  pale end — ΔE 14, 12, 11 apart under this theme — and the student said
  the levels were "too close to the point that I don't trust that there's
  a difference". That is the right complaint: contrast was never the
  measure, perceptual distance is, and four tints of one blue can each be
  legibly different from the background and still read as one colour. So
  the ladder now spends the whole range it has and changes a *kind* of
  thing at every rung: H1 the theme's chroma, H2 that colour halfway home,
  H3 the prose with no colour at all, H4 the quiet grey below it. The
  title is also deepened — out along the line that joins it to the prose,
  up to 1.3× and never below 4.5:1 — when the theme's own accent sits too
  near its text (lumon, catppuccin, tokyo-night). The cap is the point:
  past 1.3× the page would be inventing a saturation the theme chose not
  to have, and everforest's sage would come out as a vivid teal. Picking
  instead "whichever palette colour is least like the text" was tried and
  dropped: it gave tokyo-night a green title and nord a yellow one, which
  is a page that no longer looks like its theme. Sizes widened with it
  (1.7 / 1.4 / 1.15 / 1), and the live test now asserts ΔE ≥ 15 between
  neighbours rather than a direction of travel — this theme comes out at
  22, 24, 33.
- 2026-10-16: every key in one place. The page answered to 91 keys for 76
  actions, written into ten handlers and described only in prose; they are
  now one list (`plugin-page/Shortcuts.js`) that every handler asks and the
  keys sheet (`Ctrl+/`, **keys** in the header) draws, so the list cannot
  drift from what the keys do. Every key the page defines can be moved,
  including the dashboard's letters and the lists' arrows; what stays fixed
  is the text field's own (arrows, selecting, the clipboard, Enter, Tab) and
  the sheet's own keys, because a sheet whose way out can be moved can lock
  the student in. Moving a key onto one taken in the same place asks first,
  and a bare letter is refused wherever there is writing. Hyprland's keys
  are shown but not edited from the page: they live in the student's own
  bindings, and writing to those is a different trust. Matching became exact
  (Ctrl+T no longer also answers Ctrl+Shift+T), which no test relied on.
- 2026-10-16 (later): the keys measured against Obsidian, Notion, VS Code,
  Google Docs and Todoist. Kept: everything that already matched, and the
  page's own grammar where it is consistent — Alt+arrows move between
  places, Ctrl+arrows take the bigger step, Enter goes and Ctrl+Enter acts,
  Esc backs out one level. Added, never in place of a key: the other apps'
  keys for the same act (Ctrl+E, Ctrl+\, j/k, Space, e, t), the note's own
  keys inside the dashboard (Ctrl+L ticks, Ctrl+D asks when), and days by
  key — `Alt+Home` today, `Ctrl+PgUp/PgDn` the neighbouring day with a note.
  Today is not on Ctrl+T: that is the dashboard's, T for tasks, and Home
  already meant today in the calendar. Fixed: on a layout with dead keys
  `` Ctrl+` `` most likely reached nothing (xkb gives dead_grave, which Qt
  reports as Key_Dead_Grave and the page did not read), so inline code had
  no working key on the student's own keyboard; not yet confirmed by a real
  press. Parked for a decision:
  Ctrl+P (overlay ⇄ window) against every other app's switcher, Ctrl+Shift+P
  (private) against VS Code's palette, Alt+Up/Down against VS Code's move
  line.
- 2026-10-16 (evening): the three parked keys decided, and today moved. The
  student's laptop has Home and PgUp on Fn+arrows, so a key that needs them
  is two hands: today is `Ctrl+H` (H for home, free since the page has no
  replace) and the days `Ctrl+[` / `Ctrl+]` (Notion's back and forward),
  with `Alt+Home` and `Ctrl+PgUp/PgDn` kept second. The overlay ⇄ window
  flip leaves `Ctrl+P` for `F11`, every app's full-screen key, with
  `Ctrl+Alt+P` for an F-row behind Fn; `Ctrl+P` is free for a switcher.
  `Ctrl+Up/Down` walk on through blocks when pressed again (Word's
  paragraphs, and what their Shift twins already did), which frees
  `Alt+Up/Down` to move a line, as VS Code does; a bound line moved keeps
  its anchor and asks nothing. Esc in find now leaves the cursor on the
  match, as browsers and editors do; going back is `Shift+Esc`. The written
  guide, docs/keys.md, is generated from Shortcuts.js and hyprkeys.py and a
  test fails when it falls behind.
- 2026-10-17: one copy of a task, not two. Found while asking why some
  tasks had no project and could be neither opened nor deleted: the line and
  the store were two copies with a sync between them, and every way a task
  went missing was a gap in that sync (the "remove it too?" prompt defaulting
  to no, a block deleted with several deadlines asking about only the last,
  cuts and Obsidian edits never noticed, two rules for a project, Enter
  previewing instead of going, Delete doing nothing on a deadline). Compared
  against Org's agenda and Obsidian Tasks (files are the truth, lists are
  views), Logseq's file version and Obsidian block links (files plus ids on
  the blocks something refers to), and Tana, Roam and Notion (a database the
  page is a view of): Longhand takes the middle, so Obsidian stays a full
  second editor and principle 1 holds. The contract: the person's words
  live only in markdown; the layer holds ids, history, conversations and
  views, and repairs itself after outside edits; no id is ever shown inside
  Longhand. A deadline is cancelled exactly while no note holds its tag, and
  the person is told by a notice that waits for nothing, which retires the
  2026-10-10 prompt. Born without a line means the agent's, kept in a "not
  in a note yet" band until the person writes it in, with its origin kept.
  The dashboard: Enter goes to the line on any day, Delete cancels a line,
  Ctrl+E renames (Todoist's key; the second place the dashboard takes
  words). Project is one rule everywhere — the line's tag, else the heading's.
  Empty boxes are not tasks. The whole model, and what was learned, is in
  `tasks.md`.
- 2026-10-17 (later): lifespans, built. A box's clock is the layer's
  (`agent/lifespan.py`, `silence.json` beside the store), keyed by its
  project and words, and the note is never rewritten: a box silent for its
  life (7 days a note box, 30 a task; a do-date ahead starts the clock on
  that day) leaves the list and waits folded under **not now**, which is
  also where `s` puts one by hand — a shelf, not a snooze, because `t`
  already says "on this day". Touched means its words written or changed,
  the same words in a later note, a priority set, or `r` (keep); `s` on a
  box that is away is a keep too. Nothing goes unwarned: a row says "goes
  quiet in N days" through the last quarter of its life, and on the clock's
  first day every box already past its life starts in that quarter instead
  of going at once (Fizzy's rule when its setting changes) — which on the
  student's notes put all 35 open boxes on a 2-day countdown together. A
  deadline still open a fortnight past its date steps aside (hidden, by
  `longhand-check`, counted down over its last four days) and comes back if
  its date moves on or its line is ticked; `stats` counts it as missed, not
  as done late, and stops counting cancelled ones as closed. `g` grades a
  deadline from the dashboard, and done ones with no grade wait folded, as
  in the popup.
