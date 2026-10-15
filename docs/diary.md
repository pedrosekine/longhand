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

**Private.** Two scopes, described in full under "Privacy" below.

## Privacy

Two mechanisms, two scopes. Neither is a setting: both are marks in the note
itself, so the note carries its own answer and nothing has to be looked up.

| | scope | the mark | who writes it | who enforces it |
|---|---|---|---|---|
| **A private day** | the whole note | `agent: false` in the note's frontmatter | the page (`Service.setPrivate`, header word **private** / `Ctrl+Shift+P`) | the page refuses to run at all (`agentOn`); the runner refuses the note (`note_is_private` → `Fail`) |
| **A private block** | one block | a `> [!private]` callout | the student, by typing it | `blocks.py` marks the block `private`; `visible_blocks()` drops it before the payload exists |

Both are enforced by local code *before* inference, and every payload is
written to `~/.local/state/omarchy-student/payloads/` first, so "it was not
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
  Fully bound to the Omarchy theme, the way `student.pomo` and
  `student.deadline` already are. No Chromium.
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
  automatic open pass too; `student-agent` refuses such a note as well, so
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
