# Keys

<!-- Written by tools/keys_guide.py from plugin-page/Shortcuts.js and
     plugin-page/hyprkeys.py. Do not edit: change the keys there and run it. -->

Every key the page answers to, as it starts. Any of them can be moved in the page: `Ctrl+/` (or **keys** at the foot of the sidebar) opens the same list, Enter on a row and the new key moves it. The keys you move are kept in `~/.config/longhand/keys.json`; `python3 tools/keys_guide.py --mine` prints this guide with them.

Where a row has two keys, either works: the second is usually the one another app taught (Notion, Todoist, vim) or one a laptop reaches without Fn.

The keys that work **everywhere** (in a box you are typing in too) are the ones about the page itself and where you are in it: the zoom, these lists, the three panes and the page's shape. The panes are the digits, left to right: `Ctrl+1` the sidebar, `Ctrl+2` the middle, `Ctrl+3` the agent's pane; `Ctrl+\` and `Ctrl+|` open and close the side ones. How focus moves between them is in [navigation.md](navigation.md).

## The page

| | Keys | Works |
|---|---|---|
| Zoom in | `Ctrl+=` · `Ctrl++` | everywhere |
| Zoom out | `Ctrl+-` · `Ctrl+_` | everywhere |
| Zoom back to 100% | `Ctrl+0` | everywhere |
| Show these keys | `Ctrl+/` | everywhere |
| Settings (calendars, sound) | `Ctrl+,` | everywhere |
| The sidebar: go there, opening it; in it, Time ↔ Files | `Ctrl+1` | everywhere |
| The middle: go there; in it, the note ↔ the dashboard | `Ctrl+2` | everywhere |
| The agent's pane: go there, opening it; in it, the day's chat ↔ this block's or task's | `Ctrl+3` | everywhere |
| The sidebar: open or close | `Ctrl+\` | everywhere |
| The agent's pane: open (on the day's chat) or close | `Ctrl+|` | everywhere |
| The open pane to the left | `Alt+←` | everywhere |
| The open pane to the right (in the note, with none: this block's chat) | `Alt+→` | everywhere |
| Flip between overlay and window | `F11` · `Ctrl+Alt+P` | everywhere |
| Close the overlay | `Esc` | in the note |
| Make the whole note private (the agent sees nothing) | `Ctrl+Shift+P` | in the note |
| Make the block private, or the blocks selected (again: not private) | `Ctrl+P` | in the note |

## Writing

| | Keys | Works |
|---|---|---|
| Bold | `Ctrl+B` | in the note |
| Italic | `Ctrl+I` | in the note |
| Inline code | `` Ctrl+` `` · `Ctrl+E` | in the note |
| Strikethrough | `Ctrl+Shift+S` | in the note |
| Tick or untick a checkbox | `Ctrl+L` | in the note |
| Bind a checkbox's date, reschedule or unbind it | `Ctrl+D` | in the note |
| Make the lit date the deadline and go on writing the line | `Tab` | while a box's date lights up as it is typed |
| Move the line (or the lines selected) up | `Alt+↑` | in the note |
| Move the line (or the lines selected) down | `Alt+↓` | in the note |
| Undo | `Ctrl+Z` | in the note |
| Redo | `Ctrl+Shift+Z` · `Ctrl+Y` | in the note |

## Moving through the note

| | Keys | Works |
|---|---|---|
| Start of the block (again: the block before) | `Ctrl+↑` | in the note |
| End of the block (again: the block after) | `Ctrl+↓` | in the note |
| Select to the block's start (again: a block more) | `Ctrl+Shift+↑` | in the note |
| Select to the block's end (again: a block more) | `Ctrl+Shift+↓` | in the note |
| Top of the note | `Ctrl+Home` | in the note |
| End of the note | `Ctrl+End` | in the note |
| Home: today's note, the keys in it (the side panes stay open) | `Ctrl+H` · `Alt+Home` | everywhere |
| The day before, with a note | `Alt+[` · `Ctrl+PgUp` | in the note, in the dashboard |
| The day after, with a note (and then today) | `Alt+]` · `Ctrl+PgDn` | in the note, in the dashboard |
| Find in the note (in find: select the words) | `Ctrl+F` | in the note, in find |
| Follow the link the cursor is in | `Alt+Enter` | in the note |
| Back to where a link was followed from | `Ctrl+Alt+←` | everywhere |
| On again, after going back | `Ctrl+Alt+→` | everywhere |

