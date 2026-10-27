// Shortcuts — every key the page answers to, in one place.
//
// Each action says what it does, where it works and the keys it starts
// with. The keys sheet (Ctrl+/) draws this list and lets the student move
// any action to other keys; every handler in the page asks `hit(event, id)`
// instead of naming a key, so a change reaches the place the key is used.
// What the student changed is kept in ~/.config/longhand/keys.json,
// and only that: an action missing from the file has its own keys.
//
// A key is written the way it is shown, "Ctrl+Shift+P": modifiers in the
// order Ctrl, Alt, Shift, Super, then the key. A symbol carries no Shift,
// since the symbol already says it ("Ctrl+?", not "Ctrl+Shift+/"), which
// also makes a symbol the same key on every keyboard layout. "+" itself is
// "Plus".
//
// What is not here is the text field's own: arrows, selecting, the
// clipboard, Backspace, Enter for a new line. Those are listed in the sheet
// (`fixed`) so the whole picture is in one place, and they are reserved, so
// no action can be moved onto them and take typing away.
.pragma library

// Where an action works. "any" is everywhere in the page; the typing ones
// are where a bare letter has to stay a letter.
var places = {
  any: "everywhere",
  note: "in the note",
  mention: "while @ or # lists tags, or @ blocks in the day's box",
  search: "in find",
  dash: "in the dashboard",
  calendar: "in the calendar",
  lists: "in the sidebar's lists",
  files: "in the files",
  margin: "in the margin",
  chat: "in the conversation box",
  settings: "in settings",
  notebook: "in what the agent knows",
  autonomy: "in what the agent may do"
}
var typing = { note: true, mention: true, search: true, chat: true, settings: true }

var groups = [
  { id: "page", title: "The page" },
  { id: "write", title: "Writing" },
  { id: "move", title: "Moving through the note" },
  { id: "agent", title: "The agent" },
  { id: "mention", title: "@ a project" },
  { id: "find", title: "Find" },
  { id: "dash", title: "Dashboard" },
  { id: "calendar", title: "Calendar" },
  { id: "lists", title: "Deadlines, projects and sections in the sidebar" },
  { id: "files", title: "Files in the sidebar" },
  { id: "margin", title: "The margin" },
  { id: "settings", title: "Settings" },
  { id: "typing", title: "Typing (the text field's own, not changeable)" },
  { id: "system", title: "Outside the page (Hyprland)" }
]

