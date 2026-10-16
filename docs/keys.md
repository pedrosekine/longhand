# Keys

<!-- Written by tools/keys_guide.py from plugin-page/Shortcuts.js and
     plugin-page/hyprkeys.py. Do not edit: change the keys there and run it. -->

Every key the page answers to, as it starts. Any of them can be moved in the page: `Ctrl+/` (or **keys** in the header) opens the same list, Enter on a row and the new key moves it. The keys you move are kept in `~/.config/omarchy-student/keys.json`; `python3 tools/keys_guide.py --mine` prints this guide with them.

Where a row has two keys, either works: the second is usually the one another app taught (Notion, Todoist, vim) or one a laptop reaches without Fn.

## The page

| | Keys | Works |
|---|---|---|
| Zoom in | `Ctrl+=` · `Ctrl++` | anywhere in the page |
| Zoom out | `Ctrl+-` · `Ctrl+_` | anywhere in the page |
| Zoom back to 100% | `Ctrl+0` | anywhere in the page |
| Show these keys | `Ctrl+/` | anywhere in the page |
| Close the overlay | `Esc` | in the note |
| Flip between overlay and window | `F11` · `Ctrl+Alt+P` | in the note |
| Make the note private (the agent sees nothing) | `Ctrl+Shift+P` | in the note |
| Open or close the dashboard | `Ctrl+T` | in the note, in the dashboard |
| Open or close the calendar sidebar | `Ctrl+Shift+B` · `Ctrl+\` | in the note, in the calendar, in the sidebar's lists |
| Go to the sidebar (when open) | `Alt+←` | in the note |
| Back to the note from the sidebar | `Alt+→` | in the calendar, in the sidebar's lists |

## Writing

| | Keys | Works |
|---|---|---|
| Bold | `Ctrl+B` | in the note |
| Italic | `Ctrl+I` | in the note |
| Inline code | `` Ctrl+` `` · `Ctrl+E` | in the note |
| Strikethrough | `Ctrl+Shift+S` | in the note |
| Tick or untick a checkbox | `Ctrl+L` | in the note |
| Bind a checkbox's date, reschedule or unbind it | `Ctrl+D` | in the note |
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
| Go to today's note | `Ctrl+H` · `Alt+Home` | in the note, in the dashboard, in the calendar, in the sidebar's lists |
| The day before, with a note | `Ctrl+[` · `Ctrl+PgUp` | in the note, in the dashboard |
| The day after, with a note (and then today) | `Ctrl+]` · `Ctrl+PgDn` | in the note, in the dashboard |
| Find in the note (in find: select the words) | `Ctrl+F` | in the note, in find |

## The agent

| | Keys | Works |
|---|---|---|
| Ask about this block, or open its conversation | `Ctrl+Enter` | in the note |
| Open the margin for this block | `Alt+→` | in the note |

## @ a project

| | Keys | Works |
|---|---|---|
| Previous project | `↑` | while @ lists projects |
| Next project | `↓` | while @ lists projects |
| Write its #tag | `Enter` · `Tab` | while @ lists projects |
| Start the class (# Course #tag) | `Shift+Enter` | while @ lists projects |
| Close the list | `Esc` | while @ lists projects |

## A question under the cursor

| | Keys | Works |
|---|---|---|
| Switch between yes and no | `←` · `→` · `↑` · `↓` · `Tab` | while a question is under the cursor |
| Answer | `Enter` | while a question is under the cursor |
| Say no | `Esc` | while a question is under the cursor |

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
| Go to the line | `Enter` | in the dashboard |
| Done (again: not done) | `Ctrl+Enter` · `Space` · `e` · `Ctrl+L` | in the dashboard |
| When: reschedule it | `t` · `Ctrl+D` | in the dashboard |
| Cycle its priority | `p` | in the dashboard |
| Drop it | `Del` · `Backspace` | in the dashboard |
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
| Back to the note | `Esc` | in the calendar |

## Deadlines, projects and sections in the sidebar

| | Keys | Works |
|---|---|---|
| Move up | `↑` · `k` | in the sidebar's lists |
| Move down | `↓` · `j` | in the sidebar's lists |
| Open it (a deadline: go to its line) | `Enter` | in the sidebar's lists |
| Into a project's notes | `→` | in the sidebar's lists |
| A project: start its class in the note | `Shift+Enter` | in the sidebar's lists |
| A project: put its #tag at the cursor | `Ctrl+Enter` | in the sidebar's lists |
| On to the next list | `Tab` | in the sidebar's lists |
| Back out of the list | `Esc` · `Shift+Tab` · `←` | in the sidebar's lists |

## The margin

| | Keys | Works |
|---|---|---|
| Previous proposal (from an empty box: into the proposals) | `↑` | in the margin, in the conversation box |
| Next proposal, then the box | `↓` | in the margin |
| Do what the proposal says | `Enter` · `Space` | in the margin |
| Send what you wrote | `Enter` | in the conversation box |
| Back to the note | `Esc` · `Alt+←` | in the margin, in the conversation box |

## Typing (the text field's own, not changeable)

| | Keys | Works |
|---|---|---|
| New line; on an empty list item, leave the list | `Enter` | |
| New line in the same block | `Shift+Enter` | |
| Nest or un-nest the line (or every line selected) | `Tab` · `Shift+Tab` | |
| Move; by word with Ctrl | `←` · `→` · `↑` · `↓` · `Ctrl+←` · `Ctrl+→` | |
| Select, across lines too; by word with Ctrl | `Shift+←` · `Shift+→` · `Shift+↑` · `Shift+↓` | |
| Select all, copy, cut, paste | `Ctrl+A` · `Ctrl+C` · `Ctrl+X` · `Ctrl+V` | |
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
