# Navigation: where the keys are, and how they move

_Decided 2026-10-23. The keys themselves are in [keys.md](keys.md), generated
from `plugin-page/Shortcuts.js`; the code is "panes" in `plugin-page/Page.qml`._

Before this, every pane decided on its own where the keys went when it
closed (almost always the note, even when the note was hidden behind the
dashboard), Esc meant something different in each place, Alt+→ opened the
margin in the note but moved focus in the sidebar, and nothing on screen
said which pane had the keyboard. This is the model that replaces it,
borrowed from how Hyprland and Omarchy treat windows.

## Three panes

The page is at most three panes side by side:

| Pane | What it shows | Its key |
|---|---|---|
| **left**: the sidebar | its space: Time (the calendar, the day's deadlines, the projects) or Files ([files.md](files.md)) | `Ctrl+1` |
| **center**: the middle | the note, or in its place the dashboard, the keys or settings | `Ctrl+2` |
| **right**: the agent's pane | the day's chat (its home), a block's chat beside the note, a task's beside the dashboard | `Ctrl+3` |

The digits since 2026-10-27 ([keys-proposal.md](keys-proposal.md)); the
brackets `Ctrl+[` `Ctrl+\` `Ctrl+]` before, which need AltGr on many
layouts.

The keyboard is always in exactly one pane. When it is in a side pane, the
**focus frame** (Omarchy's active border: the theme's own gradient for it,
read from its `hyprland.lua`, or its accent when it gives none) is drawn on
that pane's own edges, over its hairline. Each side pane
has its own, as each window has its border in Hyprland: when the keys move,
the one they leave fades out while the one they come to fades in, at
Hyprland's own pace (Omarchy's `border` animation, about half a second,
easing out). Nothing travels across the note (until 2026-10-25 one frame
slid from pane to pane). The middle never gets a frame
(2026-10-24): there the note's blinking cursor, or the dashboard's lit row,
already says where the keys are. So no frame on screen means the keys are in
the middle. Only the pane with the keys draws its selection (the row, the day, the
card), so one place is lit at a time; the one exception is the dashboard row
being talked about beside it, which stays faintly marked.

**Selecting never moves anything** (2026-11-13). Lighting a row, a day or a
card changes its fill and may show a key beside it, but never its size nor
the size or place of anything around it: what a row shows is decided by what
it holds, not by whether the keys are on it. So a key a selection offers is
drawn outside the row (the dashboard's chat key stands in the left gutter),
and a line a row has, such as its chat's last word, is there whether or not
it is selected. Keys named while Ctrl is held float over the rows for the same
reason.

## Moving

- **A pane's number** takes you to it, opening it if it is closed. Pressed
  while you are in it, the pane switches between its two things: the sidebar
  between Time and Files, the middle between the note and the dashboard (a
  keys or settings sheet in its place closes instead), the agent's pane
  between the day's chat and the chat of what the middle has selected (the
  cursor's block beside the note, the row beside the dashboard). A side pane
  opened by its number opens as it was left: the sidebar on its space, the
  agent's pane on the day's chat.
- **`Ctrl+Alt+2`** goes straight to the dashboard from anywhere, closing a
  keys or settings sheet over the middle; pressed on the dashboard it stays,
  so it never needs a look first (2026-10-30, Craft's modifier-and-digit
  views; `Ctrl+T` stays free for tabs).
- **`Ctrl+\`** opens or closes the sidebar and **`Ctrl+|`** (Ctrl+Shift+\)
  the agent's pane, wherever the keys are: Notion's and Craft's key for the
  sidebar, and its Shift for the other side, as VS Code pairs its two.
  Hovering over the date or the seal names both of a pane's keys.
- **`Alt+←` / `Alt+→`** move to the next open pane that way, as Super+arrows
  move between Hyprland's windows. They never close anything, and open one
  thing only: `Alt+→` in the note with nothing to its right opens the
  block's own conversation, without sending anything, as it did before the
  panes (brought back 2026-10-25: it was missed). Anywhere else, at the
  edge a hint says which key would open a pane there.
- **A click** in a pane puts the keys there too.
- `Ctrl+T`, `Ctrl+J`, `Ctrl+Shift+B` and `Ctrl+{`/`Ctrl+}` went with the
  brackets on 2026-10-27: the digits and the two toggles say it all.

Moving between panes never closes one. What replaces what is fixed: the
middle shows one thing at a time (the note, the dashboard, keys or settings),
and the agent's pane shows one room at a time. A block's conversation belongs
to the note, and a task's belongs to the dashboard, so each comes back when
its view does. The day's conversation goes with either. The sidebar is
independent of both.

**When the middle moves to something else** (a paper, a note, a day, back
or on; the student's rule, 2026-11-22), the agent's pane:

- **never opens by itself:** closed, it stays closed;
- **open, follows the middle:** a paper gets the paper's chat, a note from
  Files the note's, a day the day's chat;
- **has the day's chat beside what the agent may not be given:** a private
  PDF or note, a PDF with no words; never a chat of its own;
- **stays where it is while its box holds words not sent:** nothing is
  switched under the hand. A paper's or note's chat stays that paper's or
  note's until the middle comes back to it or moves again with the box
  empty;
- **changes nothing when the middle goes where it already is** (`Ctrl+[`
  back to the paper on screen, a link to it).

Following never takes the keys: they go where the move puts them (the
middle, for a link, a day or back), and stay in the pane only when it turns
with them in it. Before,
opening a paper or a file closed the pane, even the day's chat, so `Ctrl+[`
typed in a paper's chat could close it.

## Where the panes sit

One rule for both sides, both shapes and everything that can stand in the
middle (`plugin-page/Layout.js`, 2026-11-25): the side panes stand
**against the window's edges**, the sidebar at the left and the agent's pane
at the right, like an app's sidebars, so there is no dead strip outside
them. The overlay keeps its usual margin from the screen's edge. What is in
the middle is **centred in the room the panes leave** between them:

- **the note and a paper:** their own width (the measure, or a paper's
  wider column), centred in that room. A pane opening slides them by half
  its width (at the focus frame's pace), so the space either side of the
  note stays even. Only a room narrower than the note narrows it. While the
  agent's pane's edge is dragged, the note follows it without the slide;
- **the dashboard:** takes the room after the sidebar and, while a talk or
  the day's chat is beside it, after that pane too. Its list is centred in
  what is left;
- **keys and settings:** take the room after the sidebar (the agent's pane is
  hidden while they are open), their column centred in it.

In the window shape, a hairline marks each pane's inner edge.

Before 2026-11-25 the note was centred in the **window** and did not move
when a pane opened while it still fitted (2026-10-24). The dashboard and the
lists were already centred in the room, so the note was the one thing that
did not follow the rule. With the agent's pane open on a wide screen, the
note sat close against the chat with a wide empty strip on its other side.
It looked off-centre, and the eye had to cross the empty strip to read
(the student, 2026-11-25). Before 2026-10-24 the window recentred the note
in the room the sidebar left, so the sidebar pushed the note and the right
pane did not, and the overlay shrank the right pane instead. For a few hours
after that the panes hugged the note's edges, which left dead space between
each pane and the window's edge on a wide screen.

### The agent's pane, sized by hand (2026-11-22)

Designed with the student in a grilling (`docs/explorations/chat-width/`,
its README holds every decision and the benchmark). The pane's width is no
longer only what the note leaves:

- **Three ways, all kept.** Drag its edge (it lights, the pointer turns, a
  label gives the width while dragging; a double click puts the split back
  where it starts). **Alt+Shift+← / →** nudge it about 100 px, as Omarchy's
  Super+−/= do a window. **Alt+Z** flips between two remembered splits:
  *reading* (the middle wide; at first today's width) and *discussing* (the
  chat wide; at first the middle at its least). A drag or a nudge moves the
  split you are in. Nothing changes place: only the edge moves.
- **The middle's least.** A paper is never narrowed by a key past the
  column where its body text is still about 11 px (`Layout.paperFloor`,
  from the words' usual height that `longhand-read` gives with the span);
  a drag may go under it, down to 360 px, and the hint says the text is
  small. A note's least is today's 340 px: prose rewraps.
- **The chat's most** is what it can use: its measure (580 px) and, beside
  a paper, the rail of quoted words. Past it the room stays with the
  middle; answers never run wider than the measure.
- **One at a time.** When the middle's least and the pane's 300 px do not
  fit side by side (a paper on half the laptop's screen), the side shown
  follows the keys: in the pane, the chat over the middle, the middle's name
  and Alt+Z in a strip at its left; elsewhere, the middle, the chat in a
  strip at the window's edge, a dot on it once an answer came.
- **Kept per screen width** (`pane-widths.json` in the state folder), and
  beside a paper apart from beside a note, so the laptop and the big screen
  each keep their own.
- **Seen in the header:** a small glyph of the split (the chat's share
  filled, moving with the edge) and the word *reading* or *discussing*; a
  click flips, hovering names the three ways, the hint under the box names
  Alt+Z. Beside the dashboard the pane keeps its own width.

## Esc: back out one level

Esc always undoes the last step in. In order:

1. a box or list opened inside a pane closes (find, "when?", an `@` list, a
   selection in the note, a list in the sidebar back to the calendar, a
   project back to the projects, a settings sub-view back to settings);
2. in the agent's pane, a block's or a task's conversation goes back to the
   day's, if that is open (the pane's home);
3. otherwise the pane you are in closes: the sidebar, the agent's pane, the
   dashboard, keys, settings;
4. in the note itself, the overlay closes. The window shape stays, since it
   is tiled beside your work.

## Back and forward: one history

`Ctrl+[` / `Ctrl+]` (Notion's and Craft's) and `Ctrl+Alt+←` / `Ctrl+Alt+→`
(Obsidian's) go back and on through what the middle showed (2026-10-28,
[keys-proposal.md](keys-proposal.md); links only before): a link followed,
the note ↔ the dashboard, a day before or after, a file or a PDF opened.
Going back lands where the cursor was. Opening or closing a side pane is not
a step, and a move made of several (the dashboard closing to go to a line on
another day) is one step, as it was before it began.

## Checkpoints: coming back lands where you left

Each pane keeps where its keys were: the note its cursor (and selection),
the dashboard its row, the calendar its day, the margin the box or the card.
Going back to a pane lands there.

When a pane closes with the keys in it, the keys go back to **the pane they
came from**, at its checkpoint. If you were in the middle of a line, opened a
block's conversation and pressed Esc, the cursor is back in that line, at
the letter where it was. Opening the keys from the agent's pane and closing
them returns you to the agent's pane. The page remembers this per pane
(`openedFrom`). If the pane you came from has closed since, the keys go to the
middle.

## Which keys are global

A key is global ("everywhere", the `any` place in `Shortcuts.js`) when it is
**about the page itself or where you are in it, never about the thing you are
on**: the zoom, the keys sheet, settings, the pane keys (the three digits
and the two toggles), the day's chat, home (`Ctrl+H`: today's note in the middle with the keys in it, the side
panes left open) and the page's shape (F11). Global keys are read first by every place's
handler (`anywhereKey`), including the boxes you type in, so none of them may
be a key a text field types or uses. That is why they all carry Ctrl or Alt,
or are F-keys.

Everything else is local to its place: writing and moving in the note, a
list's letters on the dashboard, the calendar's arrows. A local key may mean
different things in different places (Enter, Ctrl+E), but only one thing in
each, and the keys sheet lists each place's keys under it.

Days moved off the brackets for the panes (2026-10-23): the day before and after are now
`Alt+[` / `Alt+]` (and `Ctrl+PgUp` / `Ctrl+PgDn` as before). A chat has one
key since 2026-10-27 ([keys-proposal.md](keys-proposal.md)): `Ctrl+Enter`
opens this block's or this row's chat (`C` on the dashboard too), and
`Ctrl+Shift+Enter` the whole's, the day's chat from anywhere (in a note from
Files, that note's).

## The pointer follows the keys

Hyprland moves the pointer to the window you move to, so a click never lands
somewhere you did not expect. The page does the same inside itself: when the
keys change pane, the pointer moves into that pane, onto what is selected
there (beside the cursor in the note, the row on the dashboard, the day in
the calendar, the box you type in). That is **pane changes only**, the
default since 2026-11-20; with **every selection** (the default until then)
it also follows each row the keys move to in a list.

It never moves while your hand is on the mouse (moved in the last moment),
never while you type in the note, never when it is already on the thing, and
only while the page's window is the active one. It uses Hyprland
(`hl.dsp.cursor.move`). Settings → The pointer (picked with ↑↓, changed with
Enter or Space, since settings became a list on 2026-10-28) has
*every selection*, *pane changes only* or *off*, kept as `pointer` in
`settings.json`.

Hover hints follow the hand the other way round (2026-10-30,
[hints.md](hints.md)): a key puts them away until your hand moves the
mouse, so a row the pointer is warped onto never opens its hint.

## Not yet

- Several sheets still read raw keys that cannot be moved in the keys sheet
  (Esc/Enter/arrows in keys, settings, the notebook, the agent's permissions
  and the search folders; Enter/Esc in the "when?" and name boxes).
  They behave by the Esc rule above but are not listed per place.
- The test window never has the keyboard, but the page's own focus is real
  in it, so `tests/page/run.py` checks which panes open and close and where
  the keys land (`here`: Alt+←/→, the bracket keys, a sheet giving the keys
  back to the pane it was opened from, the note's cursor back at its letter,
  the middle when the pane they came from has closed, the calendar's keys).
  The frame and the pointer are checked in the live page. The overlay takes
  the screen and the keyboard, so its checks run only with `--overlay`.