// A key is global ("any") when it is about the page itself or where you
// are in it, never about the thing you are on: the zoom, these lists, the
// panes, the page's shape. Global keys are read before anything else,
// wherever the keyboard is (Page.qml, anywhereKey), so none of them may be
// a key a text field types or uses. Everything else works in its place.
// docs/navigation.md has the whole model.
var actions = [
  { id: "zoomIn", group: "page", places: ["any"], does: "Zoom in", keys: ["Ctrl+=", "Ctrl+Plus"] },
  { id: "zoomOut", group: "page", places: ["any"], does: "Zoom out", keys: ["Ctrl+-", "Ctrl+_"] },
  { id: "zoomReset", group: "page", places: ["any"], does: "Zoom back to 100%", keys: ["Ctrl+0"] },
  { id: "keys", group: "page", places: ["any"], does: "Show these keys", keys: ["Ctrl+/"] },
  { id: "settings", group: "page", places: ["any"], does: "Settings (calendars, sound)", keys: ["Ctrl+,"] },
  // The three panes, left to right, are the three bracket keys (the
  // student's idea, 2026-10-23): a pane's key takes you there, opening it
  // if it is closed; pressed in it, it closes it. The middle has nothing
  // to close, so there it flips the note and the dashboard. Alt+←/→ only
  // move between the panes that are open, as Super+arrows do between
  // Hyprland's windows: nothing opens or closes, save one (2026-10-25):
  // Alt+→ in the note with nothing to its right opens the block's own
  // conversation, its key before the panes. Ctrl+J and Ctrl+Shift+B are
  // the keys these had before.
  { id: "sidebar", group: "page", places: ["any"], does: "The sidebar (calendar, projects): go there, opening it; in it, close it", keys: ["Ctrl+[", "Ctrl+Shift+B"] },
  // The sidebar's spaces, after Zen's workspaces (docs/files.md,
  // 2026-10-26): Time and Files, the shifted brackets beside the sidebar's
  // own, wrapping around. They open the sidebar when it is closed.
  { id: "spacePrev", group: "page", places: ["any"], does: "The sidebar's space before (Time, Files), opening the sidebar", keys: ["Ctrl+{"] },
  { id: "spaceNext", group: "page", places: ["any"], does: "The sidebar's space after (Time, Files), opening the sidebar", keys: ["Ctrl+}"] },
  { id: "home", group: "page", places: ["any"], does: "The middle: go there; in it, flip the note and the dashboard", keys: ["Ctrl+\\"] },
  { id: "day", group: "page", places: ["any"], does: "The agent's pane: go there, opening it on the day's conversation; in it, close it", keys: ["Ctrl+]", "Ctrl+J"] },
  { id: "paneLeft", group: "page", places: ["any"], does: "The open pane to the left", keys: ["Alt+Left"] },
  { id: "paneRight", group: "page", places: ["any"], does: "The open pane to the right (in the note, with none: this block's conversation)", keys: ["Alt+Right"] },
  { id: "dashboard", group: "page", places: ["any"], does: "Open or close the dashboard", keys: ["Ctrl+T"] },
  // F11 is every app's full-screen key, and the overlay is the full-screen
  // shape; Ctrl+Alt+P for keyboards whose F-row wants Fn. Ctrl+P is left
  // to what it means everywhere else (a switcher), off since 2026-10-16.
  { id: "pin", group: "page", places: ["any"], does: "Flip between overlay and window", keys: ["F11", "Ctrl+Alt+P"] },
  { id: "close", group: "page", places: ["note"], does: "Close the overlay", keys: ["Esc"] },
  { id: "private", group: "page", places: ["note"], does: "Make the note private (the agent sees nothing)", keys: ["Ctrl+Shift+P"] },

  { id: "bold", group: "write", places: ["note"], does: "Bold", keys: ["Ctrl+B"] },
  { id: "italic", group: "write", places: ["note"], does: "Italic", keys: ["Ctrl+I"] },
  { id: "code", group: "write", places: ["note"], does: "Inline code", keys: ["Ctrl+`", "Ctrl+E"] },
  { id: "strike", group: "write", places: ["note"], does: "Strikethrough", keys: ["Ctrl+Shift+S"] },
  { id: "checkbox", group: "write", places: ["note"], does: "Tick or untick a checkbox", keys: ["Ctrl+L"] },
  { id: "deadline", group: "write", places: ["note"], does: "Bind a checkbox's date, reschedule or unbind it", keys: ["Ctrl+D"] },
  { id: "lineUp", group: "write", places: ["note"], does: "Move the line (or the lines selected) up", keys: ["Alt+Up"] },
  { id: "lineDown", group: "write", places: ["note"], does: "Move the line (or the lines selected) down", keys: ["Alt+Down"] },
  { id: "undo", group: "write", places: ["note"], does: "Undo", keys: ["Ctrl+Z"] },
  { id: "redo", group: "write", places: ["note"], does: "Redo", keys: ["Ctrl+Shift+Z", "Ctrl+Y"] },

  // Ctrl+Up/Down walk the blocks as Word and Docs walk paragraphs, so
  // Alt+Up/Down can move a line, as in VS Code (2026-10-16).
  { id: "blockStart", group: "move", places: ["note"], does: "Start of the block (again: the block before)", keys: ["Ctrl+Up"] },
  { id: "blockEnd", group: "move", places: ["note"], does: "End of the block (again: the block after)", keys: ["Ctrl+Down"] },
  { id: "selectBlockStart", group: "move", places: ["note"], does: "Select to the block's start (again: a block more)", keys: ["Ctrl+Shift+Up"] },
  { id: "selectBlockEnd", group: "move", places: ["note"], does: "Select to the block's end (again: a block more)", keys: ["Ctrl+Shift+Down"] },
  { id: "noteStart", group: "move", places: ["note"], does: "Top of the note", keys: ["Ctrl+Home"] },
  { id: "noteEnd", group: "move", places: ["note"], does: "End of the note", keys: ["Ctrl+End"] },
  // Days, the way Obsidian's daily notes step them: the next day that has
  // a note, since a day without one has nothing to read. Keys a laptop
  // reaches without Fn first (Home and PgUp are Fn+arrows on many), then
  // the ones a full keyboard knows. Ctrl+[ and ] were Notion's back and on
  // until 2026-10-23, when they became the panes; Alt keeps the brackets.
  // Home, from anywhere (2026-10-24, the student's): today's note in the
  // middle, the keys in it; the side panes stay open.
  { id: "today", group: "move", places: ["any"], does: "Home: today's note, the keys in it (the side panes stay open)", keys: ["Ctrl+H", "Alt+Home"] },
  { id: "dayPrev", group: "move", places: ["note", "dash"], does: "The day before, with a note", keys: ["Alt+[", "Ctrl+PgUp"] },
  { id: "dayNext", group: "move", places: ["note", "dash"], does: "The day after, with a note (and then today)", keys: ["Alt+]", "Ctrl+PgDn"] },
  { id: "find", group: "move", places: ["note", "search"], does: "Find in the note (in find: select the words)", keys: ["Ctrl+F"] },
  // Links (docs/files.md, 2026-10-27), as Obsidian has them: Alt+Enter
  // follows the one the cursor is in (a click does too), and the way back
  // and on again are its navigation keys. Back and on are global: they are
  // about where you are, not about the line you are on.
  { id: "followLink", group: "move", places: ["note"], does: "Follow the link the cursor is in", keys: ["Alt+Enter"] },
  { id: "linkBack", group: "move", places: ["any"], does: "Back to where a link was followed from", keys: ["Ctrl+Alt+Left"] },
  { id: "linkForward", group: "move", places: ["any"], does: "On again, after going back", keys: ["Ctrl+Alt+Right"] },

  { id: "ask", group: "agent", places: ["note"], does: "Ask about this block, or open its conversation", keys: ["Ctrl+Enter"] },
  { id: "dayHelpful", group: "agent", places: ["chat"], does: "In the day's conversation: its last answer was helpful (again: take it back)", keys: ["Alt+="] },
  { id: "dayNotHelpful", group: "agent", places: ["chat"], does: "In the day's conversation: its last answer was not helpful (again: take it back)", keys: ["Alt+-"] },
  { id: "dayHere", group: "agent", places: ["note"], does: "The day's conversation, pointing at this block", keys: ["Ctrl+Shift+Enter"] },

  { id: "mentionUp", group: "mention", places: ["mention"], does: "Previous project", keys: ["Up"] },
  { id: "mentionDown", group: "mention", places: ["mention"], does: "Next project", keys: ["Down"] },
  { id: "mentionPick", group: "mention", places: ["mention"], does: "Write its #tag", keys: ["Enter", "Tab"] },
  { id: "mentionClass", group: "mention", places: ["mention"], does: "Start the class (# Course #tag)", keys: ["Shift+Enter"] },
  { id: "mentionClose", group: "mention", places: ["mention"], does: "Close the list", keys: ["Esc"] },


  { id: "findNext", group: "find", places: ["search"], does: "Next match", keys: ["Enter"] },
  { id: "findPrev", group: "find", places: ["search"], does: "Previous match", keys: ["Shift+Enter"] },
  { id: "findGo", group: "find", places: ["search"], does: "Go to the match and close find", keys: ["Ctrl+Enter"] },
  // Esc leaves you on the match, as in every browser and editor; going
  // back to where the search began is its own key.
  { id: "findClose", group: "find", places: ["search"], does: "Close find, on the match", keys: ["Esc"] },
  { id: "findBack", group: "find", places: ["search"], does: "Close find, back where you were", keys: ["Shift+Esc"] },

  // The list keys of Todoist, Gmail and vim beside the arrows; and the
  // note's own keys for the same acts (Ctrl+L ticks, Ctrl+D asks when).
  { id: "dashUp", group: "dash", places: ["dash"], does: "Move up", keys: ["Up", "K"] },
  { id: "dashDown", group: "dash", places: ["dash"], does: "Move down", keys: ["Down", "J"] },
  { id: "dashFirst", group: "dash", places: ["dash"], does: "First row", keys: ["Home"] },
  { id: "dashLast", group: "dash", places: ["dash"], does: "Last row", keys: ["End"] },
  { id: "dashOpen", group: "dash", places: ["dash"], does: "Go to the line; on what the agent proposes, asks or did, talk with it (the margin opens beside)", keys: ["Enter"] },
  { id: "dashDone", group: "dash", places: ["dash"], does: "Done (again: not done); on the agent's proposal, accept", keys: ["Ctrl+Enter", "Space", "E", "Ctrl+L"] },
  { id: "dashWhen", group: "dash", places: ["dash"], does: "When: reschedule it", keys: ["T", "Ctrl+D"] },
  { id: "dashPriority", group: "dash", places: ["dash"], does: "Cycle its priority", keys: ["P"] },
  { id: "dashRename", group: "dash", places: ["dash"], does: "Rename it (its line's words)", keys: ["Ctrl+E"] },
  { id: "dashDrop", group: "dash", places: ["dash"], does: "Cancel it (the line stays, as cancelled); on the agent's proposal, decline", keys: ["Del", "Backspace"] },
  { id: "dashShelve", group: "dash", places: ["dash"], does: "Not now: put it aside (again: back)", keys: ["S"] },
  { id: "dashKeep", group: "dash", places: ["dash"], does: "Keep it: its clock starts again", keys: ["R"] },
  { id: "dashGrade", group: "dash", places: ["dash"], does: "Grade a deadline", keys: ["G"] },
  { id: "dashPlan", group: "dash", places: ["dash"], does: "Ask the agent to plan now", keys: ["Ctrl+R"] },
  { id: "settingsShare", group: "settings", places: ["settings"], does: "What the agent sees of the picked calendar: its classes, or everything", keys: ["Ctrl+Shift+A"] },
  { id: "settingsFetch", group: "settings", places: ["settings"], does: "Fetch the picked calendar now", keys: ["Ctrl+R"] },
  { id: "settingsRename", group: "settings", places: ["settings"], does: "Rename the picked calendar", keys: ["Ctrl+E"] },
  { id: "settingsForget", group: "settings", places: ["settings"], does: "Remove the picked calendar", keys: ["Ctrl+Shift+Backspace"] },
  { id: "settingsSound", group: "settings", places: ["settings"], does: "The tick's sound: on or off", keys: ["Ctrl+Shift+S"] },
  { id: "settingsPointer", group: "settings", places: ["settings"], does: "The pointer follows the keys: every selection · pane changes · off", keys: ["Ctrl+Shift+M"] },
  { id: "settingsNotebook", group: "settings", places: ["settings"], does: "What the agent knows: its notes, to correct or forget", keys: ["Ctrl+K"] },
  { id: "settingsSearch", group: "settings", places: ["settings"], does: "What the agent may search: each folder of the vault, on or off", keys: ["Ctrl+F"] },
  { id: "settingsAutonomy", group: "settings", places: ["settings"], does: "What the agent may do: each kind of action, ask me · do it and tell me · never", keys: ["Ctrl+M"] },
  { id: "notebookCorrect", group: "settings", places: ["notebook"], does: "Correct the picked note in your words (Enter too)", keys: ["Ctrl+E"] },
  { id: "notebookForget", group: "settings", places: ["notebook"], does: "Forget the picked note, or take a correction back", keys: ["Ctrl+Shift+Backspace"] },
  // The note's key for talking about a block, on a row (2026-10-20; Alt+→
  // until 2026-10-23, now the panes'): the agent summoned to think the
  // task through.
  { id: "dashNextAsk", group: "dash", places: ["dash"], does: "Next thing from the agent to settle (round again at the end)", keys: ["N"] },
  { id: "dashPrevAsk", group: "dash", places: ["dash"], does: "The one before it", keys: ["Shift+N"] },
  { id: "dashTalk", group: "dash", places: ["dash"], does: "Talk with the agent about it (the agent's pane opens on it)", keys: ["Ctrl+Shift+Enter"] },
  { id: "dashUndo", group: "dash", places: ["dash"], does: "Take the last tick back", keys: ["Ctrl+Z"] },
  { id: "dashBack", group: "dash", places: ["dash"], does: "Back to the note", keys: ["Esc"] },

  { id: "calPrevDay", group: "calendar", places: ["calendar"], does: "Previous day", keys: ["Left"] },
  { id: "calNextDay", group: "calendar", places: ["calendar"], does: "Next day", keys: ["Right"] },
  { id: "calPrevWeek", group: "calendar", places: ["calendar"], does: "A week back", keys: ["Up"] },
  { id: "calNextWeek", group: "calendar", places: ["calendar"], does: "A week on", keys: ["Down"] },
  { id: "calPrevMonth", group: "calendar", places: ["calendar"], does: "A month back", keys: ["Ctrl+Left", "PgUp"] },
  { id: "calNextMonth", group: "calendar", places: ["calendar"], does: "A month on", keys: ["Ctrl+Right", "PgDn"] },
  { id: "calToday", group: "calendar", places: ["calendar"], does: "Today", keys: ["Home", "T"] },
  { id: "calOpen", group: "calendar", places: ["calendar"], does: "Open the day in the sheet", keys: ["Enter"] },
  { id: "calLists", group: "calendar", places: ["calendar"], does: "On to the day's deadlines and the projects", keys: ["Tab"] },
  { id: "calBack", group: "calendar", places: ["calendar"], does: "Close the sidebar (back where you were)", keys: ["Esc"] },

  { id: "listUp", group: "lists", places: ["lists"], does: "Move up", keys: ["Up", "K"] },
  { id: "listDown", group: "lists", places: ["lists"], does: "Move down", keys: ["Down", "J"] },
  { id: "listOpen", group: "lists", places: ["lists"], does: "Open it (a deadline: go to its line)", keys: ["Enter"] },
  // The note's tick, on a deadline of the day (2026-10-17).
  { id: "listDone", group: "lists", places: ["lists"], does: "A deadline: done (again: not done)", keys: ["Ctrl+L"] },
  { id: "listInto", group: "lists", places: ["lists"], does: "Into a project's notes", keys: ["Right"] },
  { id: "listClass", group: "lists", places: ["lists"], does: "A project: start its class in the note", keys: ["Shift+Enter"] },
  { id: "listTag", group: "lists", places: ["lists"], does: "A project: put its #tag at the cursor", keys: ["Ctrl+Enter"] },
  { id: "listNext", group: "lists", places: ["lists"], does: "On to the next list", keys: ["Tab"] },
  { id: "listBack", group: "lists", places: ["lists"], does: "Back out of the list", keys: ["Esc", "Shift+Tab", "Left"] },

  { id: "filesUp", group: "files", places: ["files"], does: "Move up", keys: ["Up", "K"] },
  { id: "filesDown", group: "files", places: ["files"], does: "Move down", keys: ["Down", "J"] },
  { id: "filesOpen", group: "files", places: ["files"], does: "Open the file in the sheet (a folder: open or fold it)", keys: ["Enter"] },
  { id: "filesInto", group: "files", places: ["files"], does: "Open the folder (open: into it)", keys: ["Right", "L"] },
  { id: "filesOut", group: "files", places: ["files"], does: "Fold the folder (folded: up to the one it is in)", keys: ["Left", "H"] },
  { id: "filesFilter", group: "files", places: ["files"], does: "Filter by name", keys: ["/"] },
  { id: "filesBack", group: "files", places: ["files"], does: "Clear the filter; else close the sidebar", keys: ["Esc"] },

  { id: "marginUp", group: "margin", places: ["margin", "chat"], does: "Previous proposal (from an empty box: into the proposals)", keys: ["Up"] },
  { id: "marginDown", group: "margin", places: ["margin"], does: "Next proposal, then the box", keys: ["Down"] },
  { id: "marginAccept", group: "margin", places: ["margin"], does: "Do what the proposal says", keys: ["Enter", "Space"] },
  { id: "marginDecline", group: "margin", places: ["margin"], does: "Decline what you are talking about (a question: set it aside; a thing done: undo it)", keys: ["Del"] },
  { id: "marginHelpful", group: "margin", places: ["margin"], does: "The reply was helpful (again: take it back)", keys: ["Plus", "="] },
  { id: "marginNotHelpful", group: "margin", places: ["margin"], does: "The reply was not helpful (again: take it back)", keys: ["-"] },
  { id: "chatSend", group: "margin", places: ["chat"], does: "Send what you wrote", keys: ["Enter"] },
  // Esc backs out one level: a block's or a task's conversation to the
  // day's, when that is open (the pane's home); else the pane closes and
  // the keys go back where they were.
  { id: "marginBack", group: "margin", places: ["margin", "chat"], does: "Back out: to the day's conversation if it is open, else close the pane", keys: ["Esc"] }
]

