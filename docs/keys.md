# Keys

<!-- Written by tools/keys_guide.py from plugin-page/Shortcuts.js and
     plugin-page/hyprkeys.py. Do not edit: change the keys there and run it. -->

Every key the page answers to, as it starts. Any of them can be moved in the page: `Ctrl+/` (or **keys** at the foot of the sidebar) opens the same list, Enter on a row and the new key moves it. The keys you move are kept in `~/.config/longhand/keys.json`; `python3 tools/keys_guide.py --mine` prints this guide with them.

Where a row has two keys, either works: the second is usually the one another app taught (Notion, Todoist, vim) or one a laptop reaches without Fn.

The keys that work **everywhere** (in a box you are typing in too) are the ones about the page itself and where you are in it: the zoom, these lists, the three panes and the page's shape. The panes are the digits, left to right: `Ctrl+1` the sidebar, `Ctrl+2` the middle, `Ctrl+3` the agent's pane; `Ctrl+\` and `Ctrl+|` open and close the side ones. How focus moves between them is in [navigation.md](navigation.md).

## The page

| | Keys | Works |
|---|---|---|
| Zoom in (or Ctrl+wheel up) | `Ctrl+=` · `Ctrl++` | everywhere |
| Zoom out (or Ctrl+wheel down) | `Ctrl+-` · `Ctrl+_` | everywhere |
| Zoom back to 100% | `Ctrl+0` | everywhere |
| Show these keys | `Ctrl+/` | everywhere |
| Show these keys (where nothing is typed) | `?` | in the dashboard, in the sidebar's lists, in the files, in the calendar, in a PDF, in a paper's marks (the agent's pane, beside a PDF), in the export, in the margin, in settings, in what the agent knows, in what the agent may do, in the folders the agent may search, in the check-in |
| Settings (calendars, sound) | `Ctrl+,` | everywhere |
| Quick switcher: projects, notes, papers and views (? searches all notes) | `Ctrl+O` | everywhere |
| Search across all notes (opens the switcher with ?) | `Ctrl+Shift+O` | everywhere |
| The sidebar's first, second… project, from anywhere | `Alt+1` · `Alt+2` · `Alt+3` · `Alt+4` · `Alt+5` · `Alt+6` · `Alt+7` · `Alt+8` · `Alt+9` | everywhere |
| The sidebar: go there, opening it; in it, Time ↔ Files | `Ctrl+1` | everywhere |
| The middle: go there; in it, the note ↔ the dashboard | `Ctrl+2` | everywhere |
| The dashboard, from anywhere (pressed on it, it stays) | `Ctrl+Alt+2` | everywhere |
| The agent's pane: go there, opening it; in it, the whole chat ↔ this block's or task's chat | `Ctrl+3` | everywhere |
| The sidebar: open or close | `Ctrl+\` | everywhere |
| The agent's pane: open (on the day's chat) or close | `Ctrl+|` | everywhere |
| The open pane to the left | `Alt+←` | everywhere |
| The open pane to the right (in the note, with none: this block's chat) | `Alt+→` | everywhere |
| The agent's pane: reading (the middle wide) ↔ discussing (the chat wide); each remembers where you left it | `Alt+Z` | everywhere |
| The agent's pane wider, about 100 px (a drag on its edge too) | `Alt+Shift+←` | everywhere |
| The agent's pane narrower, about 100 px | `Alt+Shift+→` | everywhere |
| On the overlay: keep it as a window. In the window: full screen and back | `F11` · `Ctrl+Alt+P` | everywhere |
| Copy the path of what you are on (in a note, with the line), to give to an agent | `Ctrl+Shift+C` | everywhere |
| Save now, and say so (the page also saves as you write) | `Ctrl+S` | everywhere |
| The menu a right-click opens, at the cursor, on the row, or on the words selected in an answer | `Shift+F10` · `Menu` | in the note, in the dashboard, in the chat's box |
| Close the overlay | `Esc` | in the note |
| Make the whole note private (the agent sees nothing) | `Ctrl+Shift+P` | in the note |
| Make the block private, or the blocks selected (again: not private) | `Ctrl+P` | in the note |
| Export as a PDF: the section you are in, or the blocks selected | `Ctrl+Shift+E` | in the note |
| Only this project's part of the day: the section you are in (again: the whole day) | `Ctrl+Shift+F` | in the note |
| The tasks this day is for, written on any day: show or fold the list | `Ctrl+Shift+T` | in the note |
| In every list: ↑↓ or j k a row, Home and End the first and last, ? these keys | `↑` · `↓` · `j` · `k` · `Home` · `End` · `?` | |

## Writing

| | Keys | Works |
|---|---|---|
| Bold | `Ctrl+B` | in the note |
| Italic | `Ctrl+I` | in the note |
| Inline code | `` Ctrl+` `` · `Ctrl+E` | in the note |
| Strikethrough | `Ctrl+Shift+S` | in the note |
| Make a link (with words selected: they are its text) | `Ctrl+K` | in the note |
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
| Select to the block's start; with a selection, take the block above too | `Ctrl+Shift+↑` | in the note |
| Select to the block's end; with a selection, take the block below too | `Ctrl+Shift+↓` | in the note |
| Top of the note | `Ctrl+Home` | in the note |
| End of the note | `Ctrl+End` | in the note |
| Home: today's note, the keys in it (the side panes stay open) | `Ctrl+H` · `Alt+Home` | everywhere |
| The day before, with a note | `Alt+[` · `Ctrl+PgUp` | in the note, in the dashboard |
| The day after, with a note (and then today) | `Alt+]` · `Ctrl+PgDn` | in the note, in the dashboard |
| Find in the note (in find: select the words) | `Ctrl+F` | in the note, in find (the note's, or a PDF's) |
| Follow the link the cursor is in | `Alt+Enter` | in the note |
| Back: where the middle was before (a link, a day, the dashboard, a file) | `Ctrl+[` · `Ctrl+Alt+←` | everywhere |
| On again, after going back | `Ctrl+]` · `Ctrl+Alt+→` | everywhere |