## The agent

| | Keys | Works |
|---|---|---|
| Chat about this block (with a sign for the agent: it answers first) | `Ctrl+Enter` | in the note |
| The day's chat (in a note from Files: the note's) | `Ctrl+Shift+Enter` | everywhere |
| In the day's chat: its last answer was helpful (again: take it back) | `Alt+=` | in the chat's box |
| In the day's chat: its last answer was not helpful (again: take it back) | `Alt+-` | in the chat's box |

## @ a project

| | Keys | Works |
|---|---|---|
| Previous project | `↑` | while @ or # lists tags, or @ blocks in the day's box |
| Next project | `↓` | while @ or # lists tags, or @ blocks in the day's box |
| Write its #tag | `Enter` · `Tab` | while @ or # lists tags, or @ blocks in the day's box |
| Start the class (# Course #tag) | `Shift+Enter` | while @ or # lists tags, or @ blocks in the day's box |
| Close the list | `Esc` | while @ or # lists tags, or @ blocks in the day's box |

## Find

| | Keys | Works |
|---|---|---|
| Next match | `Enter` | in find |
| Previous match | `Shift+Enter` | in find |
| Go to the match and close find | `Ctrl+Enter` | in find |
| Close find, on the match | `Esc` | in find |
| Close find, back where you were | `Shift+Esc` | in find |

## Dashboard

| | Keys | Works |
|---|---|---|
| Move up | `↑` · `k` | in the dashboard |
| Move down | `↓` · `j` | in the dashboard |
| First row | `Home` | in the dashboard |
| Last row | `End` | in the dashboard |
| Go to the line; on what the agent proposes, asks or did, its chat (the margin opens beside) | `Enter` | in the dashboard |
| Done (again: not done); on the agent's proposal, accept | `Space` · `e` · `Ctrl+L` | in the dashboard |
| When: reschedule it | `t` · `Ctrl+D` | in the dashboard |
| Cycle its priority | `p` | in the dashboard |
| Rename it (its line's words) | `Ctrl+E` | in the dashboard |
| Cancel it (the line stays, as cancelled); on the agent's proposal, decline | `Del` · `Backspace` | in the dashboard |
| Not now: put it aside (again: back) | `s` | in the dashboard |
| Keep it: its clock starts again | `r` | in the dashboard |
| Grade a deadline | `g` | in the dashboard |
| Ask the agent to plan now | `Ctrl+R` | in the dashboard |
| Next thing from the agent to settle (round again at the end) | `n` | in the dashboard |
| The one before it | `Shift+N` | in the dashboard |
| Chat about it (the agent's pane opens on it) | `c` · `Ctrl+Enter` | in the dashboard |
| Take the last tick back | `Ctrl+Z` | in the dashboard |
| Back to the note | `Esc` | in the dashboard |

## Calendar

| | Keys | Works |
|---|---|---|
| Previous day | `←` | in the calendar |
| Next day | `→` | in the calendar |
| A week back | `↑` | in the calendar |
| A week on | `↓` | in the calendar |
| A month back | `Ctrl+←` · `PgUp` | in the calendar |
| A month on | `Ctrl+→` · `PgDn` | in the calendar |
| Today | `Home` · `t` | in the calendar |
| Open the day in the sheet | `Enter` | in the calendar |
| On to the day's deadlines and the projects | `Tab` | in the calendar |
| Close the sidebar (back where you were) | `Esc` | in the calendar |

## Deadlines, projects and sections in the sidebar

| | Keys | Works |
|---|---|---|
| Move up | `↑` · `k` | in the sidebar's lists |
| Move down | `↓` · `j` | in the sidebar's lists |
| Open it (a deadline: go to its line) | `Enter` | in the sidebar's lists |
| A deadline: done (again: not done) | `Ctrl+L` | in the sidebar's lists |
| Into a project's notes | `→` | in the sidebar's lists |
| A project: start its class in the note | `Shift+Enter` | in the sidebar's lists |
| A project: put its #tag at the cursor | `Ctrl+Enter` | in the sidebar's lists |
| On to the next list | `Tab` | in the sidebar's lists |
| Back out of the list | `Esc` · `Shift+Tab` · `←` | in the sidebar's lists |

## Files in the sidebar

| | Keys | Works |
|---|---|---|
| Move up | `↑` · `k` | in the files |
| Move down | `↓` · `j` | in the files |
| Open the file in the sheet (a folder: open or fold it) | `Enter` | in the files |
| Open the folder (open: into it) | `→` · `l` | in the files |
| Fold the folder (folded: up to the one it is in) | `←` · `h` | in the files |
| Filter by name | `/` | in the files |
| Clear the filter; else close the sidebar | `Esc` | in the files |

## A PDF

| | Keys | Works |
|---|---|---|
| Scroll down | `↓` · `j` | in a PDF |
| Scroll up | `↑` · `k` | in a PDF |
| The next page | `PgDn` · `Space` | in a PDF |
| The page before | `PgUp` · `Shift+Space` | in a PDF |
| The first page | `Home` | in a PDF |
| The last page | `End` | in a PDF |
| Larger | `+` · `=` | in a PDF |
| Smaller | `-` | in a PDF |
| Fit to the column again | `0` | in a PDF |
| Find in it (Enter: next, Shift+Enter: before) | `Ctrl+F` · `/` | in a PDF |
| Open it in its own application | `o` | in a PDF |
| Close it, back to the note | `Esc` | in a PDF |

## The margin

| | Keys | Works |
|---|---|---|
| Previous proposal (from an empty box: into the proposals) | `↑` | in the margin, in the chat's box |
| Next proposal, then the box | `↓` | in the margin |
| Do what the proposal says | `Enter` · `Space` | in the margin |
| Decline what you are talking about (a question: set it aside; a thing done: undo it) | `Del` | in the margin |
| The reply was helpful (again: take it back) | `+` · `=` | in the margin |
| The reply was not helpful (again: take it back) | `-` | in the margin |
| Send what you wrote | `Enter` | in the chat's box |
| Back out: to the day's chat if it is open, else close the pane | `Esc` | in the margin, in the chat's box |

## Settings

| | Keys | Works |
|---|---|---|
| What the agent sees of the picked calendar: its classes, or everything | `Ctrl+Shift+A` | in settings |
| Fetch the picked calendar now | `Ctrl+R` | in settings |
| Rename the picked calendar | `Ctrl+E` | in settings |
| Remove the picked calendar | `Ctrl+Shift+Backspace` | in settings |
| The tick's sound: on or off | `Ctrl+Shift+S` | in settings |
| The pointer follows the keys: every selection · pane changes · off | `Ctrl+Shift+M` | in settings |
| What the agent knows: its notes, to correct or forget | `Ctrl+K` | in settings |
| What the agent may search: each folder of the vault, on or off | `Ctrl+F` | in settings |
| What the agent may do: each kind of action, ask me · do it and tell me · never | `Ctrl+M` | in settings |
| Correct the picked note in your words (Enter too) | `Ctrl+E` | in what the agent knows |
| Forget the picked note, or take a correction back | `Ctrl+Shift+Backspace` | in what the agent knows |

## Typing (the text field's own, not changeable)

| | Keys | Works |
|---|---|---|
| New line; on an empty list item, step out a level, then leave the list | `Enter` | |
| New line in the same block | `Shift+Enter` | |
| New line in what you write | `Shift+Enter` | |
| Nest or un-nest the line (or every line selected) | `Tab` · `Shift+Tab` | |
| Move; by word with Ctrl | `←` · `→` · `↑` · `↓` · `Ctrl+←` · `Ctrl+→` | |
| Select, across lines too; by word with Ctrl | `Shift+←` · `Shift+→` · `Shift+↑` · `Shift+↓` | |
| Select the line; again: its block; again: the note | `Ctrl+A` | |
| Select all | `Ctrl+A` | |
| Let go of a selection (Esc again: close the overlay) | `Esc` | |
| Copy, cut, paste | `Ctrl+C` · `Ctrl+X` · `Ctrl+V` | |
| Delete a letter; a word with Ctrl | `Backspace` · `Del` · `Ctrl+Backspace` | |
| In a box that asks "when?": confirm, or leave it | `Enter` · `Esc` | |

## Outside the page (Hyprland)

| | Keys | Works |
|---|---|---|
| Page (today's note) | `Alt+Super+=` | everywhere (Hyprland) |
| Page alongside | `Alt+Super+\` | everywhere (Hyprland) |
| Deadlines popup | `Alt+Super+D` | everywhere (Hyprland) |
| Pomo popup | `Alt+Super+O` | everywhere (Hyprland) |
| Pomo toggle | `Alt+Super+P` | everywhere (Hyprland) |
| Pomo skip | `Alt+Super+N` | everywhere (Hyprland) |
