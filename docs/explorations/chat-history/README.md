# The day's chat and its earlier days — 2026-11-21

The "everything" view put fourteen earlier days above today's chat, a line
each, as "Tue 17 Nov · 5 subjects · 48 turns". They were opened four times in
three days, and the student could not say what they were for. What the
grilling of 2026-11-18 agreed was "one conversation, continuous, with a divider
between days" (`docs/agent.md`).

- `mock.html` (`?v=now|a|b|c`) and `compare.png` (from `compare.html`): the
  pane on an empty day, as it is now and in three designs. A is one chat that
  scrolls up into the days before. B keeps only today. C names each day's
  subjects and shows only the last three days. The tasks, papers and words are
  made up; the counts in "now" are the real pane's.

A was chosen and built the same day, with a plain rule (no words on it for
now) and the agent able to look back itself (`recall`); see `docs/agent.md`,
"The days before, one chat", and `docs/plan.md` item 26.

`real-built.png`: the page as built, from `tests/page/shots.py --scene one`
(the test vault, made up): yesterday under its rule, its paper and task chats
a line each, its own exchange whole, then today.

## A new day that starts blank — 2026-11-21, later

Built, A opened "too busy for a new day": pinned to the foot, a new day's pane
is filled by the days before. `blank.html` (`?v=now|a|a-up|b|c`) and
`compare-blank.png` (from `compare-blank.html`): as built; A, opened at
today's rule with the days before above, out of sight, and the same pane
scrolled up a little; B, blank with one faint "↑ Fri 20 Nov and earlier"
line; C, blank with yesterday's last words faded under the head.

A was chosen and built, and today's whole chat lost its header.
`real-blank.png`: the page as built, a new day opened (test vault, made up).