## The agent

| | Keys | Works |
|---|---|---|
| Chat about this block (with a sign for the agent: it answers first) | `Ctrl+Enter` | in the note |
| The day's chat (in a note from Files: the note's) | `Ctrl+Shift+Enter` | everywhere |
| In the agent's pane: its last answer was helpful (again: take it back) | `Alt+=` | in the chat's box |
| In the agent's pane: its last answer was not helpful (again: take it back) | `Alt+-` | in the chat's box |
| In the agent's pane: the question you asked before (the first time, your last); before the first, the earlier sessions unfold | `Alt+↑` | in the chat's box |
| In the agent's pane: the next question you asked; past the last, back to the foot | `Alt+↓` | in the chat's box |
| In the agent's pane: a screen of the conversation up | `PgUp` | in the chat's box |
| In the agent's pane: a screen of the conversation down | `PgDn` | in the chat's box |

## @ a project

| | Keys | Works |
|---|---|---|
| Previous project | `↑` | while @ or # lists tags, or @ blocks, tasks, notes and papers in the day's box |
| Next project | `↓` | while @ or # lists tags, or @ blocks, tasks, notes and papers in the day's box |
| Write its #tag | `Enter` · `Tab` | while @ or # lists tags, or @ blocks, tasks, notes and papers in the day's box |
| New section (# Name #tag) | `Shift+Enter` | while @ or # lists tags, or @ blocks, tasks, notes and papers in the day's box |
| Close the list | `Esc` | while @ or # lists tags, or @ blocks, tasks, notes and papers in the day's box |

## Find

| | Keys | Works |
|---|---|---|
| Next match | `Enter` · `↓` · `F3` | in find (the note's, or a PDF's) |
| Previous match | `Shift+Enter` · `↑` · `Shift+F3` | in find (the note's, or a PDF's) |
| Go to the match and close find | `Ctrl+Enter` | in find (the note's, or a PDF's) |
| Close find, on the match | `Esc` | in find (the note's, or a PDF's) |
| Close find, back where you were | `Shift+Esc` | in find (the note's, or a PDF's) |

## The switcher

| | Keys | Works |
|---|---|---|
| The match above | `↑` · `Shift+Tab` | in the switcher (Ctrl+O) |
| The match below | `↓` · `Tab` | in the switcher (Ctrl+O) |
| A screenful of matches up | `PgUp` | in the switcher (Ctrl+O) |
| A screenful of matches down | `PgDn` | in the switcher (Ctrl+O) |
| Open the picked item | `Enter` | in the switcher (Ctrl+O) |
| Open the project's page | `Shift+Enter` | in the switcher (Ctrl+O) |
| Close it, back where you were | `Esc` | in the switcher (Ctrl+O) |

## Dashboard

| | Keys | Works |
|---|---|---|
| Move up | `↑` · `k` | in the dashboard |
| Move down | `↓` · `j` | in the dashboard |
| First row | `Home` | in the dashboard |
| Last row | `End` | in the dashboard |
| A view of rows up | `PgUp` | in the dashboard |
| A view of rows down | `PgDn` | in the dashboard |
| Up to the row's band; on a band, fold it | `←` · `h` | in the dashboard |
| Open a folded band; on an open one, into it | `→` · `l` | in the dashboard |
| By date: collapse every band (the words above the list too) | `Shift+←` · `Shift+H` | in the dashboard |
| By date: expand every band (the words above the list too) | `Shift+→` · `Shift+L` | in the dashboard |
| Go to the line; on what the agent proposes, asks or did, its chat (the margin opens beside) | `Enter` | in the dashboard |
| Done (again: not done); on the agent's proposal, accept | `Space` · `e` · `Ctrl+L` | in the dashboard |
| Do on: set the day you mean to work on it (⏳) | `t` · `Ctrl+D` | in the dashboard |
| Take its date off (the day to work on it) | `Shift+T` | in the dashboard |
| Cycle its priority | `p` | in the dashboard |
| Rename it (its line's words) | `Ctrl+E` · `F2` | in the dashboard |
| Cancel it (the line stays, as cancelled); on the agent's proposal, decline | `Del` · `Backspace` | in the dashboard |
| Set aside: out of the list for now (again: back) | `s` | in the dashboard |
| Renew: its clock starts again | `r` | in the dashboard |
| Grade a deadline | `g` | in the dashboard |
| Ask the agent to plan now | `Ctrl+R` | in the dashboard |
| Next thing from the agent to settle (round again at the end) | `n` | in the dashboard |
| The one before it | `Shift+N` | in the dashboard |
| Follow the link in its line (a paper: open it where it was left) | `Alt+Enter` | in the dashboard |
| Chat about it (the agent's pane opens on it) | `c` · `Ctrl+Enter` | in the dashboard |
| Export its section as a PDF, named after it (it stays open) | `Ctrl+Shift+E` | in the dashboard |
| Take back the last change made here (it says which); in the sidebar, a deadline ticked | `Ctrl+Z` | in the dashboard, in the sidebar's lists |
| Clear the search; then back to the note | `Esc` | in the dashboard |
| How Longhand feels this week: the one-minute check-in | `f` | in the dashboard |
| Search the list: the strip's ⌕, typing (words, or a #tag) | `/` · `Ctrl+F` | in the dashboard, on the dashboard's course strip |
| The course strip, on the course picked | `#` | in the dashboard |
| Only that course: the strip's first, second… (0: all) | `1` · `2` · `3` · `4` · `5` · `6` · `7` · `8` · `9` | in the dashboard, on the dashboard's course strip |
| Every course again | `0` | in the dashboard, on the dashboard's course strip |
| Order: by day, by kind, by course | `o` | in the dashboard, on the dashboard's course strip |
| The chip before (its course shown at once, until Space keeps one) | `←` | on the dashboard's course strip |
| The chip after | `→` | on the dashboard's course strip |
| Keep this course, so the next Space adds another (again: take it out) | `Space` | on the dashboard's course strip |
| Unfold the strip: every course with what it holds; in it, only this one | `Enter` | on the dashboard's course strip |
| Unfolded: the row above | `↑` | on the dashboard's course strip |
| Down to the list; unfolded: the row below | `↓` | on the dashboard's course strip |
| Clear what is typed, then the courses; then back to the list (unfolded: fold) | `Esc` | on the dashboard's course strip |

## Calendar

| | Keys | Works |
|---|---|---|
| Previous day | `←` | in the calendar |
| Next day | `→` | in the calendar |
| A week back | `↑` | in the calendar |
| A week on | `↓` | in the calendar |
| A month back | `Ctrl+←` · `PgUp` | in the calendar |
| A month on | `Ctrl+→` · `PgDn` | in the calendar |
| Today | `Home` | in the calendar |
| Open the day in the sheet | `Enter` | in the calendar |
| Down into the lists under it: the day's deadlines, the papers read that day, the projects | `Tab` | in the calendar |
| Straight to the projects | `Shift+Tab` | in the calendar |
| Close the sidebar (back where you were) | `Esc` | in the calendar |

## Deadlines, projects and sections in the sidebar

| | Keys | Works |
|---|---|---|
| Move up (at a list's top, on into the list above) | `↑` | in the sidebar's lists |
| Move down (at a list's end, on into the list below) | `↓` | in the sidebar's lists |
| The first row under the calendar (inside a project: its first) | `Home` | in the sidebar's lists |
| The last project (inside one: its last row) | `End` | in the sidebar's lists |
| Inside a project: a screenful up | `PgUp` | in the sidebar's lists |
| Inside a project: a screenful down | `PgDn` | in the sidebar's lists |
| Open it (a deadline: go to its line; a fold: open or close it) | `Enter` | in the sidebar's lists |
| A deadline: done (again: not done) | `Space` · `Ctrl+L` | in the sidebar's lists |
| Into a project's notes (inside one: open a fold) | `→` | in the sidebar's lists |
| A project: a new section for it in today's note (# Name #tag) | `Shift+Enter` | in the sidebar's lists |
| The project's page: its papers, files, notes and deadlines in one scroll (on a project, or inside one) | `Alt+P` | in the sidebar's lists |
| The project's week: what was done, written and read, what is coming, what to ask (on a project, or inside one) | `Alt+W` | in the sidebar's lists |
| A project: put its #tag at the cursor | `Ctrl+Enter` | in the sidebar's lists |
| Skip to the next list (after the projects: the calendar) | `Tab` | in the sidebar's lists |
| Skip to the list before (before the first: the calendar) | `Shift+Tab` | in the sidebar's lists |
| Back out of the lists, to the calendar (inside a project: out of it; ← on an open fold closes it) | `Esc` · `←` | in the sidebar's lists |
| Find a project: type its letters (th picks #thesis), Enter its notes, Shift+Enter a section, Ctrl+Enter its tag (↑↓ the other matches, Esc stops) | `#` | in the calendar, in the sidebar's lists |

## Files in the sidebar

| | Keys | Works |
|---|---|---|
| Move up | `↑` · `k` | in the files |
| Move down | `↓` · `j` | in the files |
| Open the file in the sheet (a folder: open or fold it) | `Enter` | in the files |
| Open the folder (open: into it) | `→` · `l` | in the files |
| Fold the folder (folded: up to the one it is in) | `←` · `h` | in the files |
| Filter by name | `/` · `Ctrl+F` | in the files |
| Clear the filter; else close the sidebar | `Esc` | in the files |

## A PDF

| | Keys | Works |
|---|---|---|
| Scroll down | `↓` · `j` | in a PDF |
| Scroll up | `↑` · `k` | in a PDF |
| Sideways, when sized up past the fit (or on a page wider than the others) | `←` · `h` | in a PDF |
| Sideways the other way | `→` · `l` | in a PDF |
| The next page; a page taller than the view, a view at a time | `PgDn` · `Space` | in a PDF |
| The page before (a view, on a tall page) | `PgUp` · `Shift+Space` | in a PDF |
| The first page | `Home` | in a PDF |
| The last page | `End` | in a PDF |
| Jump to a page number | `g` | in a PDF |
| Larger (or Ctrl+wheel up, or a pinch) | `+` · `=` | in a PDF |
| Smaller (or Ctrl+wheel down, or a pinch) | `-` | in a PDF |
| Fit again; fitted, switch between its text and the whole page | `0` | in a PDF |
| Find in it, every place listed (Enter: next, Shift+Enter: before) | `Ctrl+F` · `/` | in a PDF |
| Open it in its own application | `o` | in a PDF |
| Dark pages: the paper in the theme's colours (again: as printed); kept for this paper | `i` | in a PDF |
| A scan: read its words (OCR), into a copy that takes its place; the scan is not written | `r` | in a PDF |
| Highlight the words selected; on a mark clicked, make it a highlight | `m` | in a PDF |
| Mark the words selected as a question; on a mark clicked, make it one | `q` | in a PDF |
| A note under the mark clicked, else the last one made | `n` | in a PDF |
| Remove the mark clicked, and its note | `x` · `Del` · `Backspace` | in a PDF |
| Bring back the mark just removed, with its note and name | `u` · `Ctrl+Z` | in a PDF |
| The paper's acronyms: each underlined on the pages, and a list to find one by its letters or words | `a` | in a PDF |
| On what is under the pointer (or the mark clicked): an acronym, to where the paper spells it out (back: the back key); a question, its answer in the paper's chat; else (a highlight, a question not asked) the paper's chat with it attached | `Enter` | in a PDF |
| Let go of the mark clicked (a click on the page away from it does too) or the words selected; then close it, back to the note | `Esc` | in a PDF |

## A paper's marks and chat

| | Keys | Works |
|---|---|---|
| The mark above (the PDF goes to it) | `↑` · `k` | in a paper's marks (the agent's pane, beside a PDF) |
| The mark below (the PDF goes to it) | `↓` · `j` | in a paper's marks (the agent's pane, beside a PDF) |
| To the paper's chat: on the first row, about the paper as a whole; on a mark, with it attached (or the ones kept) | `Enter` | in a paper's marks (the agent's pane, beside a PDF) |
| Keep this mark, to attach several together (again: let go) | `Space` | in a paper's marks (the agent's pane, beside a PDF) |
| To the paper's chat, nothing attached | `Tab` | in a paper's marks (the agent's pane, beside a PDF) |
| To this mark in the PDF, to change its kind, write its note or remove it (a click on the row does the same) | `→` | in a paper's marks (the agent's pane, beside a PDF) |
| Every mark | `1` | in a paper's marks (the agent's pane, beside a PDF) |
| Only the highlights | `2` | in a paper's marks (the agent's pane, beside a PDF) |
| Only the questions, the waiting ones first | `3` | in a paper's marks (the agent's pane, beside a PDF) |
| Ask every waiting question at once, answered one by one | `Ctrl+Enter` | in a paper's marks (the agent's pane, beside a PDF) |
| Let go of the marks kept; then close the pane (from the chat, Esc comes back here) | `Esc` | in a paper's marks (the agent's pane, beside a PDF) |

