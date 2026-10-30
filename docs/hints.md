# Hover hints: a study

_2026-10-30. Started from the student's observation: "when I am typing, I
don't really want hover reminders of what something means. I am focusing on
the keyboard content. Those are useful when my mouse movement is the focus
of the moment."_

The question this study asks is **where is the hand?** A hint is help for
the hand that is moving. On the mouse, a hover hint says what a click will
do and names the key that does the same: the mouse teaches the keyboard.
On the keys, a hover hint is noise over the words being written. When the
hands are on the keys, the help has to come from the keys.

## What the page does today

- 34 hover hints, every one built by `page.tip()` / `page.tips()`: what the
  thing does, then its key, read live from `Shortcuts.js`. The words are
  good. When the hint shows is the problem.
- Each one waits 400 ms (the shell's `PanelToolTip`), then shows, starting
  the wait over every time. Moving along the footer or the toolbar waits
  400 ms at each word.
- Nothing puts a hint away except moving the pointer off its thing: not a
  key, not Esc.
- Three ways a hint came up while the hands were on the keys:
  1. **The pointer follows the keys** (`pointer: every`, the default since
     2026-10-23). A move in a list warps the pointer onto the selected row,
     and 400 ms later that row's hint opens under it. Every j/k in the
     sidebar or the dashboard could bring up a box of keys.
  2. **The note grows under a still pointer.** Hyprland hides the pointer
     on a key press on this machine (`cursor:hide_on_key_press = true`),
     but Qt still counts the hidden pointer as hovering. Enter pushes the
     lines down, a checkbox slides under the spot, and "Tick or untick it"
     opens in the middle of a sentence, under a pointer you cannot see.
  3. **Rows that scroll or redraw** under a resting pointer do the same.
- One exception was already built in: the pointer is never warped while the
  hand is on the mouse (`handMovedAt`). Hints never had the same rule.

## What the benchmark apps do

| App / standard | Behaviour | Source |
|---|---|---|
| macOS, Windows | The pointer hides on typing until the mouse moves (`NSCursor setHiddenUntilMouseMoves`; Windows "Hide pointer while typing"). Help tags close on a key press. | [Apple](https://developer.apple.com/documentation/appkit/nscursor); [Ghostty using it](https://git.uoc.run.place/Applied-Software/ghostty/commit/954c4d7b56efe720930e93440d7d9f15bc2e1439); help tags from use |
| Hyprland (this machine) | `cursor:hide_on_key_press` is on: the system already says "typing = no pointer". | `hyprctl getoption` |
| Zed | `hide_mouse`: never / on typing / on typing and action. Hover popovers have a delay, a hiding delay and a "sticky" setting, as in VS Code. | [Zed docs](https://zed.dev/docs/nightly/visual-customization.html); [hover settings commit](https://git.secluded.site/zed/commit/497b6de85f11a6afeaa3593ce26d22e49e141b91) |
| VS Code | `editor.hover.delay`, `.sticky`, `.hidingDelay`; a key shows the hover from the keyboard (Ctrl+K Ctrl+I), so the keyboard gets the same help without the mouse. | [issue](https://github.com/microsoft/vscode/issues/62835); the key from use |
| Radix, React Aria | A first hint waits (Radix: 700 ms). Once one shows, the next shows at once while you move across (Radix: 300 ms window; React Aria calls it warmup and cooldown). Keyboard focus shows a hint at once. Hints are not shown for touch. | [Radix](https://radix-ui.com/primitives/docs/components/tooltip); [React Aria](https://react-aria.adobe.com/Tooltip) |
| Superhuman, IntelliJ Key Promoter X | Hover shows the key. After a mouse action that has a key, the app says the key for next time. Key Promoter can count, and suggests a key for an action you keep clicking. | [Superhuman help](https://help.superhuman.com/article/478-superhuman-command); [Key Promoter X](https://awesome.ecosyste.ms/projects/github.com%2Fhalirutan%2FIntelliJ-Key-Promoter-X) |
| Linear, Figma | The action's name, then its key, in every hint. Linear lights up the modifiers you already hold. | [setproduct guide](https://www.setproduct.com/blog/tooltip-ui-design); [community note](https://www.producthunt.com/p/hotkey-hint) (second-hand) |
| Emacs which-key | Keyboard-timed hints: pause after a prefix key and the next keys appear (default 1.0 s; faster after the first). Built into Emacs 30. | [which-key](https://github.com/justbur/emacs-which-key); [Emacs Redux](https://emacsredux.com/blog/2026/07/18/which-key-is-now-built-in/) |
| Office KeyTips | Press Alt and letter badges appear on the controls; type them to act. The keyboard's own way to see what can be done. | [Microsoft](https://support.microsoft.com/en-US/Accessibility/windows/use-the-keyboard-to-work-with-the-ribbon) |
| Notion | Block handles and the + appear in the gutter when the mouse moves, and are gone while you type. | From use; not confirmed by a source |
| WCAG 1.4.13 | Content shown on hover must be dismissible without moving the pointer (Esc), hoverable, and persistent. | [W3C](https://www.w3.org/WAI/WCAG22/Understanding/content-on-hover-or-focus) |

What they agree on:

1. **Typing puts the mouse's help away.** The OS, Zed and Notion hide the
   pointer and what hangs off it the moment a key is pressed, and bring it
   back only when the mouse moves.
2. **The mouse's help names the key** (Superhuman, Linear, Figma), which
   the page already does.
3. **The keyboard has its own help, timed by the keyboard**: which-key
   waits for a pause, KeyTips for Alt, VS Code for a key. None of them uses
   the pointer.
4. **A first hint waits; the next ones don't** (Radix, React Aria, macOS).
5. **Teaching works best right after the act** (Superhuman, Key Promoter),
   not before it.

## Design explorations

Ordered by how much each is worth against what it costs.

### A. Hints follow the hand — built 2026-10-30

A hover hint shows only while the hand is on the mouse. Any key except a
modifier alone puts every hint away and keeps them away until the hand
moves the pointer again (more than 2 px, not a warp). This matches what
Hyprland already does with the pointer itself. It fixes all three cases
above: a warp is the keys moving, a row sliding under a still pointer is
not a hand, and Esc (a key) now puts a hint away, which WCAG asks for. A
modifier alone keeps the hint, so "Ctrl-click: put its #tag at the cursor"
can be read while holding Ctrl. Opening the page by its key shows no hint
until the mouse moves.

`Page.qml`: `handOn`, `keysTook()` (called first in `anywhereKey`, which
every pane's keys pass through), the `handHover` handler; each
`PanelToolTip` adds `&& page.handOn`.

### B. Warm hints — built 2026-10-30

The first hint waits about 500 ms. While one is open, or for 300 ms after
it closes, the next one opens at once. Running the mouse along the footer
(today · keys · settings) or the toolbar then reads like one strip instead
of three waits. Built as `Tip.qml`, which every hint now uses: it wraps
the shell's `PanelToolTip` and holds both rules, A's gate and this delay.
The page counts open hints (`tipWarm`, `tipsOpen`, `tipCool`), and a key
cools the strip at once. The first wait went from the shell's 400 ms to
500 ms, since warm hints make up for it.

### C. Teach after the click, in the status line — built 2026-10-30

When the mouse does something that has a key, the status line says the key,
quietly: "next time: Ctrl+H". If the click wrote its own passing word, the
key follows it ("… · next time: Ctrl+L"). It uses the existing passing hint
(`showHint`), so nothing covers the page. This is the mouse-teaches-keyboard
idea at the moment it is most likely to stick.

As built:
- **Once a day for each action**, and never again once its key has been
  used three times (counted in `Shortcuts.js` when `hit()` matches).
- **Only keys that work from where you are**: actions whose place is the
  whole page or the note. A list's Enter, or a key that needs the
  selection somewhere first, is not worth naming. That leaves the seal,
  the date, today, pin, private, the note's chat, ask, the footer (today ·
  keys · settings), Time / Files, and the note's checkbox.
- A Ctrl- or Shift-click is a different action, so it names nothing.
- A hint says which action it teaches (`act` on `Tip.qml`); the note's box
  says so through the editor's `boxClicked`.
- Kept in the state folder as `taught.json` (action → times by key, the
  day last named). `taught` in the usage log says when a key was named, so
  stats can tell whether the key came into use afterwards.

### D. Hover marks follow the hand too — built 2026-10-30

The same gate for the faint `hoverFill` on rows. While the keys move, only
the keys' `selectedFill` shows. A list scrolled by the keys under a still,
hidden pointer then never paints a second, mouse-coloured row. This keeps
the 2026-10-19 rule that mouse and keys never read as the same thing, even
when the mouse isn't moving. Built wider than fills: every mark the mouse
paints, which also covers a button word's accent, a box's accent edge (in
the note and on the dashboard), the dashboard row's "chat c", and the chat
field's hover border. In the note this matters most: a box that slides
under a still pointer is no longer lit. The editor gets `handOn` from the
page.

### E. A hint that fits

The dashboard's task hint lists ten lines (open, done, reschedule, …). It
is the most complete hint on the page and the least read. Options: the
three keys that matter for this row, then "all keys: Ctrl+/"; or the key
as a right-aligned chip so the words scan first (Linear's shape). And no
hint is ever drawn over the line with the text cursor.

### F. Keys that wait show the keys (which-key, KeyTips)

The keyboard's own help. Hold Ctrl (or a leader key) about 700 ms without
pressing anything, and the pane with the keys shows what it answers to:
either small key badges on its controls (KeyTips) or a one-line strip at
the bottom (which-key). Nothing shows on a quick Ctrl+S. This is the
counterpart to A: once hover hints stop for typists, this is how a typist
finds a key without the sheet. The biggest of these explorations; it wants
a mock-up first, in the real theme.

### G. Hints that graduate

Once a key has been used for an action some number of times, its hover
hint drops the key, or the hint goes quiet for that action. This needs the
usage log and a threshold. Watch A–C in use before building it: it may not
be needed.

## Recommendation

A, B, C and D are built. E is next, after a look at the dashboard in use. E needs a look at the dashboard in use. F is the
real design exploration, so mock it up before building. G waits on use.
