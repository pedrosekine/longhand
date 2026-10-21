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
logged; it has no tools; what it proposes is done by local code, and only
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
  at the end. Accepting is what writes it, so the act is the person's.

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

- **Space / Ctrl+Enter** accept (on a question: the recommended answer).
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
- **One conversation per task,** shared by every proposal about the box
  or a box under it, and by the margin of its note: what was said in the
  margin (the block's record, in the day's state) and what was said with
  the planner (the ledger's `threads`) are shown as one, merged by time —
  in the margin beside the dashboard and in the note's margin alike — and
  each agent reads the other's part before it answers. A deadline found in
  the writing has no box yet: its conversation is filed under its words; a
  question about no box, under its own.
- **Summoned on any task** (Alt+→ on its row, the note's key for a block's
  margin): the margin opens beside the dashboard on the task's one
  conversation, to think it through. Nothing is pinned to accept; a message
  goes to the margin agent, about the task's block, as Ctrl+Enter in the
  note would — it knows the notes, the course's documents and what the
  planner said. Once a pinned proposal is settled, the conversation goes on
  the same way.
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

Decided with the student in a grilling on 2026-10-20/21: an agent to talk to
about the tasks and the context itself — what was written, searchable —
not only about one block. A conversation attached to **the day**.

**Where it lives.** The right pane, from anywhere in the page: **Ctrl+J**
everywhere, **Ctrl+Shift+Enter** in the note (the shifted twin of Ctrl+Enter:
"this, but to the day", opening with the cursor's block referenced). The
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
calendar, deadlines and tasks (the margin's context). **Cross-visibility:**
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
**Never shared, whatever the switches:** private notes and blocks; any type
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
  be handed over by hand.
- **They live in the vault but outside git:** `projects/<course>/docs/`,
  synced between the machines, ignored by the hourly commit (they can be
  downloaded again from the portal). A project's page in the sidebar lists
  them and opens them in the PDF viewer.
- **The agent reads them in three tiers** (progressive disclosure, as agent
  skills load):
  1. *Index* — on a run about a course: title, date, pages of that course's
     documents. A line each; nothing read.
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
  subscription (OpenAI's own tool; opencode's ChatGPT login exists on this
  machine but its token expired on 2026-07-17 and needs a re-login); the
  OpenAI and Anthropic APIs, metered, the cleanest (no tools unless given);
  `claude -p` (Claude Code) on the Claude subscription, only once the
  student is comfortable with Anthropic's terms for it — Anthropic reportedly
  stopped subscription logins in third-party tools in 2026.
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
   view (`NotebookSheet.qml`, Ctrl+K from Settings) lists each of the agent's
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
   proposals, PDFs of the last 60 days only; a match is a ◇ row in its
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
   set in Settings → what the agent may do (Ctrl+M; ←→): at "do it and
   tell me" the page does it when it arrives and shows a "done: …" row —
   Space lets it stand, Del undoes it (a deadline's box is cancelled, not
   erased, as any deadline is); "looks done" stays a question, since
   ticking is the person's act. The inbox follows the same setting: filed
   at once and told, or never scanned. Tests: `tests/test_actions.py`,
   and the dashboard and Settings sections of `tests/page/run.py`.

The pluggable runner stands apart from the slices: it can come whenever a
second route is wanted — first `codex exec` and the OpenAI API, once the
ChatGPT login is renewed.
