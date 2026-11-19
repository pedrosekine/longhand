# The agent that does things — while the person drives

**Status:** designed 2026-10-17 in a grilling with the student, after a
reflection on whether the agent as built could become proactive. Nothing of
it is built yet; the slices at the end are the order. This is the reference
for the agent's environment, its actions and their autonomy, how it asks,
what it learns, the documents it reads, and how it reaches a model. It sits
beside `docs/tasks.md` (one copy of a task) and `docs/diary.md` (the
principles), and does not change principle 1 (plain files, nothing
resident) or principle 3 (consent is an allowlist, logged before inference).

## Why

The agent as built reacts to writing — a block sent, a list written, a box
ticked, the page opening — and can propose one thing, a deadline. In its
first month it was refused (41 declines to 1 of the old send prompt) and
proposed nothing on any day. The student's reading: it knows nothing and
does nothing, so there is nothing to gain from it.

What is right about it stays: it sees only what local code assembled and
logged; it has no tools (a read-only one from 2026-11-18's design: "One
conversation", below); what it proposes is done by local code, and only
when the person accepts. That is "the agent does the legwork, the person
makes the act", and it is the foundation a proactive agent needs, not a
limit to remove. What changes is the shape on top: jobs rather than only
reactions, more than one action, proposals where the decision is made, and a
record of what came of them.

## The environment: structured work, not authored words

Checkboxes are where the agent may work, because they are structured work
rather than something the person is authoring (the student's words). Its
reach:

- **A box's facts:** its do-date (`⏳`), its priority, whether it is still
  wanted.
- **New boxes**, and **bullets only as children of a box** (steps under a
  task, notes under it) — never loose in the prose.
- **Never the words of a box the person wrote.** A rewording is proposed,
  and is the person's once accepted.
- **Never prose** — everything that is not a box or a box's child is the
  person's by definition.
- **Never anything private:** a note marked private, or a block inside
  `[!private]`, is invisible to the agent and therefore untouchable. (Whether
  a private note's deadlines stay out of the payload is still the plan's
  item 3.)

The model still never writes a file: whatever it does, the page or
`longhand-check` writes on its behalf, after checking what the person
allowed — so "the agent never touched the prose" stays provable
(`guard_write` is unchanged).

## Who made it: three marks

Authorship is kept **by line**, for boxes and bullets, in **the layer** —
never as a mark in the file — the way a sent block is known by its words and
place. Three states:

| | When | Drawn as (the box or dot itself) |
|---|---|---|
| **The person's** | they wrote it | the box and dot as today |
| **The agent's** | it wrote it, and its words are untouched | a hollow ◇, quiet |
| **Together** | the agent made it and the person changed its words; or the person's, reworded by the agent with the person's accept | the Longhand seal, small, in the theme's colour |

- **Facts do not change authorship.** A do-date or priority the agent set
  on the person's box leaves it theirs; the pill carries a faint agent tint.
- **Edits made in Obsidian** cannot be followed by the layer, so such a line
  falls back to the person's — erring towards theirs.
- The seal as "together" is an experiment the student chose
  (docs/brand/README.md records the narrowed rule); it may be refined with
  the brand's own tools.
- Precedent: iA Writer's Authorship marks human, AI and reference text and
  clears the AI mark word by word as the writer edits it, locally; this is
  the same idea a line at a time, with a third state.

## Where the agent's boxes go

The daily note is the home of notes.

- **Proposed** (the action is at "ask me"): it waits in the dashboard on a
  row of its own and is not in any note yet — as deadlines born without a
  line already do.
- **Accepted, or done at "do it and tell me":** a step goes under its parent
  box, in whatever day's note that box lives in; anything without a parent
  goes into today's note, under the course's heading if today has one, else
  at the top — above the first heading, after the loose boxes already there,
  in the order accepted. Never at the end: the end of a note is inside its
  last section, so the line is claimed by a course it does not belong to
  (2026-11-03, below). Accepting is what writes it, so the act is the
  person's; the words stay the agent's (◇) until the person rewords them
  (together).
- **Taken back:** Ctrl+Z in the note removes the line only; a deadline goes
  back to the dashboard with no line, as before Enter wrote it. Cancelling
  it is still Del on its row.

### Where it came from (grilled 2026-11-03)

The case: a #thesis deadline proposed in the chat on another task
(Themenvorschlag draft, #36) was accepted, and Enter wrote its line at the
end of the day's note — inside `# Speculative Environments #dtm › ## Watch
and read list`. The #dtm section counted it as one of its open boxes, the
#thesis view found nothing (a project's sections are found by tagged
headings), the dashboard said "Master Thesis › Watch and read list" (a
section that does not exist), and nothing said why the line was there. The
placement rule above fixes where; this is the rest.

- **Every line the agent writes says where it came from** — a deadline from
  a chat, a step from a plan, what was done at "do it and tell me" — each
  with its own source: "from the chat on Themenvorschlag draft · 19 Oct ·
  accepted today 20:35", "from the plan of 3 Nov", "done by the agent,
  3 Nov". One rule, so a ◇ always explains itself.
- **In the layer, never in the file.** Kept beside authorship: the ledger
  records the chat (its day and block) a proposal was accepted from, at the
  moment it is accepted. Obsidian sees the line and nothing else.
- **Shown when looked for.** In the note, a dim line under the box while the
  cursor is on it or the hand is over it; otherwise the box with its ◇ and
  nothing more. Accepting lands the cursor on the line, so it is seen once
  as the line arrives. On the dashboard, the row's second line says it:
  "Master Thesis · from the agent, in the chat on Themenvorschlag draft".
- **It outlives rewording.** A reworded line is together (the seal), and
  its origin stays, with "· reworded by you".
- **And outside edits, for a deadline.** Like authorship, it is kept by the
  line's words, so an edit in Obsidian drops it — except a deadline's line,
  whose `^dN` ties it to the deadline whatever its words become.
- **The way back to the chat that made it.** A task gets its own
  conversation (`c` on the row, Ctrl+Enter on the line); a task born in
  another chat starts it with "born in the chat on Themenvorschlag draft" as
  its first line, Enter opening that chat, and the agent reads the earlier
  conversation as background on the first message, so nothing is said
  twice. Two tasks never share one conversation (reversed 2026-11-18:
  "One conversation", below). With the hand: the chat's
  name in the dim line is a link, underlined under the hand, opening the
  chat in the agent's pane beside the note; the hints then name the keys
  once, as after any click.

Fixed with it: the dashboard's place line no longer puts the course's name
over a box's first heading when they differ, and a project's sections also
find a box by its own `#tag`, not only by the heading above it.

## When it acts

In the page only, never on a timer while the student is away, never by
notification (the 2026-09-17 rule, kept):

- **A planning job** runs at most once a day, the first time the page or the
  dashboard opens; again when something it plans around changes (a new
  deadline, a calendar fetch that brought changes, a document filed); and on
  demand ("plan now", a key in the dashboard).
- **The bar** shows a quiet count when proposals or questions wait — the
  page's existing widget, no notification, no sound.
- **The arithmetic is local:** workload per project across the fortnight,
  free days, what is due — computed by code and handed to the model as data.
  The model brings judgement (which day, how big, what is missing).

## Actions, and how far each may go

Autonomy is set **per kind of action**, by the person, at one of three
levels: **ask me** (a proposal) · **do it and tell me** (done, shown as the
agent's, one key undoes it) · **never**. Every kind starts at **ask me**;
the record of outcomes can show the evidence for raising one ("you accepted
9 of 10 do-dates"), and only the person raises it. Per project can come
later.

The first set:

1. **Set a do-date** (`⏳`) on a box.
2. **Add a deadline** noticed in the writing ("hand in by the 30th").
3. **Set a priority.**
4. **Add steps under a box** (new child boxes and bullets, ◇).
5. **Propose dropping** a box that has gone stale.
6. **File a document** from the inbox into a course (below).
7. **"This looks done — tick it?"** — a question only. Ticking is the
   person's act; it is what the sound and the "done today" count are for.
8. **Propose a new project** (2026-10-22) — a question only. Making a
   project is the person's act (from the note's `@`/`#` or the sidebar);
   accepting the card makes its file. The agent may add to an existing
   project's file but never rename or re-tag it, and a file it writes for
   a project that does not exist is not kept (`agent/projects.py`).

Not in the first set: rewording the person's boxes; anything in prose.

## How it asks — the grilling, built in

It should not go ahead with what it does not understand, nor interrogate
about what is simple.

- **It asks when it would otherwise have to guess the person's intent:**
  what a box means ("draft intro" — of which essay?), which of two readings
  is meant, how big something is, whether something is still wanted.
- **It never asks** about what can be computed (free days, workload) or
  about what is cheap and reversible.
- **It asks the way a grilling does:** one question, with its recommended
  answer, so the answer is usually one key.
- **Questions are rows** in the dashboard, beside the work they concern; a
  question holds back only its own action. **At most two questions a run.**
- **Answers are kept** in the agent's notebook (`projects/<course>.md`), so
  it does not ask again.

## The dashboard: proposals and questions as rows

Proposals follow the app's own verbs, so a task, a deadline, a proposal and
a question are all settled the same way — no new keys:

- **Whose turn** (2026-10-23, the student's call). While the planner runs,
  the dashboard's line says "planning…" — the agent's turn. What it has
  proposed is the student's turn: a row that arrived since the dashboard
  was last left says **new** in the accent before its reason, and the line
  counts them ("21 from the agent, 4 new"). New is by the ledger's ids,
  not `at` (a plan's start), so a plan that ends after the dashboard was
  left is new next time; the last id seen is machine state (`page.json`).
  No "I'm on it" state to set: settling a row is the processing.
- **N** goes to the next proposal, question or thing done to settle, past
  the cursor and round again at the end; **Shift+N** the one before — the
  queue worked through without walking to it. One new key, asked for by
  the student on 2026-10-23.
- **Space / E** accept (on a question: the recommended answer). Ctrl+Enter
  accepted too until 2026-10-27; it opens the chat now.
- **Del** declines; it asks nothing back, and the record notes it.
- **Enter** on anything the agent offers — a proposal, a question, what it
  did on its own — opens a conversation about it (below): writing back
  means there is something to talk about. A document to file opens
  instead; on anything else, Enter goes to the line.
- A proposed do-date is a **◇ row under its task**, not a pill on the task's
  row, so Space on the task still ticks the task.
- New boxes and deadlines are ◇ rows in the band they would belong to.

## Talking about a proposal

Decided with the student on 2026-10-20: a proposal is something to talk
about, not only to take or leave, as any block is in the note.

- **Enter on a proposal, a question, or what the agent did on its own**
  opens the margin beside the dashboard, which gives up the room (a list
  has more width than it needs). It is pinned at the top — a proposal with
  its reason, a question with its recommended answer; the conversation box
  is ready. Space / Enter on the pinned item accepts (a question: the
  recommended answer; a thing done: let it stand), Del declines (a
  question: set aside; a thing done: undone), Esc goes back to the list.
  Widened the same day, from proposals only, when a typed answer to a
  question went one way: the student answered with a question of their own
  and got no reply.
- **One conversation per task** (reversed 2026-11-18: "One conversation",
  below)**,** shared by every proposal about the box
  or a box under it, and by the margin of its note: what was said in the
  margin (the block's record, in the day's state) and what was said with
  the planner (the ledger's `threads`) are shown as one, merged by time —
  in the margin beside the dashboard and in the note's margin alike — and
  each agent reads the other's part before it answers. A deadline found in
  the writing has no box yet: its conversation is filed under its words; a
  question about no box, under its own.
- **Summoned on any task** (C or Ctrl+Enter on its row, or the "chat" the
  row shows where the keys or the mouse are, since 2026-10-27; Ctrl+Shift+Enter
  from 2026-10-23, Alt+→ before): the margin opens beside the dashboard on
  the task's one conversation, to think it through. The row says how that
  conversation stands (2026-10-28): the note's gutter bar beside it (the
  accent while the agent's last word is unread, dim once read, a light
  travelling down it while the agent answers), and on the selected row its
  last line, the agent's after ◇, yours after "you:". Nothing is pinned to accept; a message
  goes to the margin agent, about the task's block, as Ctrl+Enter in the
  note would — it knows the notes, the course's documents and what the
  planner said. Once a pinned proposal is settled, the conversation goes on
  the same way.
- **What the margin agent proposes there is a card there** (2026-11-03).
  Found when the student asked a task's chat to "create a new task": the
  agent said "Proposed", and nothing showed — its cards were kept on the
  block (the note's margin draws them), but beside the dashboard the margin
  drew only the turns, and the ledger never had them. They stay the
  block's cards (they bind the box's own line, and move a deadline, which
  the ledger's kinds do not), and `thread` now gives each answer its cards:
  drawn under it beside the dashboard, ↑ from the empty box onto them,
  Space runs `accept` on the block the chat is filed under. The box the
  chat is about says "◇ a card in its chat" on its row while one from the
  last week waits (`next`'s `chat.cards`; older ones go quiet, still in the
  chat). Asked again, the same card is that card; about the same deadline
  in other words, it takes the open one's place (`superseded`, drawn faint,
  not accepted).
- **The planner answers,** given back the very payload it planned from (it
  is logged), then the proposal, what came of its others about the box, the
  box as it stands, and the conversation. Its instructions for the
  conversation travel with the message (`TALK_MESSAGE`); the planner's own
  prompt is unchanged.
- **It may revise** its proposal: the same kind, the same box, through the
  plan's own checks. The revision takes the old one's place (the old is
  settled as `revised`) and waits for the person, whatever the action's
  autonomy.
- **An agreement settles it,** either way — the person agreeing to the
  proposal, or the planner to what the person asked (a revision giving
  exactly that). A decline is recorded by the runner; an accept is written
  by the page, as any accept is. A question is settled by the runner: the
  answer kept in `answers.md` is the one the two agreed on, in the
  person's terms (the recommended one when they simply agreed). A thing
  done is let stand by the runner, undone by the page. The planner is told never to settle on its
  own judgement; when unsure, the person still has their keys.
- **The person's words are the reason** kept with the answer, however it
  is given — by agreement, by key in the margin, or by key on the row after
  talking — so the review and the evals have more than a silent Del. The
  next plan carries each box's last few turns (`conversations`).

## The day conversation — talking to the day, not to a line

(A note's own conversation, for a file or a day the agent does not
otherwise see, borrows this agent and pane: `docs/files.md`, "Talking about
a note", 2026-10-27.)

Decided with the student in a grilling on 2026-10-20/21: an agent to talk to
about the tasks and the context itself — what was written, searchable —
not only about one block. A conversation attached to **the day**.

**Where it lives.** The right pane, from anywhere in the page: **Ctrl+3**
(go there; in it, the day's chat ↔ this one), **Ctrl+|** (open or close;
Ctrl+J and Ctrl+] until 2026-10-27) and **Ctrl+Shift+Enter** (the shifted twin of Ctrl+Enter:
the whole rather than this block). Until then Ctrl+Shift+Enter worked in
the note only and opened with the cursor's block referenced; `@` in the
box points at a block now. The
**seal**, moved to the centre of the header, opens and closes it; it never
carries a badge (the brand rule stands). The **date**, at the left, opens
the left sidebar — the click lands on the side the thing appears. The day is
the pane's home: a block's or a task's conversation is a room stepped into
on purpose (Alt+→ on a block, Enter on a proposal), one key back to the day.

**One per day.** One model session a day; within it nothing is compressed
(a fresh session seeded with a brief only if a day ever grows very long).
The next morning a small run writes the day's **brief** into the notebook
(`days/<date>.md`), correctable and forgettable in Settings → what the agent
knows; each new day reads the last few. A past day's note shows its own
conversation, read-only; talking happens in today's, which can search the
old ones. A day marked private still has its conversation — it sees nothing
of the note and says so.

**What it knows.** At its first message: today's note, the notebook, the
calendar, deadlines and tasks (the margin's context). (Since 2026-11-18
what one place sees of the others is the one conversation's memory, by
subject: "One conversation", slice 1.) **Cross-visibility:**
it sees today's block and task conversations in full; they see its last
~6 turns. **`@`** in its box references a block (a chip); the agent gets
the block and its conversation. It speaks first only by setting the morning
observation at the top of the conversation, waiting — no sound, no
notification.

**What it searches.** It asks; local code searches and logs it, and the
same conversation runs once more (the documents' tiers): passages first,
then a whole file on request, two follow-ups at most; it answers with
clickable file:line links, and "searched / read" under the reply.
**Settings → what the agent may search:** each vault folder on or off by
click or key — on by default Daily, Studies, projects, Reference, Career,
Archive; off Personal, Health, _Attachments; `_Secrets` never listed.
**Never shared, whatever the switches:** private notes and blocks; daily
notes before the agent's horizon (2026-10-26, `docs/files.md`); any type
but `.md`, `.txt` and `.pdf` with text; names of identity, money, health,
contract or secret documents (English and German); what gitleaks flags;
IBAN- and card-shaped strings masked. The payload log counts what was
withheld, never what. (Measured 2026-10-21: gitleaks finds nothing but a
known false positive in the default folders; `Personal` holds 72 money and
10 identity names, hence off; `.gitignore` is not the rule — course
documents are ignored by git on purpose.)

**What it does.** Talks, searches, writes its notebook; proposes through the
same kinds and autonomy as the planner, each proposal a **structured card**
under its reply — ◇ and the kind in small caps, the facts with a date pill,
the reason faint, the keys — the same item as its dashboard row. Never
writes the student's notes. Conversational, short by default, citing lines.
Its own prompt (`longhand-day.md`), rated helpful or not, with eval cases
from real conversations and the install gate; the margin's model.

**Slices:** (1) the conversation in the pane — keys, seal and date, the
morning line, past days, cross-visibility, the private day; (2) search —
the switches, the never-list, citations; (3) `@` references and the
proposal cards; (4) the day's brief; (5) the prompt's eval cases.

**How the cards work (slice 3, built 2026-10-21).** The day's first message
carries what the planner plans from — the fortnight, the boxes without a
day, every open box, the kinds the student allows — and a later message
carries it again only when it changed. What the agent proposes goes
through the planner's own `validate` (against what is open, what the store
has closed, what was declined or undone, and the autonomy levels) and into
the one ledger, marked `from: day`; a proposal the same as one still open
is that one, not a new item. The turn keeps each card's words, so a card
settled since — on its row, by a later plan — still reads, faint, saying
how. ↑ from the empty box goes onto the cards; Enter or Space does what
one says (written by the page, as from its row), Del declines it or, for
what it did on its own, undoes it. A card made after the page last read
the ledger is "arriving", never "settled".

**A drop asked for, and a card refused (2026-10-27).** Found when the
student asked the day to strike a duplicate deadline box ("the task is the
same one"): the agent proposed the drop and said "accept the card below",
but `validate` allowed dropping only a box stale and not yet due, so the
proposal vanished and no card came. In the day conversation (`asked`), a
drop is offered whatever the box's age or due date, with its reason — the
student is there asking, and the card is still theirs to accept; the
planner's rule is unchanged. And whatever local code still refuses is no
longer silent: the turn keeps it (`unoffered`), the page says "not offered
as a card" under the reply, and the next message tells the agent, whose
prompt no longer lets it point at a card it cannot see.

**A block's chat changes what is there (2026-11-15).** Found on a new
"AI Literacy course" box (#63, the 20th): "do this task by wed" gave a
card "add deadline", which added #64 on the 18th beside #63 — the margin's
card named a deadline only by its words, and with two alike (#63 and
January's #32) local code made a new one rather than guess. Asked then to
remove the 18th and the 20th, the agent had no card to do it and sent the
student to the dashboard. Now a block's chat proposes the day
conversation's cards too — a day for a box (`do-date`) and dropping one
(`drop`) — checked by `validate` as the day's are (`asked`), recorded in
the one list (`from: margin`), and drawn in the margin under the answer
that made them, the block keeping a copy that names the item (`ledger`).
Enter does what one says, written by the page as from its row; Del
declines it. The margin is shown what it may propose about: the boxes that
read like the block (at most eight, with each box's deadline number) and
the deadlines the store holds with no line (`deadlines_with_no_line`) —
the duplicates someone asks to tidy, not the whole list, which is the
day's. A deadline with no line is dropped by its number, and accepting it
cancels it in the store, as Del on its row does; a number that has a line
becomes its box's drop. A move names the deadline it moves (`moves: n`); a
number that is not open is no card, and is said back; a new deadline with
others alike says which ("beside #63, #32"), so it is never taken for a
move. The day conversation is shown the deadlines with no line as well.
Tests: `tests/test_margin_cards.py`, and 10b' in `tests/page/run.py`.

**The day's chat of 2026-11-19.** Read back with the student, one morning
of their own use. "Change my late tasks for today" was refused twice — a
do-date could go only on a box with no day, so a late one could not be
moved. Now a conversation (`asked`) may give a box that has a day another
one, the day it had kept as `was` (undoing the card puts it back; the
card is moot only once the box carries a third day), and `open_boxes`
marks `late` the boxes whose day has gone by. A planning pass still never
moves a day already set. "Tell me its path", about a PDF, came with the
AI literacy box under the cursor, and the agent had to ask which was
meant: the chip that follows the cursor now arrives marked as attached by
itself, with a line saying to answer the conversation when the message
plainly carries on from it (in the payload, beside the chip: the same
words in the prompt cost the `day-seed-email-date` case 5 runs in 6). The rest of that morning was filing (below,
"Documents").

**How the brief works (slice 4, built 2026-10-21).** The day's first run —
the morning pass, the plan, or the first message to the day, whichever
comes first; runs that start together wait for each other — writes the
brief of each of the last seven days that had a conversation the agent
answered in and has none yet. The day agent writes it from that day's
turns and what came of its proposals (not from the note), three to six
lines, each its own line so Settings can correct or forget it; an empty
answer means nothing was worth carrying. The student's corrections are
applied as it is written. Each day is briefed once (its state says so), so
a brief forgotten line by line does not come back. A day whose note is
marked private gets none: what was said there does not travel. Every
payload carries the last three briefs, after the knowledge files; Settings
→ what the agent knows lists them after its other notes, newest first.

**How it is checked (slice 5, built 2026-10-21).** Its answers are rated
helpful or not in the pane, like the margin's replies (a click under the
answer, or Alt+= / Alt+- on the last one); the weekly review counts them,
the cards and the briefs, and names `longhand-agent eval add <payload>
--job day` for each miss. A day case is one payload: a later message is
joined to its day's first message and the turns between, since the
session that held them is gone. Its rules: what the reply must or must not
say, whether it asks to search or read (and with which words) instead of
answering, which proposals must survive plan.py's checks and which must
not, and for a brief, three to six lines; criteria go to the judge. With
cases in the vault, `install` refuses a changed `longhand-day.md` that has
not passed them. The first six are seeds from a throwaway vault, to be
replaced by real conversations.

## One conversation (grilled 2026-11-18)

**Status:** designed with the student on 2026-11-18; slice 1 (one store,
one memory) built the same day, the rest not; the slices at the end of
this section are the order. It comes from the UX evaluation
of the same day (vault, `projects/longhand/ux-evaluation-2026-11-18.md`,
F8: six places to talk to the agent) and replaces, once built, the
separate conversations described above: "Talking about a proposal", "The
day conversation", a block's margin chat, a task's chat beside the
dashboard, a note's and a paper's.

**What was found first.** Six kinds on screen were four in storage: a
task's chat beside the dashboard is its block's margin chat merged with
the planner's talk about that box. In five weeks the planner's talk had 3
threads and 4 messages from the student, and it alone started a fresh
session with every message; a note's chat had never been used; a paper's
had 27 messages since 2026-11-15, blocks and tasks 65 over 27 blocks, the
day 13. What each saw of the others was uneven: the day saw every other
conversation in full; blocks, tasks and the planner saw the day's last six
turns; notes and papers saw nothing of the rest.

**The pain,** in the student's words: the agent forgets, and "I just need
to get things done from anywhere I am at". Not the number of panes as
such.

**One conversation, not one per thing.** The student's own turn in the
grilling: a task lives in the daily note too, so why would the task and the
day have different chats — "wouldn't it be better to have a mechanism like
for papers where I am able to mention tasks and talk about them on a
general chat". So: one conversation, continuous, with a divider between
days. This **reverses, on purpose,** "one conversation per task" (above,
2026-10-20) and "two tasks never share one conversation" (2026-11-03).
Their reason — "change it to tomorrow" must know what "it" is — is met by
references instead: every message shows what it is about before it is
sent.

**References, always seen and removable** (the student: "I can clearly see
what it is referring to, and remove references if I want to"). A row of
chips above the box, each saying its kind and a short name: `task · Draft
the intro`, `paper · Smith 2021 ^3`, `note · 18 Nov`, `block · "the method
section…"`.
- What the student is looking at is attached on its own: the selected
  task, the block under the cursor, the open paper. That chip is drawn
  dimmer and follows the selection until the first character is typed;
  from then on it is fixed for that message.
- `@` in the box adds any task, note or paper (today it points at a block
  of the open note only; `^` keeps pointing at a paper's marks). × under
  the hand removes a chip; Backspace in an empty box removes the last.
- A sent turn keeps its chips above it, dim, each opening its thing.
- A card in an answer always names what it changes ("move · Draft the
  intro → Fri").
- A box under a task is never a subject of its own: it goes with its task.

**Two views of the one conversation,** so that many blocks' conversations
merged into one stay readable (the student's worry):
- **About this:** only the turns that mention the thing the student is on.
  A block's gutter bar, a dashboard task, a paper open it. It reads as the
  per-thing chat did; what differs is underneath.
- **Everything:** the whole conversation by time. Turns about one subject
  are grouped under one chip; the group the student is on is open, the
  others fold to their last line; an earlier day folds to one line ("Mon 16
  Nov · 3 subjects · 9 turns"). A turn with two chips shows under both; a
  turn with none shows here only.
- The pane follows where the student is: something attached, "about
  this"; nothing attached, "everything", at today.

**Where it lives.** The agent's pane, always, with the keys it has:
Ctrl+| opens or closes it, Ctrl+3 goes there and, in it, switches the two
views (as it switches the day's chat and a block's today), Ctrl+Enter on a
block and C on a dashboard task open it with that thing attached. The
note's margin stops being a chat of its own: a block that has turns keeps
its quiet gutter bar, and Enter on it opens the pane on "about this". No
new key.

**One voice.** One agent to the student: the planner's proposals and the
morning line are turns in the conversation, answered under them — which
ends the opening line that could not be replied to where it appeared. A
proposal still shows on its dashboard row.

**What the agent is given with each message — memory follows the
subject.** Today's turns; for each chip, the earlier turns that mention it
(the last 12 a subject, a number to tune in use); each chip's own content
(the task and its steps, the block, the paper's marks); the open proposals
about them; never anything private. The model's session is one per day
and per machine, so it stays fast; what carries across days and machines
is this, not the session. One rule in place of the uneven ones above.

**It speaks quietly.** What the agent says unasked (the morning line, a
proposal, the open pass) is written into the conversation; the seal says
something is unread; the pane never opens by itself.

**A tool, to read only.** Reopened by the student ("not sure that is the
right thing anymore"). Until now the agent saw only what local code packed
for it and could look nothing up while answering. It gets read-only
tools: search the vault, read a note, a paper's text, a course document —
never what is private, which our own search code enforces, not the prompt.
Each lookup is logged and shown dim under the answer ("read: Essay
draft"). It still writes nothing: every change is done by local code from
its answer, as a card. This amends "Why" (it has no tools) and "Reaching
a model" (a run offered any tool is dropped): one narrow tool of ours is
offered, and the log holds what it looked up as well as what it was given.

**What one message can do, from anywhere:** move a date and break a task
into steps (both exist), add a task to a note or a course, tick or untick
a task, open something ("open my essay draft"), file a document from
Downloads (today from the dashboard only). The larger ones (dates, steps,
a new task, filing) come as a card accepted with Enter; the small ones
(open, tick) are done at once and can be undone. Never a word written into
the student's own text.

**The conversations that exist** (about 110 messages) are merged in, by
time, each turn with its old subject as its chip.

**Two machines.** Each appends to a log of its own in the vault, merged by
time on read, as the proposals (`psync.py`) and the check-ins are. Today's
one file a day (`daily/<date>.json`), written from both, is the one place
left where Syncthing can leave a conflict copy.

**What stays:** the student drives; what is private is never seen; Stop,
a conversation surviving a change of model, the note's look.

**Slices, each usable alone and installed on both machines:**
1. ~~One store and one memory~~ *built 2026-11-18*: `agent/convo.py`,
   the log `<agentDir>/conversation/<host>.jsonl`, `longhand-agent
   conversation`. This alone answers "it forgets".
   - **The store.** A turn is a line: when, who, the words, where it was
     said (`where`, `thread`), what it is about (`subjects`: `task:<key>`,
     `block:<day>:<hash>`, `day:<day>`, `note:<path>`, `paper:<path>`;
     `ask:<key>` for a question about no box), a name for each. Its id is
     made from where, when, who and the words, so a turn written twice, or
     by both machines, is one. A box under a task has the task as its
     subject (`task_subject`, walking up as plan.py's `root_key` does);
     an answer has the subjects of what was asked.
   - **Every place still keeps and shows its own turns** (the day's state,
     a note's file, the ledger's threads). Right after a place writes,
     what it wrote is merged into the log from its store (`convo_merge`);
     the conversations from before were brought in by the same path: 248
     turns, 92 of them the student's, from 2026-09-17 on.
   - **The memory** (`convo_memory`), with every message and every pass
     the page starts: per subject, the last 12 turns said elsewhere; and
     up to 24 of today's turns said elsewhere; each at most 600
     characters, saying where and when. Never the place's own turns (its
     session, or "this chat so far", has them), never a failed answer,
     never what the session was given before (the ids are kept with the
     session: `memory` in a block's record, the day's, a note's file). A
     note asked about that the agent may not see otherwise (marked
     private, before the horizon, in a folder switched off) is `closed`:
     kept, carried nowhere else.
   - **What it replaced:** the day's last six turns in the margin's and
     the planner's payloads (`day_tail`), today's other conversations in
     the day's (`today_conversations`), the planner's turns about a box in
     the margin's (`planner_seen`), the margin's talk in the planner's
     (`margin_talk`), a pointed block's margin conversation in the day's.
     A note's and a paper's chat, which saw nothing, get the same.
   - **Moved to slice 2:** the screens reading from the log. They read
     their own stores until the pane does, so the day's one file is still
     written by both machines for what the screens show; the turns
     themselves are in the logs whatever happens to it.
   - No prompt changed (the payload's section says what it is; "One voice"
     is slice 3). Tests: `tests/test_convo.py`; the day's and the plan's
     tests say the new section.
2. The pane, reading the one store (and the places' own stores of turns
   retired with it): chips, the two views, Ctrl+Enter and C opening it,
   the margin's chat retired, the gutter bar kept.
   *The first part built 2026-11-18,* over the places as they are:
   - **Chips** (`Chips.qml`), above the box of the day's chat: what the
     next message is about, each `kind · name` with a ×. What the
     student is looking at attaches itself, dimmer — the selected row
     beside the dashboard, the block under the cursor in the note, a
     paragraph as much as a box (first built for boxes only; the
     student: a paragraph too, as designed — the chip is seen and goes
     with one Backspace) — following the selection until the first
     character, then fixed for that message (`dayAuto`, `dayTyped`).
     `@` lists the open note's blocks, the open tasks of other days and,
     once a word is typed, the notes and papers the agent may see anyway
     (`conversation --files`: switched on, not marked private, not
     before the horizon; a private note is talked about in its own chat
     only, the student's call); several can go with one message. Backspace in the empty box lets go of the last, then of the
     automatic one, which stays let go until the selection moves. A sent
     turn keeps its chips over it. The usage log counts `chip`
     (`auto-removed`, `removed`, `sent-N`), for "how it is judged".
   - **The runner:** `day --refs` takes what a message points at, blocks
     of today's note by hash or of any day's by line (`resolve_refs`: a
     private one, or one before the horizon, is counted and never
     shown); and notes and papers by path (`file_ref`: a note comes
     whole, its private callouts left out, up to 12 000 characters; a
     paper by its name, read when the agent asks). The turn keeps them
     (`refs`), and the log has the message, and its answer, about all
     of them.
   - **"Everything"** is the day's chat grown (`EVERYTHING · TODAY`):
     above its turns the earlier days, a line each (fourteen at most),
     unfolding to the places talked in that day; among its turns, in the
     order said, today's other places (a task's chat, a paper's), folded
     to how many turns and their last words (`FoldLine.qml`,
     `conversation --view`). ↑ from the empty box goes to the lines (after
     the cards, when there are any), Enter or a click opens what a line
     is about: a task's chat beside the dashboard, a paper's or a note's
     room, a closed task's note.
   - **"About this"** is a task's or a block's chat as it was
     (`Margin.qml`), saying so, with its one chip above the box (× leaves
     for the day's chat with what was typed) and, first, what was said
     about it elsewhere — the day's chat pointing at it, another day's
     margin for the same task (`conversation --elsewhere`): shown when
     short, folded to a line when long. Ctrl+3 in the pane goes between
     the two views, as it did between the day's chat and a block's.
   - *The rest, built 2026-11-18 after slice 4:*
     - **One way to draw a turn** (`Turn.qml`), in every pane — the day's
       chat, a note's, a paper's, a block's, a task's: what it pointed
       at, where and when when it was said elsewhere, the words, how a
       talk ended, what was not offered. `MentionList.qml`, the `@` list,
       the same in every box.
     - **"About this" is one stream:** a task's or a block's own turns
       and what was said about it anywhere else, read from the one
       conversation's log, in the order said; a turn from elsewhere drawn
       dim under "19:17, in the day's chat" (`talkStream`,
       `marginStream`). It replaces the folded "N turns about this
       elsewhere".
     - **`@` and chips in a task's or a block's chat:** tasks of other
       days, notes and papers, as in the day's; `chat --refs` carries them,
       the turn keeps them, the log files the message under them.
     - **Each place's own store stays** (the student's choice): the
       day's file, a note's, the proposals list keep ratings, cards,
       unread marks, sessions and cost, and what reads them (the review,
       the stats, the briefs, the planner) is unchanged. The panes'
       components stay two files (`DayPane.qml`, `Margin.qml`): the
       pinned proposal and the block's proposal rows are the margin's,
       the paper's marks the day pane's; what they share is drawn by the
       shared components.
3. ~~One voice~~ *built 2026-11-18:* one agent answers whatever the
   student types, wherever.
   - **A block's or a task's chat** is answered by the one agent
     (`longhand-day.md`, "Longhand, the one voice"), no longer the
     margin's own (`cmd_chat`): the day's context, the block as what the
     message points at ("# This conversation", `CHAT_INTRO`), the chat so
     far, the one conversation's memory, search and read, and what the
     day's chat may propose — every box, with the boxes and loose
     deadlines that read like this block named (`like_this_block`). Its
     turns stay on the block. A deadline it proposes is the block's own
     card, so a move (`"moves": n`) still has one there; anything else
     goes into the one list. A session the margin's agent began is not
     reused (`voice`); the first message carries the chat so far.
   - **A talk about a proposal** is the one agent's too (`cmd_talk`;
     its message says "as Longhand, who made the proposal"); the planner
     still plans, as a pass of its own. The eval job `talk` checks the
     day's prompt now.
   - **The margin's own agent** (`longhand.md`) is left the passes the
     page starts unasked: a box written, a question, a tick, the page
     opening. Its words reach the one conversation as before.
   - **The morning line** is a turn in its place among the day's turns
     ("when you opened the page · 08:12"), answered in the box like any.
   - **What planning proposed**, still open, is a line of "everything"
     ("proposals · from planning · N waiting"), opening the dashboard on
     the next one: settled where it is listed.
   - *A deadline moved from the day's chat* came with slice 4.
   - Evals: two cases from a scratch copy of the vault, `day-chat-move-
     themenvorschlag` (a task's chat moves #61, adds none) and
     `day-move-from-the-day`; `check_day` reads `moves` and
     `no_new_deadline`.
4. ~~The new actions~~ *built 2026-11-18:* what one message can do,
   from any chat — the day's, a block's or a task's, a note's, a paper's.
   - **Three kinds for a conversation only** (plan.py `ASKED_ONLY`, never
     from a planning pass): `task` (a box the student asks for, written
     by the page into today's note under its course, the agent's line;
     undone by taking the line out), `move` (a deadline by its number to
     a new day, keeping the day it had, `was`, for the undo; each day
     moved to its own proposal, a newer one superseding an open older
     one; a declined one blocks no other), `undone` (a box ticked in the
     last seven days, `ticked_lately`, reopened).
   - **Done at once when asked:** `done` with `"asked": true` (the
     student said to tick it) and `undone` are carried out by the page
     as soon as they arrive, as at "do it and tell me", and shown as a
     card to let stand or undo (Del). A `done` without `asked` is still
     the card "looks done — tick it?". An undone tick does not block the
     next one asked for.
   - **Open:** the answer may name one thing to open (`open`: a vault
     path, a day, a box key), checked by local code (`open_targets`); the
     page opens it when that answer arrives, never again on a later read.
     The prompt says a path not seen is searched for, never guessed.
   - **A note's and a paper's chat** propose what the student asks for,
     file and open, as the day's does; they proposed nothing before.
   - **A block's chat** keeps its own card for a move (`chat_card`);
     everywhere else a move is a card of the one list.
   - The new kinds are in Settings → what the agent may do, at "ask me";
     "never" turns one off.
   - Evals: `day-move-from-the-day` (now a card), `day-add-task`,
     `day-tick-when-asked`, `day-open-when-asked`; `check_day` reads
     `ticks` and `opens`. Tests: `tests/test_anywhere.py`; live checks for
     a new task's card, a tick done at once and undone, opening.
5. ~~The read tool~~ *built 2026-11-18, as the loop that was there:*
   checking first showed the agent could already look things up while
   answering — it asks in its answer (`search`, `read`), local code
   fetches under search.py's rules, and the same session is asked again,
   each round logged as a payload of its own (`day_follow`, since
   2026-10-21). The student chose to extend that loop rather than give
   the model a tool it calls itself (a server of ours, a way into the
   files to secure, "the model gets no tools" given up on both routes,
   for little more speed: each lookup is a model round trip either way).
   - Up to four rounds a message (`DAY_ROUNDS`, two before), each saying
     how many are left.
   - A talk about a proposal may look things up too (`cmd_talk`, its
     message's contract; `parse_talk` reads `search` and `read`).
   - What was looked up — searched, read, a course's document, filed —
     is said under every answer in every pane (`Turn.qml`, `sayFetched`),
     a task's turns carrying it from `thread`.
   - "Why" and "Reaching a model" stand as written: the model has no
     tools; what it sees is still what local code gave it, logged.

**How it is judged,** read at the check-in after two weeks of use: the
weekly check-in's practical score before and after; messages a week in the
one conversation, against about 110 over the month before; how often an
automatic chip is removed (the attach rule guessing wrong); how often
"everything" is opened. All four counted in the usage log.

**Left to the building:** rewinding a conversation (plan.md, item 22) now
means rewinding the one; how a past day's note shows its part; the first
number for "the last 12 a subject".

## The record, and what it learns

- **The proposal ledger** (in the layer): every proposal and question, what
  it rested on, and what came of it — accepted, declined, ignored, undone.
  `stats` reports acceptance per kind of action; the evidence for raising
  an action's autonomy comes from here.
- **The notebook grows from three sources:** the person's answers to its
  questions; the ledger, summarised into `patterns.md` by local code (numbers,
  not the model's impressions); and what it notices in the notes and
  calendars, as today.
- **"What the agent knows"** in Settings shows its notebook line by line,
  each with **correct** and **forget**. Corrections go to `corrections.md`,
  which the agent reads every run and never writes — as `dismissed.md`
  already works — and it is told the person's corrections overrule its own
  notes. A correction made once stays made.

## Calendars

What the agent sees is chosen **per calendar** (built 2026-10-17): its
classes only, or everything in it — titles, times and places, never
descriptions. The IT:U calendar is the university's own, so the agent sees
all of it (an event there is the student acting for IT:U). A personal
calendar can be added beside it; "classes only" on a calendar without
classes is the agent seeing nothing of it.

## Documents: consulted, never carried

Course documents are for the agent to consult — no space in git, no tokens,
nothing — unless needed. The student does not read them in Longhand; opening
the PDF is better.

- **The inbox is the Downloads folder.** Local code, on this machine, finds
  PDFs that belong to a course — its code, title or tag in the file name
  or on the first two pages, or downloaded during one of its classes or in
  the two hours after (2026-10-18: of 67 PDFs in Downloads, no file name
  named a course, two first pages did, and the class times found the
  readings saved in class) — and proposes filing them
  ("move *The_Seven_Deadly_Myths…pdf* to Interdisciplinary Seminar as
  '2026-10-14 The Seven Deadly Myths of Autonomous Systems'?"). Nothing
  that does not match is ever listed, named or shown to the agent — the
  folder also holds invoices and an ID certificate whose number is in its
  file name. Filing is action 6, so it starts at "ask me". A file can also
  be handed over by hand, or **asked for in the day's conversation**
  (2026-11-17): the reply's `file` key names a document and a project;
  asking is the consent, so local code (`day_file`) files it at once —
  unless filing is "never" — and settles the dashboard's row about it as
  accepted, in the project asked for. The agent is shown only what waits
  (`documents_waiting`); any other PDF is found only when the student's
  own words name it. The answer says "filed … in #tag", and the next
  message tells the agent what was and was not filed. On 2026-11-19 the
  student asked for five papers in Downloads to go into #thesis: the
  agent could not see them (they matched no course) and had to ask for
  their names; four of the five were already, byte for byte, in the
  thesis's literature folder, which the duplicate check never looked in;
  and they were filed as "2026-11-19 <title>" into a new
  `projects/thesis/docs`, where the student wanted the author first. Now
  (the student's calls that day): a PDF the vault holds anywhere, by
  size then content, is never filed or proposed again, and the answer
  says where the copy is; a paper (a DOI, an arXiv id, an ISSN or an
  abstract on page 1, and a first author read from the page or a
  confirmed Author field) is filed as "Surname Year Title"; a project's
  file may name its documents' folder (`- Docs: <vault path>`, kept
  through the agent's rewrites), #thesis's being its literature folder;
  and a message about downloads or papers carries `papers_in_downloads`,
  the PDFs there with a DOI or an arXiv id on page 1, not personal and not
  in the vault, each with the name it would be filed under. Found on the way: a
  filing proposal was known by its course's name, so a second paper for a
  course was taken for the one still waiting and never proposed; it is
  known by its contents now (`plan.ident`).
- **They live in the vault but outside git:** `projects/<course>/docs/`,
  synced between the machines, ignored by the hourly commit (they can be
  downloaded again from the portal). A project's page in the sidebar lists
  them and opens them in the PDF viewer.
- **The agent reads them in three tiers** (progressive disclosure, as agent
  skills load):
  1. *Index* — on a run about a course: title, date, pages of that course's
     documents. A line each; nothing read. A conversation already under
     way gets the index again, once, when a document was filed since its
     session last saw it (2026-10-23: a thread begun on 12 Oct never
     learnt of the PDFs filed for it).
  2. *Whole* — when it asks for one by name: converted to Markdown on this
     machine, kept in the state folder (not the vault), carried in the next
     run. Fine for a syllabus or a handout.
  3. *Search* — for long documents: it asks for words in a document; local
     code searches the converted text and carries the passages with their
     page numbers.

  No embeddings, no index service: plain files and keyword search, so
  principle 1 holds and an answer can say which page it came from. The
  model asks; local code fetches into the next run — the inversion already
  used for proposals, which keeps the payload log the complete record.

## Reaching a model

Today every run goes through opencode to DeepSeek v4.1 Flash (OpenCode Go),
which keeps runs cheap but ties every model to opencode — whose 2.0 release
silently broke every pass on 2026-10-15, and which no longer offers Claude's
subscription login.

- **The runner becomes pluggable**: one small layer with the same three
  jobs on every route — run a payload, continue a conversation, report the
  cost.
- **Every route keeps the agent's rule**, each with a test that proves it:
  no tools, no agent instructions loaded (`~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`), the payload logged before inference.
- **Routes:** opencode (today); `codex exec` on the student's ChatGPT
  subscription (OpenAI's own tool) — **built 2026-11-18**, below; the
  OpenAI and Anthropic APIs, metered, the cleanest (no tools unless given);
  `claude -p` (Claude Code) on the Claude subscription — **built
  2026-11-17**, below.
- **The Claude Code route (built 2026-11-17).** A model named
  `claude-code/<model>` runs `claude -p` instead of opencode
  (`run_claude`). Anthropic's terms forbid an app its own Claude login or
  using subscription credentials itself, and allow a person "signing in to
  the unmodified Claude Code binary with their own Claude subscription"
  (code.claude.com/docs/en/legal-and-compliance, read 2026-11-17): Longhand
  only starts Claude Code and never sees the sign-in. The rule, flag by flag:
  `--tools ""`, `--strict-mcp-config`, `--setting-sources ""` (no CLAUDE.md,
  hooks or memory: a run without it carried `~/.claude/CLAUDE.md`, 2,580
  input tokens against 1,020), `--disable-slash-commands`, and the agent's
  definition without its frontmatter as the whole `--system-prompt`. Not
  `--bare`: it refuses the subscription sign-in. Claude Code reports what it
  offered the model; a run offered any tool or server is dropped, and so is
  one whose transcript shows Claude Code attached memory (below). One thing
  still rides along that the payload log does not show: Claude Code attaches
  the account's email, which Anthropic holds anyway. The variant is the
  effort; a subscription run is 0 in the ledger. `tests/test_claude_route.py`.
  **The memory leak (found 2026-11-17, the same day).** The first eval,
  `claude-code/claude-opus-5-5#high`, scored 12/19, and one "invented"
  detail, the student's own Astro site, was true: no payload had it. Every
  run from `~/.local/state/longhand/agent-cwd` had carried Claude Code's
  auto memory of the home-folder project (`~/.claude/projects/-home-pms/
  memory/MEMORY.md`: the website, the home network, the student's profile),
  `--setting-sources ""` notwithstanding; a probe from `/tmp` had not shown
  it. Claude Code treats that folder as inside a repository and takes the
  home folder's memory. Fixed two ways: `CLAUDE_CODE_DISABLE_AUTO_MEMORY`
  and `…_ORG_MEMORY` on every run, and the flags no longer trusted alone —
  after each run the transcript Claude Code saved is read, and a run with an
  attachment outside `CLAUDE_ATTACHMENTS_OK` (environment, model, date, the
  account's email and organisation, the prompt snapshot), or with no
  transcript to read, is dropped. No real run had used the route yet; the
  memory reached Anthropic only, in the eval's and the tests' runs. That
  12/19 is void.
- **Opus 5.5, medium, in use since 2026-11-17** (the student: "implement
  opus 5.5 medium and let's give it a try"): `model` and `planModel` are
  `claude-code/claude-opus-5-5`, `variant` and `planVariant` `medium`;
  `evalJudgeModel` stays `openai/gpt-6.1-sol`, so the judge is the one the
  cases were graded by. Three cases were revised the same day, each saying
  why in its note: two graded a reply's length with its cards' words
  counted and stricter than the day prompt's "two to five sentences", one
  counted "I noted it in your file" (the agent's own knowledge file, which a
  talk may write) as claiming a change.
  On the revised 20 cases the same evening: GPT-6.1 Sol (high) 20/20, Opus
  5.5 (medium) 16/20 — day 9/9, plan 4/5, talk 1/2, margin 2/4. Its misses
  are real and small: a done-date one day off, a two-part question, a plan
  reason that assumed what a session covers, and "nothing to change" where
  the student asked how to move a date. The prompts were tuned on GPT; Opus
  stays in use as a trial, judged by the helpful / not helpful ratings.
  **Prompts for Opus (same evening, the student: "improve the prompts so
  Opus passes all 20").** General rules, each for a failure that came back:
  the deadline report's times are Unix seconds, never worked out into a
  day or a span (Opus once made 16 Oct "15 Oct", once "the same second");
  one question is one thing asked, and two joined by "and" are two (margin
  and day); the page opening gets one or two sentences about one thing, or
  nothing; a day reply's five sentences are a ceiling, the card's `why` not
  repeated; a planner's reason rests on what the data says of a session,
  never on what it supposes the session covers; when the five slots are
  full, steps for a big box come before drops; a talk asked for what is
  already so says so and still says how. Found on the way: local code cut
  every step at 100 characters mid-word into the note ("map … to"); it now
  cuts at a word with "…", and the prompt names the limit. Then Opus 5.5
  medium 20/20 and 17/20 on two full runs (its misses each pass most
  runs), GPT-6.1 Sol 19/20 (the synthetic seed it also failed before the
  change). The runs vary: a single 20/20 is not a guarantee.
- **GPT-6.2 Sol, high, through Codex, in use from 2026-11-18 for a month**
  (the student: "we are going to have 6.2 sol high as the model for the
  next month"): `model` and `planModel` `codex/gpt-6.2-sol`, both variants
  `high`. **The judge is Fable 5.2 from 2026-11-19**
  (`evalJudgeModel: claude-code/claude-fable-5-2#high`, the student's
  call): GPT-6.1 Sol had graded every case, and would now be grading its
  own successor. Its first run, still under the GPT judge, found two faults
  in the eval rather than the model: the judge never saw what an answer
  opens (`open`) nor that a tick was made at once (`asked`), so "Opened
  your thesis note" and "Ticked it" read as claims with nothing behind
  them — both are now in the answer it grades — and a talk case's "how"
  patterns missed "edit the checkbox … in today's … note". On the 25 cases
  with the Fable judge, the same night: GPT-6.2 Sol (high) 25/25, Opus 5.5
  (medium) 24/25 (margin 3/4: a new deadline where the case forbids one),
  GPT-6.1 Sol (high) 20/25 (talk 0/2, margin 2/4: a tick claimed in a talk,
  a question where a card was wanted). The scores are not comparable with
  the GPT judge's above. 6.2 Sol is the slowest of the three: a plan takes
  60–70 s against Opus's 25–50 s; a day reply 7–14 s. The day prompt was
  then tidied for it — the "Proposing" list had "done" twice and the asked
  ticks and two paragraphs inside the list; the same sentences, reordered —
  and "I opened …" is said only beside an `open` that names it, the one
  real miss of its first run. Two runs on the new day prompt: 25/25 both.
- **The Codex route (built 2026-11-18,** the student: "use codex for it …
  with thinking on high"). A model named `codex/<model>` runs `codex exec`
  (`run_codex`) on the student's ChatGPT sign-in, with unmodified Codex:
  Longhand only checks that a sign-in exists. Probed against Codex 0.170
  the same day, with `~/.codex` as its home, every run carried the
  student's `~/.codex/AGENTS.md` whatever the flags (`project_doc_max_bytes
  = 0` does not reach it), and with ChatGPT's defaults the skills list, the
  code-mode `exec` tool and sub-agent tools; the model called `exec` and
  `list_agents` unasked when asked about its tools. So the route runs in a
  Codex folder of its own (`~/.local/state/longhand/codex`, one more
  `codex login` by the student, the student's choice over carrying the
  pointer along) and turns off what config can: every tool feature
  (`CODEX_FEATURES_OFF`), web search, the skills, environment and
  permission notes, user config and rules, a read-only sandbox, the agent's
  definition without its frontmatter as `model_instructions_file` in place
  of Codex's own prompt. What Codex cannot turn off, its conversation
  tools (ask or message the user, list or wait for sub-agents), stays
  offered — the one difference from the Claude Code route, also the
  student's choice — and the flags are checked against the session file
  Codex saves: a run that called any tool, or whose new lines hold
  anything beyond the agent's instructions, Codex's running notes
  (`CODEX_CONTEXT_OK`) and the student's words once, or that saved no file,
  is dropped. Codex appends stdin to a new session's prompt but not to a
  resumed one's, so the words and the payload go together on stdin. The
  effort is `low` … `max`; `ultra` delegates to sub-agents and is refused.
  A ChatGPT run is 0 in the ledger. `tests/test_codex_route.py`.
- **The Antigravity route (built 2026-11-19,** the student: "do it through
  google own pipeline instead of opencode … I don't want to go against any
  rules"). A model named `antigravity/<model>` runs Google's Antigravity CLI
  headless (`agy -p`, `run_antigravity`) on the student's Google AI Pro
  sign-in, with unmodified Antigravity. Google replaced Gemini CLI with it
  for Google One plans on 2026-06-18; Gemini 4 Neon needed `agy` 1.5 (1.1.27
  listed no Gemini 4). The rules, as read on 2026-11-19: Google forbids
  other software from using the CLI's sign-in to reach its servers directly,
  and it documents headless `-p` for scripts and CI. It has not answered
  whether a personal script running its CLI headless on a subscription is
  fine. So the route runs Google's own binary and never reads the sign-in,
  and a weekly routine on the student's machine watches for a ruling.
  Probed against `agy` 1.5.12 the same day:
  - **A home of its own.** `HOME` pointed at
    `~/.local/state/longhand/antigravity` keeps the student's own `~/.gemini`
    out: its omarchy skills and a "science" plugin would ride along
    otherwise. The sign-in lives in the system keyring, so it carries over
    with no second sign-in. Before every run, `antigravity_personal` refuses
    the run if rules, skills, plugins, hooks or MCP servers are found there.
  - **Tools: not all of them can be turned off.** The agent's definition,
    without its frontmatter, becomes a custom agent with `tools: []`. The
    request it makes then carries the agent's instructions as `<System
    Prompt>`, Antigravity's own notes (the folders, the time, artifacts,
    messaging, its guidelines) and two tools, `manage_task` and `schedule`,
    whatever `tools`, `--mode plan` or a `permissions.deny` say. The
    stream's `init.tools` lists all 60 tools of the registry whatever the
    agent gets, so it proves nothing. The steps are checked instead: a run
    with any step beyond the student's words and a reply
    (`ANTIGRAVITY_STEPS_OK`) is dropped, as is one that ran an agent other
    than Longhand's.
  - **The words travel on stdin.** Plain `-p` ignores stdin, and the
    largest payload logged so far (126 KB) is close to the 128 KB an
    argument may hold. So the words and the payload go as one
    `{"event":"user","message":{"content":…}}` line on
    `--input-format stream-json`; `--conversation <id>` resumes.
  - The effort is part of the model's slug (`gemini-4-neon-high`, `low` …
    `xhigh`). A subscription run is 0 in the ledger.
  `tests/test_antigravity_route.py`.
- **The fallback (built 2026-11-19,** the student: "add opus as the
  fallback model"): `fallbackModel`, `claude-code/claude-opus-5-5#medium`
  in use — Opus passed 24/25 at medium under the Fable judge. `run_model`
  hands a pass the model in use failed — any error but a stop: a usage
  limit, a sign-in gone, a run dropped for the agent's rule, a `Fail` such
  as "not signed in" — to the fallback, and marks the failed model passed
  over for `FALLBACK_MINUTES` (30) in `fallback.json`; `routed` reads it at
  every command but `eval`, so the passes after it run on the fallback from
  the start and resume its sessions. No route resumes another's session,
  so a chat that had one on the failed model falls back afresh: the three
  places that resume one (a block's chat, the day's, a note's or paper's)
  give `run_model` a `fresh` that builds the whole context with the chat
  so far, logged as `…-fallback.md` before it is sent. A follow-up round in
  the same pass (documents read, a search) does not fall back: its first
  round already ran on the model that answered. Evals never fall back.
  `tests/test_fallback.py`; checked live the same night with Codex pointed
  at an empty folder and Opus answering.
- **Settings chooses the route per job** — for example, replies to blocks
  on the cheap model, planning on a stronger one.
- **A failing route says so** and does not fall back silently.
- **In use since 2026-10-17:** the OpenCode Go key expired, so the planner
  reaches its own model — `planModel` in the config (with `planVariant` if
  that model names one), set to a ChatGPT-subscription model through
  opencode's renewed OpenAI login; at the student's word the margin moved
  to the same model (`model`), its "high" variant kept. The first real plan
  proposed two sensible do-dates and asked how big a task was; a margin
  pass on the day's real payload came back well-formed — both at no
  metered cost.
- **Which model, 2026-10-18.** Twelve models from both subscriptions were
  run on the real planning payload and a real past margin request,
  recording nothing. All were reliable (every answer well-formed, every
  do-date through plan.py's checks); they differed in judgement. DeepSeek
  v4.1 Flash read the context and asked the right questions; the GPT models
  were fast and plain — not for want of ability but because they follow the
  prompts literally, and the prompts invited it: the margin's rule for a new
  checkbox told it to ask for a date, and the planner's said questions were
  rare. The prompts now say what good is — look across the payload first
  and name a specific, ask (with a best guess) when one answer would change
  the reply or the plan, never ask "by when?" by reflex, a reason names
  what makes the day right, and a question holds back only its own box.
  After that, GPT-6.1 Sol did what the design asks on both tasks in two runs
  each (dates for the clear boxes, grounded questions for the unclear, in
  ~15 s), and is the model for both jobs; DeepSeek v4.1 Flash is the
  fallback (OpenCode Go key renewed the same day).
- **Start planning on the model there is**, so the acceptance rate shows
  whether quality is the limit; switch planning to a stronger route if the
  student declines most of what it proposes.

## The improvement loop — instructions that are not static

Built 2026-10-18. The agent learns facts about the student in its notebook;
how it *behaves* changes only through an edit the person sees and approves,
checked first. The loop:

- **Every run records its prompt and model** — a short fingerprint of the
  exact instructions used (`prompt_version`) and the model — on the block,
  the plan's ledger items, the cost ledger. What came of a run can always be
  told apart by what made it.
- **The student's word on a reply.** Under each reply in the margin:
  *helpful · not helpful* (`+` / `-` in the margin; the same again takes it
  back), kept on the block and in `feedback.tsv`. The plan's accept and
  decline are the same signal for proposals.
- **The eval set** (`agent/evals.py`, `longhand-agent eval`). A case is a
  real run's payload — kept in the vault (`agents/longhand/evals/cases/`),
  never in the public repo — with `rules` checked by code (patterns a reply
  must or must not have; for a plan, what survives plan.py's checks, which
  questions are asked, which boxes get dates) and `criteria` in plain words,
  graded by a judge of its own (`longhand-judge`, every tool denied, given
  the payload so "grounded" can be judged). `eval add` makes a case of a run
  that missed; `eval run` gives every case to the repo's prompts (a
  throwaway opencode configuration, so a prompt is checked before it is
  installed) and keeps the result with the prompt versions and models in
  `evals/results/` — the history.
- **The check before a change.** `longhand-agent install` refuses a changed
  prompt that has not passed its cases on the model it will run on
  (`--force` overrides, said aloud). A model change is checked the softer
  way: Settings → The agent, `eval status` and the review say "never
  checked" until the cases have passed on it.
- **The weekly review** (`longhand-agent review`). Local arithmetic, no
  model: what ran, by prompt and model; how replies were rated; what came of
  proposals and questions; each reply rated not helpful and each declined
  do-date, with the command that makes it a case; whether what runs has
  passed. Written into the vault (`agents/longhand/reviews/<year>-W<week>.md`)
  when the page opens and a week has passed — pull, never on a timer — and
  said once; Settings → The agent opens the latest.

The first three cases (2026-10-18) are the ones the weekend found: the
e-scooter question (engage with the substance; never "by when?"), the
first real plan (dates for the clear boxes, a question about the
supervisor, reasons that name the day), and a page opening with nothing new
(silence, or one grounded observation). The prompts from before the rewrite
fail the first two, as they should; the prompts in use pass all three.

## Slices, in order

Each is usable alone.

1. **Who made it** — authorship in the layer, kept through every edit in the
   page; the three marks in the note and the dashboard. Everything else
   rests on it, and it shares its machinery with keeping a sent block's
   conversation through word edits (plan item 6). **Built 2026-10-17:**
   `plugin-page/Authorship.js` (pure: restore, carry, serialize; unit tests
   in `tests/tst_authorship.qml`), records in `authors.json` beside the
   deadline store, keyed by a line's words; a deadline's line by the ledger's
   `origins` (the agent's while its first words stand, together once
   rewritten). Drawn in the box or dot itself: the person's square and dot;
   the agent's ◇; the seal for together — open as an outline, done filled
   with the tick's colour, like the square. `markAuthor(line, author)` is
   what slice 2 calls when one of the agent's proposals is written in.
2. **Proposals and planning** — the ledger; the planning job with the
   arithmetic done locally; action 1 (do-dates) at "ask me"; questions with
   recommended answers; the rows and keys; the count in the bar; acceptance
   in `stats`. **Built 2026-10-17:** `agent/plan.py` (the fortnight, workload,
   candidates — tasks and deadlines with no do-date, never a note box — the
   checks on what the model answers, the ledger `proposals.json`) and
   `longhand-agent plan | proposals | proposal`, with a planner of its own
   (`agent/opencode/longhand-plan.md`, every tool denied). It plans when the
   page or the dashboard opens (once a day unless what it plans around
   changed; a failed plan is not counted), and on Ctrl+R in the dashboard.
   Two choices made while building: the ledger's record goes into each plan
   as data (`your_record`) rather than being written into `patterns.md` —
   that file is the model's to rewrite; and the student's answers are kept
   in `knowledge/answers.md`, which the agent reads and cannot write. An
   accepted do-date's pill says so with ◇. Tests: `tests/test_plan.py`, and
   the dashboard section of `tests/page/run.py` against a stub model.
3. **The notebook, visible** — Settings → "What the agent knows", correct
   and forget, `corrections.md`. **Built 2026-10-18:** `agent/notebook.py`
   and `longhand-agent notebook [forget|correct|take-back]`; Settings' second
   view (`NotebookSheet.qml`, Enter on its row in Settings; Ctrl+K until 2026-10-28) lists each of the agent's
   files line by line, then the student's answers, then their corrections.
   Forget takes the line out (with what is nested under it), correct puts
   the student's words in its place; local code does both and records them
   in `corrections.md`, which every payload carries as its own section and
   the model can never write. A correction is *enforced*, not only told:
   whenever the model rewrites a file, the whole record is applied again,
   so a line it copies back is corrected or left out regardless of what the
   prompt achieved. Forgetting an answer just removes it (the agent may ask
   again); a correction can be taken back. Tests: `tests/test_notebook.py`,
   and the Settings section of `tests/page/run.py`.
4. **Documents** — the Downloads inbox and filing, the index, conversion
   and search, the project's documents in the sidebar. **First half built
   2026-10-18:** `agent/documents.py`; the inbox is opt-in (`"inbox":
   "~/Downloads"` in config.json), scanned when the dashboard asks for
   proposals, PDFs of the last 60 days only, at its top and one folder
   down (an unpacked course export; 2026-10-23); a match is a ◇ row in its
   course's band ("file “2026-10-14 The Seven Deadly Myths of Autonomous
   Systems” in Human Factors…", why underneath), Space/Ctrl+Enter files
   it into `projects/<tag>/docs/` (named by the download's date and the
   document's own title), Del declines it for good, Enter opens it first.
   The scan's cache keeps only hashes, so an invoice is never named
   anywhere; two copies of one download are one proposal. The project in
   the sidebar lists its documents above its sections (↑ reaches them,
   Enter opens the PDF viewer), and a run about a course carries their
   index, a line each. The vault's `.gitignore` leaves `projects/*/docs/`
   out of git. **Second half built 2026-10-18:** tiers 2 and 3. The
   margin's reply contract has a fifth key, `read`: a document of the
   index by name, whole (`words: ""`) or for a few words. Local code reads
   only the documents of the course the block is about — the ones the
   index showed — converting the PDF once into `doc-text/` in the state
   folder (pages kept apart by pdftotext's form feeds); whole up to 60,000
   characters (else its beginning, and a note to ask for words), search by
   paragraph, best first, eight passages with their pages. "The next run"
   is the same session at once: one follow-up, logged as its own payload
   (`…-read.md`), framed as material and never instructions; its answer is
   the one shown, its requests are not followed again, and the cost is
   both runs'. The block records what was read, and the margin says it
   under the reply ("read: … (p. 1, 4)"), so a citation can be checked.
5. **The other actions** (2–7) and raising an action's autonomy. **Built
   2026-10-18.** Decided first with the student: the planner reads the
   last seven days of notes (private parts removed), as the margin reads
   today's — without it, a deadline in the prose or "got the haircut" under
   an open box cannot be seen; five proposals a run *of all kinds
   together*, plus two questions; what is done on its own is told as
   dashboard rows; raising is suggested at 9 of the last 10 accepted.
   `plan.py` checks every kind against what the planner was shown (a
   deadline not already in the store or a box, dated today to a year on; a
   priority that changes something; at most five steps under a box with
   none; dropping only a box quiet or two weeks old and not yet due; "looks
   done" only with the words that say so) and against what the person
   refused or undid. The page writes each on accept — facts on the box
   (a do-date, a priority, a drop, the tick) or new lines that are the
   agent's ◇ (steps one level in; a deadline's box in today's note, under
   its course when today has one). Autonomy is per kind in settings.json,
   set in Settings → what the agent may do (Enter on its row, Ctrl+M until 2026-10-28; ←→): at "do it and
   tell me" the page does it when it arrives and shows a "done: …" row —
   Space lets it stand, Del undoes it (a deadline's box is cancelled, not
   erased, as any deadline is); "looks done" stays a question, since
   ticking is the person's act. The inbox follows the same setting: filed
   at once and told, or never scanned. Tests: `tests/test_actions.py`,
   and the dashboard and Settings sections of `tests/page/run.py`.

The pluggable runner stands apart from the slices: it can come whenever a
second route is wanted. Claude Code (2026-11-17), Codex (2026-11-18) and
Antigravity (2026-11-19) are built; the OpenAI and Anthropic APIs are left.
