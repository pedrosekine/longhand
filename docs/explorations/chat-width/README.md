# The agent's pane for long chats about a paper — 2026-11-22

Whether the agent's pane should be resizable, and what else a long chat
about a paper needs.

**Built 2026-11-22** (branch `claude/chat-width`): the sizing as decided
below (`Layout.js`, `PaneSplit.qml`, `PaneEdge.qml`, Page.qml's "the agent's
pane, sized by hand"; `docs/navigation.md` has the rules), the rail of
quoted words (`ChatTurn.qml`), Alt+↑/↓ through your questions and a paper's
or note's earlier sessions folded (`DayPane.qml`). One correction to what
this page says further down: answers were already drawn as markdown
(`ChatTurn.qml` and `Chat.js`, 2026-11-19, tables by Qt's markdown); only
`Turn.qml`'s own labels are plain text. Not done: the pane beside the
dashboard keeps its own width; the question jumps and the fold are in the
day pane's chats (the day's, a paper's, a note's), not a block's margin.

- `mock.html` (`?v=now|steps|swap|lift|flipread|flipdisc`), rendered by
  `render.sh` to `now.png`, `steps.png`, `swap.png`, `lift.png`;
  `compare.png` shows the four together (`compare.html`), and `flip.png`
  shows the flip on the laptop (`flip.html`).
- `controls.html` (`?s=<scene>`): the agreed design, drawn before building.
  `render-controls.sh` renders every scene to `shots/`. The five
  `board-*.html` gather them (both screens; the controls; by hand and long
  chats; small windows and a note; look b) and are rendered to
  `board-*.png` with headless chromium.
- **No picture is committed** (the student's call, 2026-11-22): every PNG
  here is ignored by `.gitignore`. Run `render.sh` and `render-controls.sh`
  to draw them again, then the boards.

## Decided (grilling with the student, 2026-11-22)

This replaces the recommendation further down where they differ.

- **Three ways to resize, all kept:**
  - Drag the edge freely, as Omarchy's window borders; the edge lights and
    the pointer turns.
  - **Alt+Shift+← / →** nudges the edge by about 100 px.
  - **Alt+Z** flips between two remembered splits: *reading* (the middle
    wide) and *discussing* (the chat wide).
  - A drag or nudge moves the split you are in. At first, reading is
    today's width and discussing puts the paper at its floor. Nothing
    changes position: the chat stays on the right. Mockup B's real swap is
    not built.
- **The paper's floor** is a legibility rule: the paper is never so narrow
  that its text, fitted to the column, drops below about 11 px. That is
  about 550–630 px, measured for each paper. The keys stop there. A drag
  can go past it, down to about 360 px, and a hint says the text is small.
- **The chat's ceiling** is what it can use: the answer's width (about
  580 px) plus the rail. Width beyond that stays with the middle. So
  beside a note (no rail), *discussing* grows the chat only to about
  640 px and the note keeps its 72 characters.
- **One at a time when both cannot fit:** if the paper's floor plus the
  chat's 300 px minimum does not fit (half the laptop, 710 px), one of the
  two shows. Alt+Z switches, and the other waits in a 30 px strip that
  carries a dot when the agent has answered. Today that case shows "too
  narrow".
- **Remembered per window width:** the big screen (1920) and the laptop
  (1440) each keep their own two splits, beside a paper apart from beside
  a note.
- **Seen and clicked:**
  - The word *reading* or *discussing* in the pane's header; a click
    flips.
  - Hovering the word names all three ways.
  - Alt+Z appears in the hint under the box.
  - The three keys go in the keys sheet.
- **Answers are drawn as markdown** (Qt's own) in every chat: lists,
  emphasis, headings, code and tables. Table cells wrap first, and the
  table scrolls sideways only if one column cannot fit. Math is a later
  step.
- **The rail:** when the chat is wide enough, the paper's words an answer
  quotes stand beside that paragraph, with their page. On the laptop it
  just fits at *discussing*.
- **Long chats:** **Alt+↑ / ↓** jump between your own questions, and
  earlier turns fold to one line that Enter opens.
- **Kept as today:** a quote's page link takes the paper there, and
  hovering a quote lights it up in the paper.

Settled after the visualizations:

- **The header word is look b**, on trial: the word with a small glyph of
  the split, whose filled part is the chat's share of the window, so it
  moves while you drag or nudge. Hovering it shows the tooltip, with the
  shortcut first (`board-5-glyph.png`).
- **The chat's ceiling wins on the laptop.** A drag stops when the chat
  reaches what it can use (about 930 px with the rail), so there the paper's
  smallest is about 490 px, not 360. The chat never grows empty margins.
- **Alt+Z works beside a note too**, though there it only adds about 200 px
  (440 → 640). The key always does the same thing.

Before building, check that Ctrl+R (reply to selected words) and the
dotted quote underlines survive answers drawn as rich text.

## What is there today (from the code)

- The pane's width is `Layout.rightPane` (`plugin-page/Layout.js`): the room
  the note leaves, between 300 and **440** px, never over 45% of the window,
  and 0 (the "too narrow" hint) when even 300 does not fit beside a 340 px
  note. There is no way to change it.
- Beside a paper the middle asks for `pdfFor` = 1.8 × the note's width, so
  the pane is already pushed toward its smallest width there.
- An answer is drawn as **plain text** (`Turn.qml`, `Text.PlainText`). The
  prompts allow markdown, so a table arrives as rows of pipes and wraps.
  The tables in the mockups show how they would look if they were drawn.

## The constraint that decides most of it: the measure

The chat's type (design A, 2026-11-19) is ~17 px. At 440 px a line already
holds about 55 characters, inside the 45–75 the eye likes, and the note is
held to 72 for the same reason. **A wider pane does not help prose. Beyond
~600 px it hurts**, because lines get too long. So freely dragging the pane
wider gives a worse chat. The extra width is only worth having for:

1. wide things in an answer: tables, equations, code, a list of papers;
2. the paper's own words next to the answer that quotes them, so the
   eye does not need to cross back to the PDF;
3. moving the balance: while you discuss, the paper is something you
   glance at, not something you read, so it can be narrower.

A long chat also suffers in height (finding the answer from twenty minutes
ago), not only in width.

## Three designs

**A · Steps** (`steps.png`). Three widths, not a free drag: *reading*
(as now, ≤ 440), *even* (half), *discussing* (about 62%, the paper keeps a
column of ~540 px fitted to its text). One key goes each way, and the
hairline drags and snaps to the same three widths. Answers keep their
~580 px measure. The width past it becomes a **rail of the paper's words**
beside the paragraph that quotes them, which the narrow pane cannot show.
The width is remembered per kind of room (paper chats apart from the
day's), so a paper opens as you left the last one.

**B · Swap** (`swap.png`). The chat takes the middle at the note's
measure, and the paper becomes the pane, showing the page the last answer
quotes. This is the most room for a real discussion. But it turns the
three-pane model around: the middle stops being "what I'm working on".
Ctrl+3's meaning and the Esc ladder would need new rules, and the paper
in 440 px is only good for a glance.

**C · Lift** (`lift.png`). The pane stays as it is, and one answer can be
lifted over the paper at full width (Enter on an answer, Esc puts it
back). It is cheap and solves wide content, but only one answer at a
time, and it hides the paper while open.

## Recommendation

**A, with C's job folded into it.** At *discussing* width a table or
equation already has room, so a separate lift is needed only at *reading*
width. Start with A's three steps and the rail. Add C only if wide answers
keep hurting at *reading* width. Keep B as an idea: it is what
*discussing* becomes if 62% turns out not to be enough.

In the same build, for height:

- **Alt+↑ / ↓** jump between your own questions in the chat, as one jumps
  between headings in a note. The keyboard is in the box, so `[` `]` would
  type. Alt+↑ is only bound in the note today (move the line).
- The earlier turns fold to one line ("6 earlier turns about this
  paper"), as the "everything" view already folds by subject.

Proposed keys: **Alt+Shift+← / →** narrower / wider. They are free in
`Shortcuts.js` and in Hyprland's binds (only Super+Alt+Shift is used
there). The pane-number keys stay as they are. It costs no RAM: it is
QML layout only.

The benchmark (below) changes two details. First, the widest step should
behave as a **zoom toggle**, as in tmux `z`, Zed `shift-escape` and
JetBrains `Ctrl+Shift+'`: one press goes to *discussing*, the same press
returns to the width you came from. Second, the width is **remembered once
for all paper chats**, not per paper. No app keeps a width per document,
and the complaints are about widths being lost, not about widths being
shared.

## Open questions as first asked (answered in "Decided" above)

1. Steps or a free drag? (Steps keep the measure. A drag is what every
   other app does.)
2. Does *discussing* also want its own toggle key (zoom), or are the two
   step keys enough?
3. Draw markdown tables in answers at all? Without that, the wide-content
   case is mostly lists and equations.
4. Is the rail of quoted words wanted, or is the orange page link enough?

## How others do it

Researched 2026-11-22 by a subagent with web search. [V] means checked in
the app's own docs or keymap. [S] means a search snippet or forum post
only. [M] means from memory.

| App | Width | Bigger / elsewhere | Long threads |
|---|---|---|---|
| Zed agent panel | drag; keys grow / shrink / reset the dock (`ctrl-alt-=`, `-`, `0`) [V] | `shift-escape` zooms the panel to the whole window and back [V] | previous / next of your own prompts (`ctrl-alt-pageup/down`), scroll to top / latest [V] |
| VS Code Copilot Chat | drag [V] | the same chat in the side bar, an editor tab or its own window [V] | Accessible View: one answer as plain text (`Alt+F2`) [V] |
| JetBrains AI Assistant | keys resize the active tool window (`Ctrl+Alt+Shift+arrows`); a size remembered per tool window [V] | maximize / restore (`Ctrl+Shift+'`), float, own window [V] | none |
| Cursor | drag; widths reported to reset between layouts [S] | preset layouts; pop-out removed in 2.0 [S] | none |
| Readwise Reader | drag since Aug 2026 [V] | the sidebar chat expands to full-screen Ghostreader, same thread [S] | save an answer to the document's note [V] |
| NotebookLM | no drag found [S] | sources panel collapses to a thin rail [V] | citations jump to the quote; save to note keeps tables [V] |
| Acrobat AI Assistant | desktop: show / hide only [V] | none found | none |
| ChatGPT | none | long answers open in a full-screen editor with a table of contents (Canvas replaced, mid-2026) [S] | the table of contents |
| Zotero 7/8 + plugins | side panes drag and collapse at a minimum [S] | llm-for-zotero: its own window [S] | jumps back to cited pages [S] |
| SciSpace, ChatPDF, Elicit | fixed split [S/M] | none found | citations link to the passage [M] |
| tmux, i3 | `C-arrow` / `M-arrow` small and large steps; i3 resize mode [V] | tmux `z` zoom, `{` `}` swap [V] | none |

What recurs:

- **Zoom is a toggle.** The same key that grows the pane to full size
  brings it back to where it was (tmux, Zed, JetBrains).
- **Keyboard resizing goes in steps, with a reset**, never pixel by pixel.
- **Lost widths draw the complaints** (Cursor, Chrome). Nobody keeps a
  width per document.
- **The thread stays the same when the chat changes place** (VS Code,
  Readwise).
- **Jumping between your own prompts** is the one first-class aid for long
  threads (Zed). ChatGPT's full-screen answer with a table of contents is
  the closest thing to C · Lift.
- **Paper tools lag.** Fixed splits, no keys. Nobody puts the quoted
  passage beside the answer, which makes A's rail the distinctive part.
- **Collapse to a rail, not to nothing** (NotebookLM, Zotero).

Sources: zed.dev/docs/ai/agent-panel; Zed's default-linux keymap;
code.visualstudio.com/docs/agents/chat-view; jetbrains.com/help/idea/
manipulating-the-tool-windows.html; docs.readwise.io/reader/guides/
ghostreader/chat; readwise.io/reader/update-aug2026; support.google.com/
notebooklm/answer/16179559; helpx.adobe.com (Acrobat mobile AI);
forum.cursor.com/t/139704; felloai.com/chatgpt-canvas; forums.zotero.org/
discussion/111472; github.com/yilewang/llm-for-zotero; tmux(1); i3 user's
guide.