## Export as a PDF

| | Keys | Works |
|---|---|---|
| The next block | `↓` · `j` | in the export |
| The block before | `↑` · `k` | in the export |
| A screenful of blocks down | `PgDn` | in the export |
| A screenful of blocks up | `PgUp` | in the export |
| Put the block in, or leave it out | `Space` | in the export |
| From a deadline: the section found before (its likelier one) | `←` | in the export |
| From a deadline: the next section found | `→` | in the export |
| The look: minimal or your Omarchy theme | `l` | in the export |
| Edit the title (Tab: on to your name; Enter: back to the blocks; Esc: as it was) | `Tab` | in the export |
| Write the PDF and open it | `Enter` | in the export |
| Close it, back to the note (or the dashboard it came from) | `Esc` | in the export |

## The margin

| | Keys | Works |
|---|---|---|
| Previous proposal (from an empty box: into the proposals, or the other chats' lines) | `↑` | in the margin, in the chat's box |
| Next proposal, then the box | `↓` | in the margin |
| Do what the proposal says | `Enter` · `Space` | in the margin |
| Decline what you are talking about (a question: set it aside; a thing done: undo it) | `Del` · `Backspace` | in the margin |
| The reply was helpful (again: take it back) | `+` · `=` | in the margin |
| The reply was not helpful (again: take it back) | `-` | in the margin |
| Send what you wrote | `Enter` | in the chat's box |
| Reply to the words selected in the agent's answer (several, each attached) | `Ctrl+R` | in the chat's box, in a PDF, in a paper's marks (the agent's pane, beside a PDF), in the note, in the sidebar's lists |
| While the agent answers: stop it, your words back in the box; else back out: to the day's chat if it is open, else close the pane | `Esc` | in the margin, in the chat's box |

