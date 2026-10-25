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
| **left**: the sidebar | the calendar, the day's deadlines, the projects | `Ctrl+[` |
| **center**: the middle | the note, or in its place the dashboard, the keys or settings | `Ctrl+\` |
| **right**: the agent's pane | the day's conversation (its home), a block's conversation beside the note, a task's beside the dashboard | `Ctrl+]` |

The keyboard is always in exactly one pane. When it is in a side pane, the
**focus frame** (an outline in the theme's accent, like Omarchy's active
border) is drawn on that pane's own edges, over its hairline, and slides to
the other side pane as the keys move. The middle never gets a frame
(2026-10-24): there the note's blinking cursor, or the dashboard's lit row,
already says where the keys are. So no frame on screen means the keys are in
the middle. Only the pane with the keys draws its selection (the row, the day, the
card), so one place is lit at a time; the one exception is the dashboard row
being talked about beside it, which stays faintly marked.

## Moving

- **A pane's key** (the brackets) takes you to it, opening it if it is
  closed. Pressed while you are in it, it closes it. The middle has nothing to
  close, so there `Ctrl+\` flips the note and the dashboard (a keys or
  settings sheet in its place closes instead).
- **`Alt+←` / `Alt+→`** move to the next open pane that way, as Super+arrows
  move between Hyprland's windows. They never close anything, and open one
  thing only: `Alt+→` in the note with nothing to its right opens the
  block's own conversation, without sending anything, as it did before the
  panes (brought back 2026-10-25: it was missed). Anywhere else, at the
  edge a hint says which key would open a pane there.
- **A click** in a pane puts the keys there too.
- `Ctrl+T` (the dashboard), `Ctrl+J` (the agent's pane) and `Ctrl+Shift+B`
  (the sidebar) still work, as second keys.

Moving between panes never closes one. What replaces what is fixed: the
middle shows one thing at a time (the note, the dashboard, keys or settings),
and the agent's pane shows one room at a time. A block's conversation belongs
to the note, and a task's belongs to the dashboard, so each comes back when
its view does. The day's conversation goes with either. The sidebar is
independent of both.

## Where the panes sit

One rule for both sides and both shapes (`plugin-page/Layout.js`, 2026-10-24):
the side panes stand **against the window's edges**, the sidebar at the left
and the agent's pane at the right, like an app's sidebars, so there is no dead
strip outside them. The overlay keeps its usual margin from the screen's
edge. The note stays centred in the window, and a pane opening **does not
move it** as long as the note fits between the panes. Only when it does not
does the note step aside, as far as it has to (a slide, at the focus frame's
pace), and it narrows last. Beside the dashboard, keys or settings, which are
lists and take the room they are given, the list slides over for the sidebar.
In the window shape, a hairline marks each pane's inner edge.

Before 2026-10-24 the window recentred the note in the room the sidebar left,
so the sidebar pushed the note and the right pane did not, and the overlay
shrank the right pane instead. For a few hours after that the panes hugged the
note's edges, which left dead space between each pane and the window's edge
on a wide screen.

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
on**: the zoom, the keys sheet, settings, the five pane keys, the dashboard,
home (`Ctrl+H`: today's note in the middle with the keys in it, the side
panes left open) and the page's shape (F11). Global keys are read first by every place's
handler (`anywhereKey`), including the boxes you type in, so none of them may
be a key a text field types or uses. That is why they all carry Ctrl or Alt,
or are F-keys.

Everything else is local to its place: writing and moving in the note, a
list's letters on the dashboard, the calendar's arrows. A local key may mean
different things in different places (Enter, Ctrl+E), but only one thing in
each, and the keys sheet lists each place's keys under it.

Days moved off the brackets for this: the day before and after are now
`Alt+[` / `Alt+]` (and `Ctrl+PgUp` / `Ctrl+PgDn` as before). Talking about a
dashboard row is `Ctrl+Shift+Enter`, the same key that talks about a block
in the note.

## The pointer follows the keys

Hyprland moves the pointer to the window you move to, so a click never lands
somewhere you did not expect. The page does the same inside itself: when the
keys change pane, the pointer moves into that pane, onto what is selected
there (beside the cursor in the note, the row on the dashboard, the day in
the calendar, the box you type in). With **every selection** (the default),
it also follows each row the keys move to in a list.

It never moves while your hand is on the mouse (moved in the last moment),
never while you type in the note, never when it is already on the thing, and
only while the page's window is the active one. It uses Hyprland
(`hl.dsp.cursor.move`). Settings → The pointer (`Ctrl+Shift+M` there) has
*every selection*, *pane changes only* or *off*, kept as `pointer` in
`settings.json`.

## Not yet

- Several sheets still read raw keys that cannot be moved in the keys sheet
  (Esc/Enter/arrows in keys, settings, the notebook, the agent's permissions
  and the search folders; Enter/Esc in the "when?" and name boxes).
  They behave by the Esc rule above but are not listed per place.
- The test window never has the keyboard, so `tests/page/run.py` checks which
  panes open and close. Where the keys land, and the frame and the pointer,
  are checked in the live page.