// The text field's own keys: shown, never moved, and never taken. `keys`
// are what a binding may not land on in those places.
var fixed = [
  { group: "typing", places: ["note"], does: "New line; on an empty list item, step out a level, then leave the list", show: ["Enter"], keys: ["Enter"] },
  { group: "typing", places: ["note"], does: "New line in the same block", show: ["Shift+Enter"], keys: ["Shift+Enter"] },
  // The conversation box wraps and grows (ChatField, 2026-10-25): Enter
  // sends, so a new line in a message is Shift+Enter.
  { group: "typing", places: ["chat"], does: "New line in what you write", show: ["Shift+Enter"], keys: ["Shift+Enter"] },
  { group: "typing", places: ["note"], does: "Nest or un-nest the line (or every line selected)", show: ["Tab", "Shift+Tab"], keys: ["Tab", "Shift+Tab"] },
  { group: "typing", places: ["note", "search", "chat"], does: "Move; by word with Ctrl", show: ["Left", "Right", "Up", "Down", "Ctrl+Left", "Ctrl+Right"],
    keys: ["Left", "Right", "Ctrl+Left", "Ctrl+Right", "Home", "End"] },
  // Up and down are the note's lines; a one-line box lends them out (the
  // conversation box's ↑ goes to the proposals). Reserved, not shown twice.
  { group: "typing", places: ["note"], does: "Move a line or a screen", show: [], keys: ["Up", "Down", "PgUp", "PgDn"] },
  { group: "typing", places: ["note", "search", "chat"], does: "Select, across lines too; by word with Ctrl", show: ["Shift+Left", "Shift+Right", "Shift+Up", "Shift+Down"],
    keys: ["Shift+Left", "Shift+Right", "Shift+Up", "Shift+Down", "Ctrl+Shift+Left", "Ctrl+Shift+Right", "Shift+Home", "Shift+End", "Ctrl+Shift+Home", "Ctrl+Shift+End"] },
  // In the note Ctrl+A climbs (NoteEditor.selectAllStep); the one-line boxes
  // take it as select all. Esc in the note lets go of a selection before it
  // closes anything, so it is shown here and reserved by "close" above.
  { group: "typing", places: ["note"], does: "Select the line; again: its block; again: the note", show: ["Ctrl+A"], keys: ["Ctrl+A"] },
  { group: "typing", places: ["search", "chat"], does: "Select all", show: ["Ctrl+A"], keys: ["Ctrl+A"] },
  { group: "typing", places: ["note"], does: "Let go of a selection (Esc again: close the overlay)", show: ["Esc"], keys: [] },
  { group: "typing", places: ["note", "search", "chat"], does: "Copy, cut, paste", show: ["Ctrl+C", "Ctrl+X", "Ctrl+V"], keys: ["Ctrl+C", "Ctrl+X", "Ctrl+V"] },
  { group: "typing", places: ["note", "search", "chat"], does: "Delete a letter; a word with Ctrl", show: ["Backspace", "Del", "Ctrl+Backspace"],
    keys: ["Backspace", "Del", "Ctrl+Backspace", "Ctrl+Del"] },
  { group: "typing", places: [], does: "In a box that asks \"when?\": confirm, or leave it", show: ["Enter", "Esc"], keys: [] }
]