## Settings

| | Keys | Works |
|---|---|---|
| What the agent sees of the picked calendar: its classes, or everything | `Ctrl+Shift+A` | in settings |
| Fetch the picked calendar now | `Ctrl+R` | in settings |
| Rename the picked calendar | `Ctrl+E` · `F2` | in settings |
| Remove the picked calendar (it asks first) | `Del` · `Backspace` | in settings |
| Change the picked setting, or open it (a calendar: fetch it now) | `Enter` · `Space` | in settings |
| Correct the picked note in your words (Enter too) | `Ctrl+E` · `F2` | in what the agent knows |
| Forget the picked note, or take a correction back (it asks first) | `Del` · `Backspace` | in what the agent knows |

## Typing (the text field's own, not changeable)

| | Keys | Works |
|---|---|---|
| New line; on an empty list item, step out a level, then leave the list | `Enter` | |
| New line in the same block | `Shift+Enter` | |
| New line in what you write | `Shift+Enter` | |
| Nest or un-nest the line (or every line selected) | `Tab` · `Shift+Tab` | |
| Move; by word with Ctrl | `←` · `→` · `↑` · `↓` · `Ctrl+←` · `Ctrl+→` | |
| A screen up or down; with Shift, selecting | `PgUp` · `PgDn` | |
| Select, across lines too; by word with Ctrl | `Shift+←` · `Shift+→` · `Shift+↑` · `Shift+↓` | |
| Select the line; again: its item, list, block, section, a step wider each time, up to the note | `Ctrl+A` | |
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
| Deadlines popup | `Alt+Super+U` | everywhere (Hyprland) |
| Pomo popup | `Alt+Super+O` | everywhere (Hyprland) |
| Pomo toggle | `Alt+Super+P` | everywhere (Hyprland) |
| Pomo skip | `Alt+Super+N` | everywhere (Hyprland) |
