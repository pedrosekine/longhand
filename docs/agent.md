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
- **Enter** goes to the line it concerns; on a question, it lets the person
  write their own answer.
- A proposed do-date is a **◇ row under its task**, not a pill on the task's
  row, so Space on the task still ticks the task.
- New boxes and deadlines are ◇ rows in the band they would belong to.

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
  PDFs that name a course by its code or title and proposes filing them
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
- **Start planning on the model there is**, so the acceptance rate shows
  whether quality is the limit; switch planning to a stronger route if the
  student declines most of what it proposes.

## Slices, in order

Each is usable alone.

1. **Who made it** — authorship in the layer, kept through every edit in the
   page; the three marks in the note and the dashboard. Everything else
   rests on it, and it shares its machinery with keeping a sent block's
   conversation through word edits (plan item 6).
2. **Proposals and planning** — the ledger; the planning job with the
   arithmetic done locally; action 1 (do-dates) at "ask me"; questions with
   recommended answers; the rows and keys; the count in the bar; acceptance
   in `stats`.
3. **The notebook, visible** — Settings → "What the agent knows", correct
   and forget, `corrections.md`.
4. **Documents** — the Downloads inbox and filing, the index, conversion
   and search, the project's documents in the sidebar.
5. **The other actions** (2–7) and raising an action's autonomy.

The pluggable runner stands apart from the slices: it can come whenever a
second route is wanted — first `codex exec` and the OpenAI API, once the
ChatGPT login is renewed.