// ------------------------------------------------------------ keys

var SHIFT = 0x02000000, CTRL = 0x04000000, ALT = 0x08000000, META = 0x10000000

var named = {
  0x01000000: "Esc", 0x01000001: "Tab", 0x01000003: "Backspace", 0x01000004: "Enter", 0x01000005: "Enter",
  0x01000006: "Ins", 0x01000007: "Del", 0x01000010: "Home", 0x01000011: "End",
  0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
  0x01000016: "PgUp", 0x01000017: "PgDn", 0x20: "Space", 0x2b: "Plus"
}
// What a hand-written keys.json may say, beyond the canonical names.
var aliases = {
  escape: "Esc", "return": "Enter", backtab: "Tab", "delete": "Del", insert: "Ins",
  pageup: "PgUp", pagedown: "PgDn", pgdown: "PgDn", up: "Up", down: "Down", left: "Left", right: "Right",
  esc: "Esc", enter: "Enter", tab: "Tab", backspace: "Backspace", del: "Del", ins: "Ins",
  home: "Home", end: "End", pgup: "PgUp", pgdn: "PgDn", space: "Space", plus: "Plus"
}
// A dead key (US-International's ` ' ~ ^ ", most European layouts' ^ and
// ´) is the character it prints: with Ctrl held it composes nothing, and
// Ctrl+` has to be Ctrl+` on every keyboard that has a backtick.
var dead = { 0x01001250: "`", 0x01001251: "'", 0x01001252: "^", 0x01001253: "~", 0x01001257: "\"" }
// A modifier on its own is not a key yet.
var lone = { 0x01000020: 1, 0x01000021: 1, 0x01000022: 1, 0x01000023: 1, 0x01000024: 1, 0x01000025: 1,
  0x01000053: 1, 0x01000054: 1, 0x01000055: 1, 0x01000056: 1, 0x01000057: 1, 0x01001103: 1, 0x01ffffff: 1 }

