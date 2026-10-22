# What Longhand can do, and how

<!-- The agent's manual (2026-10-18): what it is given when the student asks
     how to do something in Longhand. Written by hand from the README and
     docs/; {key:<id>} is filled in with the student's own keys from
     plugin-page/Shortcuts.js and keys.json when a payload is built, so a key
     the student moved reads as theirs. Keep it short and true: a feature not
     here does not exist as far as the agent knows. -->

## The page

Longhand is a daily note in the Omarchy shell: today's note as a blank sheet,
saved on every keystroke, plain markdown in the vault where Obsidian keeps
its daily notes. {key:sys:page} opens it from anywhere (or the bar's glyph);
{key:close} closes it. {key:sys:alongside} opens the same sheet as a window to
tile beside something; {key:pin} flips between the two. {key:zoomIn},
{key:zoomOut}, {key:zoomReset} zoom. {key:find} finds in the note.
{key:today} goes to today's note; {key:dayPrev} and {key:dayNext} step to
the day before or after that has a note.

## Writing

Typing `# `, `- [ ] ` or `> ` turns the line into a heading, a checkbox or a
quote; Backspace at its start turns it back. {key:bold}, {key:italic},
{key:code} and {key:strike} wrap the selection or the word the cursor is
in. {key:checkbox} ticks or unticks a checkbox (a click works too); a tick
writes the day it was done (`✅`) and makes a short sound, which Settings can
turn off. {key:lineUp} and {key:lineDown} move lines. Tab nests a line,
Shift+Tab un-nests it, and so does Enter on an empty nested item (at the
outermost level Enter leaves the list); Shift+Enter is a new line in the same block.

## Deadlines

A checkbox with a date at its end is a deadline: `- [ ] essay draft #intsem
due fri 17:00` (also `by monday`, `until 20 oct`, `📅 tomorrow`). The date
lights up as it is typed and becomes the deadline when the cursor leaves
the line — nothing is asked. To keep the date as words: Backspace as it
lights up, or {key:deadline} on the line. {key:deadline} also binds a line
on purpose, asks "when?" on a line with no date, and on a bound line
reschedules it (empty unbinds). The line is the task: its words are the
title, its `#tag` (or the tagged heading above it) the project; a tick or a
date changed anywhere reaches everywhere. Deleting the line cancels the
deadline, and Ctrl+Z brings it back. The bar's deadline popup
({key:sys:deadlines}) is the glance.

## Do-dates and priorities

A do-date (`⏳`) is the day to work on a box, not the day it is due; a
priority is `⏫` high, `🔼` medium, `🔽` low. Both are set from the
dashboard ({key:dashWhen} asks "when?" in words, {key:dashPriority} cycles
the priority) or written on the line.

## Projects and courses

A project is a course or anything worked towards, with a `#tag`. A heading
`# Course #tag` claims everything under it until the next heading of the
same or a higher level. Typing `@` lists the projects: Enter writes its
`#tag`, Shift+Enter starts the class with its `# Course #tag` heading. The
sidebar ({key:sidebar}) shows a month calendar, the day's deadlines and the
projects with their next session; a project opens its notes from every day,
newest first, and its documents.

To make a project: type `@` or `#` and its new tag in the note — when
nothing matches, the list offers "+ make #tag a project" (after `#`, press
{key:mentionDown} first, so Enter is still a new line) and asks its name;
or "+ new project" at the foot of the sidebar's projects, typing its name
and, if it should not be the name's words, its `#tag`. A project's name
and tag stay as made; the agent never makes one, only proposes it.

## The dashboard

{key:dashboard} turns the sheet into the dashboard: every open checkbox and
deadline across all the notes, grouped by what they ask (due, doing, to
schedule) and by course. {key:dashOpen} goes to the line; {key:dashDone}
ticks it; {key:dashWhen} reschedules it; {key:dashPriority} cycles its
priority; {key:dashRename} renames it; {key:dashDrop} cancels it (the line
stays, as cancelled); {key:dashShelve} puts it aside for now; {key:dashKeep}
keeps it when it has gone quiet; {key:dashGrade} grades a deadline;
{key:dashUndo} takes the last tick back. A box left untouched goes quiet
after a while instead of nagging. The agent's proposals and questions are
rows here too: {key:dashDone} accepts, {key:dashDrop} declines;
{key:dashPlan} asks it to plan now. {key:dashOpen} on a proposal, a
question, or something it did on its own opens the margin beside the
dashboard, to talk with the planner about it: why that day, what you would
rather, or your own answer to its question. It can change its proposal, and
when the two of you agree, that settles it. {key:dashTalk} on any task's
row summons the agent to think the task through, in the same margin. Each
task keeps one conversation — what was said in the margin of its note and
with the planner, shown together — shared by the boxes under it.

## The day's conversation

{key:day} opens the day's conversation in the right pane, from anywhere in
the page — talk to the day, not one line: the tasks, the courses, what was
written. In the note, {key:dayHere} opens it pointing at the block the
cursor is in. The seal at the centre of the header opens and closes it; the
date at the left opens the sidebar. One conversation a day: the morning's
observation waits at the top, it sees today's other conversations, and a
past day's note shows that day's conversation, read-only — talking happens
in today's. A private day still has it, seeing nothing of the note. It can
search your files — the folders switched on in Settings → what the agent
may search ({key:settingsSearch} in Settings) — and cites where it found
things as links that open the note at that line. Never private notes or
blocks, `_Secrets`, or documents of identity, money, health, contracts or
secrets. Typing `@` in its box lists the note's blocks; Enter points the
next message at one. When the conversation comes to a change in the tasks
(a day for a box, a deadline, a priority, steps, dropping a box, "looks
done"), it proposes it as a card under its answer — the same item as the
dashboard's row, under the same "what the agent may do" levels.
{key:marginUp} from the empty box goes onto the cards; {key:marginAccept}
does what one says, {key:marginDecline} declines it. Under each answer,
"helpful" and "not helpful" say whether it was ({key:dayHelpful} and
{key:dayNotHelpful} on the last one; again takes it back). The morning after, it
writes what the day's conversation came to — a few lines, the day's brief
— into what the agent knows, where each line can be corrected or
forgotten like any other; the next days read the last three. A private day
gets no brief.

## The agent

The agent answers in the margin, beside the note. Nothing interrupts the
writing to offer it: {key:ask} sends the block the cursor is in (a
checkbox, an `@` line or a line ending in `?` are the usual signs), or
opens the conversation on a block that has a reply; {key:margin} goes into
the margin, where `+` and `-` say whether a reply helped. It plans the next
two weeks when the page or the dashboard opens: do-dates, and with the
student's leave, deadlines found in the writing, priorities, steps under a
box, dropping a stale box, "this looks done — tick it?". Every kind starts
at "ask me"; Settings → what the agent may do ({key:settingsAutonomy}) sets
each to ask me, do it and tell me, or never. What it learns is in Settings →
what the agent knows ({key:settingsNotebook}), each line correctable or
forgettable. It never writes the student's prose.

## Private

{key:private}, or **private** in the header, makes the whole note unseen by
the agent (`agent: false`). A `> [!private]` callout hides one block.

## Settings

{key:settings} opens Settings: calendars (paste an `.ics` or `webcal://`
address; for each, the agent sees its classes only or everything in it),
the agent (what it knows, what it may do, its eval checks and weekly
review), and the tick's sound.

## Documents

With `inbox` set in the config, PDFs in Downloads that belong to a course
(named for it, or downloaded during one of its classes) are proposed in the
dashboard for filing into the course's documents; nothing else in the
folder is ever listed. A course's documents are in its project in the
sidebar; the agent sees their titles and can ask to read one.

## Keys

Every key can be moved: {key:keys} opens the list of keys; Enter on a row,
then the new key.

## The timer

`pomo` is the focus timer: {key:sys:pomoToggle} starts or pauses it,
{key:sys:pomoSkip} skips, {key:sys:pomoPopup} shows the popup. From a terminal:
`pomo start [focus|break|up] [minutes]`, and `pomo deadline add <title>
<when>` adds a deadline without a note.