function isSymbol(name) {
  return name === "Plus" || (name.length === 1 && name.toUpperCase() === name.toLowerCase())
}

function compose(ctrl, alt, shift, meta, name) {
  if (isSymbol(name)) shift = false
  return (ctrl ? "Ctrl+" : "") + (alt ? "Alt+" : "") + (shift ? "Shift+" : "") + (meta ? "Super+" : "") + name
}

// The key a key event is, written as above; "" while only modifiers are
// down.
function fromEvent(event) {
  var k = event.key, m = event.modifiers
  if (lone[k]) return ""
  var shift = !!(m & SHIFT)
  var name
  if (k === 0x01000002) { name = "Tab"; shift = true }            // Backtab is Shift+Tab
  else if (named[k] !== undefined) name = named[k]
  else if (dead[k] !== undefined) name = dead[k]
  else if (k >= 0x01000030 && k <= 0x01000047) name = "F" + (k - 0x01000030 + 1)
  else if (k > 0x20 && k < 0x01000000) name = String.fromCharCode(k).toUpperCase()
  else return ""
  return compose(!!(m & CTRL), !!(m & ALT), shift, !!(m & META), name)
}

// Any spelling of a key, written the one way; "" when it is not a key.
function canonical(s) {
  s = String(s || "").trim()
  if (s === "") return ""
  var parts = s.split("+")
  // "Ctrl++": the key is the plus.
  if (parts.length > 1 && parts[parts.length - 1] === "" ) { parts.pop(); parts[parts.length - 1] = "Plus" }
  var ctrl = false, alt = false, shift = false, meta = false
  for (var i = 0; i < parts.length - 1; i++) {
    var p = parts[i].trim().toLowerCase()
    if (p === "ctrl" || p === "control") ctrl = true
    else if (p === "alt") alt = true
    else if (p === "shift") shift = true
    else if (p === "super" || p === "meta" || p === "win" || p === "mod") meta = true
    else return ""
  }
  var last = parts[parts.length - 1].trim()
  var name
  if (last.length === 1) name = last.toUpperCase()
  else if (aliases[last.toLowerCase()] !== undefined) name = aliases[last.toLowerCase()]
  else if (/^f([1-9]|1[0-9]|2[0-4])$/i.test(last)) name = last.toUpperCase()
  else return ""
  return compose(ctrl, alt, shift, meta, name)
}

// A key as the sheet and the hints show it.
var glyphs = { Up: "↑", Down: "↓", Left: "←", Right: "→", Plus: "+" }
function show(seq) {
  var parts = seq.split("+")
  var last = parts[parts.length - 1]
  if (glyphs[last]) last = glyphs[last]
  if (parts.length === 1 && last.length === 1) last = last.toLowerCase()   // a bare letter is the letter you type
  parts[parts.length - 1] = last
  return parts.join("+")
}

// ------------------------------------------------------------ state

var byId = {}
for (var a = 0; a < actions.length; a++) {
  var act = actions[a]
  for (var j = 0; j < act.keys.length; j++) act.keys[j] = canonical(act.keys[j])
  byId[act.id] = act
}
for (var f = 0; f < fixed.length; f++)
  for (var q = 0; q < fixed[f].keys.length; q++) fixed[f].keys[q] = canonical(fixed[f].keys[q])

var changed = {}   // id → [keys], only what differs from the action's own

function defaults(id) { return byId[id] ? byId[id].keys.slice() : [] }

function keysOf(id) {
  if (changed[id] !== undefined) return changed[id]
  return byId[id] ? byId[id].keys : []
}

function isChanged(id) { return changed[id] !== undefined }

function hit(event, id) {
  var s = fromEvent(event)
  if (s === "") return false
  var ks = keysOf(id)
  for (var i = 0; i < ks.length; i++) if (ks[i] === s) return true
  return false
}

// The first key of an action, for a hint ("" when it has none).
function label(id) {
  var ks = keysOf(id)
  return ks.length > 0 ? show(ks[0]) : "—"
}

function same(a, b) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

function set(id, ks) {
  if (!byId[id]) return
  var clean = []
  for (var i = 0; i < ks.length; i++) {
    var c = canonical(ks[i])
    if (c !== "" && clean.indexOf(c) < 0) clean.push(c)
  }
  if (same(clean, byId[id].keys)) delete changed[id]
  else changed[id] = clean
}


// keys.json, read: anything unknown or unreadable is left out, never an
// error — a typo in the file costs that one line, not the page's keys.
function load(obj) {
  changed = {}
  if (!obj || typeof obj !== "object") return
  for (var id in obj) {
    if (!byId[id]) continue
    var v = obj[id]
    if (typeof v === "string") v = [v]
    if (!Array.isArray(v)) continue
    set(id, v)
  }
}

// keys.json, written: only what was changed.
function save() {
  var out = {}
  for (var id in changed) out[id] = changed[id]
  return out
}

// ------------------------------------------------------------ checking a new key

function overlaps(pa, pb) {
  for (var i = 0; i < pa.length; i++) {
    if (pa[i] === "any") return true
    for (var j = 0; j < pb.length; j++) if (pb[j] === "any" || pb[j] === pa[i]) return true
  }
  return false
}

// Can `seq` go on action `id`? { ok, reason, taken: [ids already on it] }.
// A letter, a digit or Space alone stays a letter where you type; the text
// field's own keys stay its own. Another action on the same key in the
// same place is not refused — it is `taken`, for the sheet to ask about.
function check(id, seq) {
  var act = byId[id]
  if (!act || seq === "") return { ok: false, reason: "", taken: [] }
  var parts = seq.split("+")
  var bare = parts.length === 1 || (parts.length === 2 && parts[0] === "Shift")
  var printable = parts[parts.length - 1].length === 1 || parts[parts.length - 1] === "Space" || parts[parts.length - 1] === "Plus"
  if (bare && printable) {
    for (var i = 0; i < act.places.length; i++) {
      var p = act.places[i]
      if (p === "any" || typing[p])
        return { ok: false, reason: show(seq) + " would be typed " + places[p] + " — add Ctrl or Alt", taken: [] }
    }
  }
  for (var f = 0; f < fixed.length; f++) {
    if (fixed[f].keys.indexOf(seq) < 0 || !overlaps(act.places, fixed[f].places)) continue
    var where = fixed[f].places.filter(function (p) { return act.places.indexOf(p) >= 0 || act.places.indexOf("any") >= 0 })[0]
    return { ok: false, reason: show(seq) + " is the text field's own " + places[where] + " (" + fixed[f].does.toLowerCase() + ")", taken: [] }
  }
  var taken = []
  for (var a = 0; a < actions.length; a++) {
    var o = actions[a]
    if (o.id === id || !overlaps(act.places, o.places)) continue
    if (keysOf(o.id).indexOf(seq) >= 0) taken.push(o.id)
  }
  return { ok: true, reason: "", taken: taken }
}

// Give `seq` to `id`: in place of its keys, or beside them (`add`). Any
// action in the same place that had it lets it go.
function assign(id, seq, add) {
  var c = check(id, seq)
  if (!c.ok) return c
  for (var i = 0; i < c.taken.length; i++) {
    var rest = keysOf(c.taken[i]).filter(function (k) { return k !== seq })
    set(c.taken[i], rest)
  }
  var ks = add ? keysOf(id).filter(function (k) { return k !== seq }).concat([seq]) : [seq]
  set(id, ks)
  return c
}

// Keys a text field acts on by itself and the editor has taken over. Once
// the student moves undo (say) elsewhere, the old key must do nothing
// rather than reach the field's own undo, which knows nothing of the
// note's history.
var fieldOwn = ["Ctrl+Z", "Ctrl+Shift+Z", "Ctrl+Y", "Ctrl+Home", "Ctrl+End"]
function fieldWouldTake(event) { return fieldOwn.indexOf(fromEvent(event)) >= 0 }

// Back to the action's own keys. One another action took meanwhile comes
// back too, so no key is ever on two things in one place. Returns the ids
// it took from.
function reset(id) {
  delete changed[id]
  var from = []
  var own = defaults(id)
  for (var i = 0; i < own.length; i++) {
    var c = check(id, own[i])
    for (var t = 0; t < c.taken.length; t++) {
      set(c.taken[t], keysOf(c.taken[t]).filter(function (k) { return k !== own[i] }))
      if (from.indexOf(c.taken[t]) < 0) from.push(c.taken[t])
    }
  }
  return from
}

function does(id) { return byId[id] ? byId[id].does : id }

// The sheet's rows, in group order: a heading, then the actions and the
// fixed keys of that group. `filter` keeps the rows whose words or keys
// hold it. `outside`: the keys that reach the page from Hyprland, as
// hyprkeys.py's state says them ({ owned, actions: [{ id, does, keys,
// own }] }); movable once the page keeps them (`owned`).
function rows(filter, outside) {
  var want = String(filter || "").trim().toLowerCase()
  var wantKey = want.indexOf("+") > 0 ? canonical(want) : ""   // "super+alt+k" finds Alt+Super+K
  function keep(text, ks) {
    if (want === "") return true
    if (text.toLowerCase().indexOf(want) >= 0) return true
    for (var i = 0; i < ks.length; i++)
      if (show(ks[i]).toLowerCase().indexOf(want) >= 0 || ks[i].toLowerCase().indexOf(want) >= 0 || (wantKey !== "" && canonical(ks[i]) === wantKey)) return true
    return false
  }
  var out = []
  for (var g = 0; g < groups.length; g++) {
    var gid = groups[g].id
    var items = []
    for (var a = 0; a < actions.length; a++) {
      var act = actions[a]
      if (act.group !== gid) continue
      var ks = keysOf(act.id)
      if (!keep(act.does + " " + groups[g].title, ks)) continue
      items.push({ kind: "action", id: act.id, does: act.does, keys: ks.map(show), changed: isChanged(act.id),
                   where: act.places.map(function (p) { return places[p] }).join(", ") })
    }
    for (var f = 0; f < fixed.length; f++) {
      var fx = fixed[f]
      if (fx.group !== gid || fx.show.length === 0 || !keep(fx.does + " " + groups[g].title, fx.show)) continue
      items.push({ kind: "fixed", id: "", does: fx.does, keys: fx.show.map(show), changed: false, where: "" })
    }
    if (gid === "system" && outside) {
      var os = outside.actions || []
      var shown = []
      for (var o = 0; o < os.length; o++) {
        if (!keep(os[o].does + " " + groups[g].title, os[o].keys)) continue
        shown.push({ kind: outside.owned ? "hypr" : "fixed", id: "hypr:" + os[o].id, does: os[o].does,
                     keys: os[o].keys.map(show), raw: os[o].keys, own: os[o].own,
                     changed: outside.owned && !same(os[o].keys, os[o].own), where: "Hyprland" })
      }
      // Until the student lets the page keep them, they are listed as
      // Hyprland's, under the one row that offers to.
      if (!outside.owned && shown.length > 0)
        items.push({ kind: "offer", id: "hypr:adopt", does: "Let the page keep these keys, to move them here", keys: [], changed: false, where: "Hyprland" })
      items = items.concat(shown)
    }
    if (items.length === 0) continue
    out.push({ kind: "head", id: "", does: groups[g].title, keys: [], changed: false, where: "" })
    out = out.concat(items)
  }
  return out
}
