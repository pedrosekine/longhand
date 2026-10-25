# Plan — Longhand

## Architecture
- `cli/` — single-source timer + deadline core (bash, no deps)
  - state in `~/.local/state/longhand/` (`state.json`, `deadlines.tsv`, `pomo.log`)
  - commands: start, pause, resume, toggle, reset, skip, status, stats, deadline, report
- `cli/longhand-check` — one copy of a task: brings the deadline store, the ledger
  (`ledger.json`) and the note lines in line with each other; the page and the
  popup run it. Reference: `docs/tasks.md`
- `plugin/`, `plugin-deadline/` — thin Omarchy bar widgets that read the state files
- `page/` (next) — Quickshell full-screen panel: today's note, blank page, the trigger
- `agent/` (next) — the runner: allowlist context builder, payload log, tool-less
  opencode agent, transcript + state file. Reference: `docs/diary.md`

## Steps (one at a time)
- [x] Step 1 — folder + README + this plan
- [x] Step 2 — `gh repo create pedrosekine/omarchy-student --public --source .` (done, origin set; renamed `pedrosekine/longhand` on 2026-10-16, folder `~/Projects/longhand`)
- [x] Step 3 — v0.1 CLI prototype: `cli/pomo` bash script + state file — on PATH via `ln -sfn "$PWD/cli/pomo" ~/.local/bin/pomo` (absolute target: re-link after moving the repo, or the bindings and both widgets fail with "binary could not be found")
- [x] Step 4 — Hypr bindings: `SUPER+ALT+P` toggle, `SUPER+ALT+N` skip in `~/.config/hypr/bindings.lua` (SUPER+P was taken by Pseudo window)
- [x] Step 5 — v0.2 bar widget: `plugin/` QML (`longhand.pomo`: countdown label + progress popup, left=popup, right=toggle, middle=skip). Installed as real files in `~/.config/omarchy/plugins/longhand.pomo` (symlinks not allowed there — copy on change, shell auto-reloads).
- [x] Step 6 — session counter: `pomo stats [day|week|month|--json]` (calendar week Mon–Sun) + popup segmented Day/Week/Month selector with live count. Counts `focus started` lines in `pomo.log`.
- [x] Step 7 — finish cue: `pomo bell` (desktop notification + bell sound), auto-fired once by the widget on running→expired edge. Sound: `sounds/done.wav` (Mixkit "Uplifting flute notification", free license, see sounds/README.md).
- [x] Step 8 — auto-start flow: `auto` flag in state.json, `pomo autostart [on|off|toggle]`, `pomo expired` edge handler (bell + auto-advance), popup switch. Provisional name "auto-start" — naming decision tracked in issue #1.
- [x] Step 9 — popup controls: icon buttons (play/pause, skip, reset) side by side; tap-timer duration picker (15/25/45/60 min chips when idle, tap toggles picker, tap while running pauses/resumes). CLI `pomo start [focus|break] [minutes]` with per-phase default persisted (`focus_len`/`break_len`/`total` in state.json).
- [x] Step 10 — typed minutes (idle timer is a minutes field, Enter starts) + completions-only counting (`focus completed` logged at expiry; CLI stats + popup recount).
- [x] Step 11 — microwave-style entry, no caret: plain focusable Text (cursor impossible), digits shift in (--:-2 → --:25 → 25:00 → 250:00), Backspace deletes, Enter starts, Escape blurs.
- [x] Step 12 — deadlines (manual): `pomo deadline add|list|rm|next`, stored as
      `deadlines.tsv` (`id<TAB>epoch<TAB>title`). Free-text dates via `date -d`
      ("next friday 17:00", "in 3 hours", "3d", "by friday"); a bare day snaps to
      23:59 because a deadline means the end of that day. New `longhand.deadline`
      bar widget (`plugin-deadline/`): calendar glyph + countdown to the next
      deadline, urgent-coloured inside 24h, popup lists the next 6 with `x` to
      remove. Installed alongside `longhand.pomo` in the bar's center section.
- [x] Step 13a — deadline identity: ids are handed out once and never reused
      (high-water mark in `deadlines.seq`, self-healing from the store when the
      file is missing), and `pomo deadline set <id> [--title <text>] [<when...>]`
      edits in place. Also fixed `parse_when`: GNU date reads today/tomorrow/
      yesterday as now +/- 24h, so those never hit the end-of-day snap and
      "tomorrow" landed at whatever o'clock you typed it.
- [x] Step 13b — closing deadlines out. Store grows three columns
      (`status<TAB>done_at<TAB>grade`; old three-column lines read as open).
      CLI: `pomo deadline done|reopen|grade|hide|unhide <id>`, `list --all`,
      and `pomo report --json` (timer + stats + every deadline incl. hidden,
      the one call an agent needs). Grading an open deadline marks it done;
      hiding keeps the record for the agent but drops it from list and popup;
      `rm` still deletes. Bar counts down to the next *open* deadline only
      (`✓` when everything is handed in). Popup is a keyboard grid: rows are
      deadlines, columns are the row itself (Enter = done/undo), grade (inline
      editor), hide, remove; `d` `g` `x` shortcuts; done rows strike through
      and sink to the bottom. `SUPER+ALT+D` summons it. Gotcha: the shell's
      plugin hot-reload keeps the old compiled component, so after copying
      QML into `~/.config/omarchy/plugins/` run `omarchy restart shell`.
- [ ] Step 14 — the diary. Reference plan with files, loop, page, tests and
      phases: `docs/diary.md`. Phases, each shippable alone:
      - [x] 14.1 the page — `plugin-page/` (`longhand.page`, kind `overlay`,
            keepLoaded). Themed sheet, date, today's note as plain text, save
            per keystroke (300 ms coalesce, flush on Enter/close, atomic
            writes), Esc closes, Enter continues list items and checkboxes,
            Ctrl+Up/Down jump blocks. Block splitting in `Blocks.js` with a
            Python twin `agent/blocks.py`; `tests/test_blocks.py` cross-checks
            them. Config: `~/.config/longhand/config.json` (see
            `config.example.json`). Note created from
            `<vault>/agents/longhand/templates/daily.md` by whoever gets there
            first — the same file is set as Obsidian's daily-notes template.
            Install: copy to `~/.config/omarchy/plugins/longhand.page/`, add
            `{"id":"longhand.page"}` to `plugins[]` in shell.json, bind
            `SUPER+ALT+=` → `omarchy-shell shell toggle longhand.page '{}'`.
            Gotcha: overlays are toggled via the `shell` target, not their id.
      - [x] 14.2 the loop — `agent/longhand-agent` (Python, no deps): builds
            the payload from the allowlist (note minus private blocks and the
            link line, knowledge files, curriculum folder, `pomo report`),
            logs it to `~/.local/state/longhand/payloads/`, runs
            `opencode run --pure --agent longhand --format json` with the
            tool-less agent in `agent/opencode/longhand.md` (DeepSeek 4.1
            flash via OpenCode Go), parses one fenced JSON block (reply,
            proposals, suggestions, knowledge), and applies it: transcript
            `agents/longhand/daily/<date>.md`, state `<date>.json`, knowledge
            files (path-guarded), `cost.tsv`. `guard_write` refuses any path
            under the daily folder. Page triggers: Enter after a checkbox /
            `@` / `?` line, a tick, and page open (skipped when nothing is
            new); runs launch only after the save has landed; header mark
            brightens while running, accent when a reply waits for a block
            still in the note. Tests: `tests/test_agent.py` (stub opencode:
            allowlist, no-write, apply, quiet open, private day) — all green.
            CLI: `deadlines.tsv` is 8 columns (`subject`, `link`), `pomo
            deadline add/set --subject --link`, `list --subject`, `pomo start
            --for <id>` carried into state and every log line. First real
            run: silent open pass $0.0009; a mention got a specific,
            evidence-based reply for $0.0005. Watch: model latency varied
            1 s → 10 s → 50 s across three calls; provider-side.
      - [x] 14.3 the overlay — blocks the agent has seen are veiled (a
            half-transparent wash in the sheet's own colour over the text, so
            the theme decides the look); blocks with a reply get a gutter
            mark, accent until looked at, dim after. The margin: a second,
            narrower sheet to the right showing the reply, proposals, and
            the dive-in chat for the block under the cursor (or the nearest
            one above when the cursor sits on a blank line); looking at it
            for a second marks it read (`longhand-agent ack`). `Ctrl+Enter`
            focuses the chat field, Enter sends (`longhand-agent chat`
            continues the block's opencode session), Esc returns to the
            note. Bar glyph `󰏫` (the plugin is now `overlay` + `bar-widget`)
            toggles the page and turns active when a reply is unread.
            `AgentState.qml` reads today's state file for both. Gotcha: the
            page is keepLoaded, so QML changes need `omarchy restart shell`,
            not just a copy. Revised the same afternoon: Enter/tick only
            *stage* a block (hollow mark), `Ctrl+Enter` sends; keys moved to
            `Alt+Up/Down` (blocks), `Ctrl+Up/Down` (block start/end),
            `Alt+Right` (chat), `Alt+Left`/Esc (back). Then once more: Enter
            on a signed line stages *and* asks in the margin with *no*
            preselected (arrow + Enter sends); `Ctrl+Enter` sends only a
            signed block. `languages` list in config; the runner detects the
            block's language by stopwords and states it in the payload,
            after a Dutch reply to an English note. Open-pass observations
            kept in state under `observations` for the suggestions panel.
      - [x] 14.4 proposals — the margin lists the agent's proposals under the
            reply; `Alt+Right` focuses them (then the chat field), Enter
            accepts one: `longhand-agent accept --hash --index` runs `pomo
            deadline add` with title/subject/link/when, records the new id
            in state and transcript, never twice. The prompt now flags
            disagreements between the note and the deadline store (the
            store is the truth). Tasks panel on `Ctrl+T`: `longhand-agent
            tasks` lists every open checkbox across daily notes (read-only),
            last seven days open, older folded; Enter ticks — today's note
            in the editor, another day's file rewritten one line, atomic —
            because the page is the one writer. Verified end to end: a
            checkbox line → prompt → yes → proposal → Enter → deadline #5 in
            the store (then removed). Gotcha: copying a QML file into the
            plugins dir closes the running overlay even though the code is
            not replaced; restart the shell instead. Revised after use: a
            checkbox list is one submission, staged when the list is left
            (runner takes `--hash h1,h2,…`, one record per item sharing a
            `group`); the margin is on-demand only (`Alt+Right`/`Ctrl+T`);
            the send prompt is a washed line under the cursor; `- []`
            autocorrects to `- [ ] `.
      - [x] 14.5 knowledge — the payload now carries an "Intentions and
            outcomes" section computed locally from the last 14 days of
            checkboxes (done vs open, per day), so `patterns.md` rests on
            facts; the prompt says what each knowledge file is for.
            Suggestions: deduplicated by content-word overlap against the
            day's list and against `knowledge/dismissed.md`, a file the
            runner writes and the model may only read; the payload lists
            dismissals as "do not raise again". `longhand-agent next` lists
            open tasks plus undismissed suggestions and open-pass
            observations across the last 7 days; the `Ctrl+T` panel is now
            "what's next": tasks on top, "from the agent" below, Enter ticks
            a task or waves off a suggestion. `curriculum` folder in config
            (`agents/longhand/curriculum`); `longhand-agent curriculum`
            converts PDFs to markdown once with pdftotext; `.md` files there
            are always in the payload. `- []` and a bare `[]` at line start
            become `- [ ] `.
      - [x] 14.5b alongside — the same content tree reparented into a
            Quickshell `FloatingWindow` (title "Page — today's note"), which
            Hyprland tiles like any app. `SUPER+ALT+backslash` summons it
            (`{"shape":"alongside"}` payload), `Ctrl+P` or the header "pin"
            mark flips between overlay and window, Esc does nothing in the
            window, closing the window closes the page. The margin opens
            inside the window (45% width) instead of beside the sheet.
      - [x] 14.6 rendering — `NoteEditor.qml`: one text field per *line*,
            not per block, with the markdown that only says what kind of
            line it is (`# `, `- [ ] `, `1. `, `> [!private] `, indentation)
            lifted off and drawn instead ("always drawn", chosen over raw
            markdown under the cursor). `Rows.js` derives the rows from the
            text and keeps prefix + body == line, so the note changes only
            where typed. Blank lines are drawn as block space (a little air
            when a block starts with no blank line), and arrows skip them.
            Enter carries list and quote markers, Backspace at a line's
            start drops its kind, then its indent, then joins; Ctrl+L ticks;
            (2026-10-19: Enter on an empty nested item steps out one level,
            as Shift+Tab and Notion do, and leaves the list only at the
            outermost; Backspace takes the indent a level at a time);
            undo is the editor's own (cross-field). Page logic (staging,
            send prompt, panel) is unchanged and talks to the editor through
            the same `text`/`cursorPosition`/`insert`/`remove`. Not yet:
            selecting across lines (selection is per line).
            `tests/tst_editor.qml` drives it offscreen with qmltestrunner.
            Inline emphasis is drawn too (`Emph.js`, 2026-10-15): a row with
            `**bold**`, `*italic*`, `` `code` `` or `~~struck~~` in it becomes
            rich text whose plain text is still the body character for
            character, markers in a one-pixel transparent span, so every
            offset above holds; a row without emphasis stays plain text.
            `tests/tst_emph.qml` proves the drawn text strips back to the
            body.
      - [x] 14.6b overlay and window side by side — the shell's `toggle`
            hides a plugin whose `opened` is true, so SUPER+ALT+= closed the
            window. `opened` now means the overlay only: with the window
            open (anywhere), SUPER+ALT+= brings the overlay up, the one sheet
            moves into it and the window shows "on the overlay"; Esc or the
            key again returns it. SUPER+ALT+\ while the overlay is up moves
            the sheet to the window. Only opening from nothing runs the
            automatic pass.
      - [x] 14.6c size — body type is the shell's `title` token (14 px at
            the default base-size, was `heading`, 16), so the page sits with
            the terminal and GTK apps. Browser-style zoom of the whole page
            (type, spacing, margins, panel; not the window's own size):
            Ctrl+= / Ctrl+- / Ctrl+0 over 67–200%, shown in the header for a
            moment, kept in `~/.local/state/longhand/page.json`.
      - [x] 14.6d find — Ctrl+F opens a line under the date; matches are
            case-insensitive, in the rows' words only (never the lifted
            markdown), painted under the text (current one stronger) and
            counted "n / m". Enter / Shift+Enter step with wrap-around;
            Ctrl+Enter selects the match and closes; Esc returns the cursor
            to where the search began.
      - [x] 14.6e sidebar — Ctrl+B (Ctrl+Shift+B since 2026-10-15, when
            Ctrl+B became bold), hidden unless asked (diary.md decisions
            log, 2026-10-09). Lists the daily folder (FolderListModel,
            watched) by date, newest first, by month; names in the
            configured format and the common older ones (`Days.js`).
            Enter/click opens a day in the same sheet, editable; the save
            for the old day lands first. `Service.openDate`, `AgentState.date`,
            and `--date` on run/chat/ack/accept carry the agent to that day;
            notes named in another format get "agent off". Only today is
            ever created from the template.
      - [x] 14.6f calendar — the sidebar list became a month grid: a day's
            number full where a note exists, faded where none does; today
            dotted, the open day outlined. Arrows move by day/week across
            month edges, Ctrl+Left/Right and PageUp/Down by month (day
            clamped), Home to today. A day without a note opens empty with
            the template's header held ready, and its file is written only
            once something is typed (`Service.exists`). `weekStart` in the
            config, else the locale.
      - [x] 14.6g selecting across lines — a selection that crosses a line
            (Shift+arrows past the edge, a mouse drag, Ctrl+A) is held by
            the editor as text offsets and painted under the words; typing,
            Backspace/Delete, cut/copy/paste (markdown included), Enter and
            Tab/Shift+Tab act on all of it. One pointer area over the lines
            does placing, dragging and double-click words; presses on a
            checkbox pass through. `tests/test_agent.py` now dates its
            fixtures from today (recency is judged against the clock).
            2026-10-19, tested by simulated mouse: a triple-click takes the
            line, a drag held after a double or triple click grows by words
            or lines, Shift+click carries on from a double-clicked word, a
            wrapped line is painted on every visual line, and a blank line
            no longer opens under a drag (it moved the lines below).
      - [x] 14.6h deadlines and notes, one thing (decided 2026-10-10, see
            diary.md). Subjects became projects (`--project`, `--subject`
            kept as an alias; `knowledge/projects/`). A checkbox line can
            stand for a deadline: `- [ ] words #tag 📅 2026-10-16 17:00 ^d6`
            (Obsidian Tasks date + block id; the store's link is
            `[[stem#^d6]]`). Ways in: a cue at the end ("due/by/until/
            before/📅 <date>") recognised as typed and bound on leaving
            the line (since 2026-10-13, see below); Ctrl+D (bind, reschedule,
            clear to unbind); accepting an agent proposal (it binds the line
            it names, anywhere in the submission — no such line, no
            binding); Enter twice on an
            unwritten deadline in what's next. The store wins: page edits go
            to it at once (tick → done, words → title, #tag → project), store
            edits reach the line when its note opens, a removed deadline
            leaves the date as text; deleting a bound line asks (a cut does
            not). Calendar corner marks (accent open, urgent late, hollow
            done) and the day's deadlines under the grid (Tab, Enter goes to
            the line); what's next leads with deadlines; the popup's `o`
            opens the line, done ones leave the list the day after and
            ungraded ones wait in a folded row. Tests: tst_bound.qml,
            test_pomo.py, and an IPC-driven run of every path on a scratch
            store.
      - [x] 14.6j stabilise (2026-10-11, after an assessment) — an unreadable
            store no longer strips anchors; prompts take arrows+Enter, never
            a letter; deleting a bound line hides the deadline; ticks from
            what's next find their line by its words (Tasks.js); line
            tracking resets per note and a rename lands on close; the open
            note is watched for outside edits (Obsidian); `pomo` locks the
            store (eight racing adds gave duplicate ids before); the runner
            queue is FIFO; "today" follows the clock. tests/page/run.py drives
            the page live over IPC (21 checks). `longhand-agent stats` and the
            page's local usage log, for the freeze.
- [x] 14.6k theme (2026-10-11, the last change before the freeze) — the page
      draws in the Omarchy theme's palette by role (ThemeColors.qml, read from
      the theme's colors.toml and re-read on a theme switch): headings h1–h4
      four kinds of thing (2026-10-15, spaced out 2026-10-16 — H1 the theme's
      one chroma, lifted to 4.5:1 if fainter and deepened up to 1.3× if it
      sits within ΔE 45 of the text; H2 that colour halfway to the prose; H3
      the prose; H4–H6 `dim`. Adjacent levels are at least ΔE 15 apart, which
      contrast alone does not give you. A palette with no chroma to lend
      walks the prose down to its grey in thirds instead), search
      matches yellow and the current one orange, the theme's own selection, a
      ticked box green, bullets and numbers in the accent, a private callout in
      magenta. Secondary text uses the theme's grey only if it reads at 4.5:1
      (faint things at 3:1); otherwise the foreground faded no further — most
      stock themes' `muted` is a 1.5–3:1 comment grey.
- [x] 14.6l projects in the sidebar (2026-10-11, the one agreed exception to
      the freeze: it keeps tomorrow's tag convention from sprawling).
      `longhand-agent projects` reads knowledge/projects/*.md — tag from a
      `Tag: #x` line (else the file name), name from the H1, next session
      from `- Mon 12 Oct: 10:45–… (Room)` lines — and the calendar lists them
      soonest first. Enter starts a class (`# Course #tag` at the end of
      today's note, cursor under it); Ctrl+Enter puts the tag at the cursor.
      The five courses' files were written from the IT:U timetable feed.
      - [x] 14.6i projects for notes (2026-10-15, the first thing off the
            parking lot once the freeze lifted). `longhand-agent sections
            --tag <tag>` gathers every section of a project's tag across the
            daily notes, newest day first: a tagged heading claims
            everything under it until the next heading of the same or a
            higher level, so an H2 never ends an H1, and a tagged heading
            inside a section of the same tag is part of it rather than a
            second copy. Each section carries its title (the heading
            without the tag), the headings under it as its index, its
            checkbox counts and a preview. In the sidebar's projects, `→`
            (or Shift+click) opens the project in the margin; Enter opens a
            section in the sheet with the cursor on its heading, found by
            its words rather than its line number, in whatever day it was
            written. Found on the way: a page opened from nothing kept the
            panel the last session left open, squeezing the sheet — the
            margin is on-demand only, so a fresh open now shows the note
            alone. Tests: `tests/test_agent.py` (the claiming rule),
            `tests/page/run.py` (the list, the jump, the fresh open).
- [x] **Freeze, 2026-10-11 → 2026-10-25: fixes only, use it.** At the end,
      `longhand-agent stats --since 2026-10-11` and decide with it:
      - habit — days written in, days the page was opened, minutes;
      - intention → outcome — checkboxes ticked / written (0/17 before);
      - deadlines — bound from a note vs elsewhere, closed by their time;
      - finding — calendar and past days opened, find used (the case for
        projects); #tags used unprompted;
      - languages — blocks per language (the case for multi-language cues);
      - focus — pomodoro sessions (0 since 2026-09-17).
- [x] **Freeze lifted 2026-10-15**, ten days early: a week of classes had
      given it enough to say. `longhand-agent stats --since 2026-10-11`:
      - habit — 4 of 5 days written in, 4 with the page opened (20 opens,
        371 min), 1324 words. **The habit took; that was the question.**
      - intention → outcome — 2 of 22 checkboxes closed (0/17 before).
        Still the weakest number in the tool.
      - deadlines — 29 added, 18 bound from a note line, 2 closed. None
        closed "by their time" because nothing is due before 2026-10-30:
        **that axis cannot be judged until November.**
      - finding — calendar 31, past days 11, three tags used unprompted
        (#intsem #respro #hfpi). **The case for projects, confirmed.**
      - languages — 61 English blocks against 3 Portuguese. **Multi-language
        is refuted for now**; it stays on the lot, further down.
      - focus — 0 pomodoro sessions in a month. **Focus mode is refuted**
        on the same terms; the pomodoro is vestigial, not yet removed.
      - the agent — 15 runs all week, $0.0303, and the send prompt answered
        **yes once against no 41 times**. 10 of those were the 10-13 prompt
        storm; the other **31 were separate, deliberate declines**. A week
        of real writing showed the agent nine blocks. The premise — writing
        alone with a partner — is the one thing use did not pick up. What
        the student says about it is the three notes below.
- [x] After the freeze: take from the parking lot below, with the stats in
      hand. Chosen 2026-10-15: projects for notes (1), the one item the
      numbers confirm.

## Parking lot

What is waiting, and only that, in the order it is worth doing; each says
what it needs. New ideas land here first (date, where they came from, what
they need) rather than in code. Cleaned up on 2026-10-17: what is done or
decided against moved out of the way — to the record at the end of this
section, word for word, and to the diary's decisions log.

### Open, in order

0. **The day conversation** (grilled 2026-10-20/21; `docs/agent.md`, "The
   day conversation"): an agent to talk to about the day — the tasks, the
   context, what was written, searchable — in the right pane from anywhere
   (Ctrl+J; Ctrl+Shift+Enter with the block referenced; the seal, moved to
   the header's centre), one conversation a day with a brief carried to the
   next, cross-visible with the block and task conversations, searching
   every folder switched on in Settings and never what is private,
   proposing as the planner does. Slices: (1) the conversation in the pane
   — *built 2026-10-21*: `longhand-agent day`, its own agent
   (`longhand-day.md`), one session a day in the day's state; `DayPane.qml`;
   Ctrl+J, Ctrl+Shift+Enter, the seal at the centre, the date opening the
   sidebar; the morning line; past days read-only; a private day talks
   blind; cross-visibility both ways; `tests/test_day.py` and live checks;
   (2) search — *built 2026-10-21*: `agent/search.py` (folders on or off,
   the daily notes' own always on by default; never private notes or
   blocks, `_Secrets`, other types, identity/money/health/contract/secret
   names, nor what gitleaks flags; IBANs and card numbers masked; withheld
   counted, never named), the agent's `search` and `read` of a file in two
   rounds, Settings → what the agent may search (Ctrl+F), citations as
   links that open a note at its line; `tests/test_search.py`;
   (3) `@` references and proposal cards — *built 2026-10-21*: `@` in the
   day's box lists the note's blocks, narrowing as you type, and points at
   one; the day proposes through the planner's checks into the one ledger
   (`from: day`), each proposal a ◇ card under the answer — kind in small
   caps, the box, the day as a pill, the reason faint — with ↑ onto the
   cards, Enter/Space to do, Del to decline or undo; `tests/test_day.py`
   and live checks; (4) the day's brief — *built 2026-10-21*: the day's
   first run writes each missing brief of the last seven days into
   `days/<date>.md` (once a day, never for a private day, the student's
   corrections applied); every payload carries the last three; Settings →
   what the agent knows lists them, correctable line by line;
   `tests/test_day.py`; (5) its eval cases — *built 2026-10-21*: the eval
   runner knows the day job (said or silent, asking to search or read,
   proposals kept or refused by plan.py's checks, a brief's lines); `eval
   add` joins a later message to its day's first message and the turns
   between; answers are rated helpful or not in the pane (Alt+= / Alt+-, or
   a click), and the weekly review lists the misses with the command that
   makes each a case; six seed cases pass, and the install gate now checks
   `longhand-day.md`; `tests/test_day_evals.py`.
1. **The agent that does things, while the person drives** — designed
   2026-10-17 in a grilling; the whole design is `docs/agent.md`. Checkboxes
   are its environment (structured work, not authored words); who made each
   line is kept in the layer and drawn (the box, ◇, the seal for
   "together"); autonomy per kind of action, all starting at "ask me"; it
   asks when it would have to guess, at most two questions a run; proposals
   and questions are dashboard rows with the app's own keys; a ledger of
   outcomes; its notebook visible and correctable; course documents from
   the Downloads inbox, read in three tiers; a pluggable route to the model.
   In slices: **(1)** who made it (built 2026-10-17) → **(2)** proposals and planning (built 2026-10-17), starting
   with do-dates → **(3)** the notebook, visible (built 2026-10-18) → **(4)** documents (built 2026-10-18: inbox, filing, sidebar, index, reading whole and search) →
   **(5)** the other actions (built 2026-10-18). **Needs from the student:** a new OpenCode
   Go API key (the one in use expired — found 2026-10-17 on the first real
   plan; every agent run fails until it is replaced), and a re-login to
   ChatGPT in opencode before a second model route.
   **The improvement loop, built 2026-10-18** (docs/agent.md): the prompt
   version and model on every run, *helpful / not helpful* on replies, an
   eval set of real runs (cases in the vault), the check before a prompt is
   installed, and a weekly review written when the page opens.
2. **The agent's cheap tiers** (2026-10-14, "the agent's tools" in the
   record). *Self-knowledge*: "how do I add a deadline?" answered from a
   payload section listing what the CLIs and the page can do — static,
   auditable. **Built 2026-10-18:** `agent/manual.md`, written by hand, its
   keys named by action (`{key:deadline}`) and filled in by `manual.py`
   with the student's own keys (Shortcuts.js with keys.json, and
   Hyprland's as they are), so a moved key reads right. A block that asks
   how to do something carries it whole; every other block run names it,
   and the agent can ask to read or search it like a course document. The
   margin prompt answers from it only, the keys exactly as listed, and says
   so when Longhand does not do something. First real answer: "How do I
   move a task to another day?" → the dashboard, `t`, a day in words — a
   do-date, not the deadline. *Observability*: `longhand-agent explain --date D`, answering
   what it saw, said, cost, and why it was silent, from logs, never notes.
   The third tier (internet, tools for the student's agent) cuts against
   principle 3 and stays a decision, not a build.
3. **How far does private go?** — a decision, not a build. A dated checkbox
   in a private note still binds, so its title, project and date are in the
   store, and every payload carries the store whole; calendars shared whole
   make the boundary matter more. Three ways out, in the record; plus a key
   and a visible treatment for the block-level `[!private]` callout.
4. **Structure** — split `Page.qml` (5,822 lines on 2026-10-17, 6,337 by
   the 18th). *First pass done 2026-10-18*: the five sheets beside the note
   — the dashboard, settings, keys, the sidebar, the margin — each in a file
   of its own (`Dashboard.qml`, `SettingsSheet.qml`, `KeysSheet.qml`,
   `Sidebar.qml`, `Margin.qml`), moved by `tools/extract_sheet.py` with
   their bodies unchanged; `Page.qml` is 4,415 lines. Left: the note sheet
   itself (most coupled to the editor), and the logic — bound lines, the
   runner queue — into `.js` libraries with unit tests. Install by symlink
   is out: the Omarchy plugin folder refuses symlinks, so the install stays
   a copy. One deadline-store parser for both plugins, still to do. Before
   item 5.
5. **A project as one continuous page** (2026-10-17, the consistency
   grilling). Every section of a project in one scroll, newest first,
   editable in place, each edit landing in its day's note. Needs writing
   another day's note while it is on screen and finding blocks by identity.
6. **A sent block keeps its conversation through word edits.** A tick, a
   date or a priority keep it since `7740b51`; changing the words still
   detaches it. Identity in the layer (its last words and place, followed
   through every edit in the page), never a tag in the prose. *Done
   2026-10-18*: `plugin-page/Threads.js` pins an answered block's
   conversation to its first line and carries it through every edit with
   authorship's machinery (`Authorship.carryBy`, now for any line), kept by
   the lines' words in `threads.json`; the runner reads it, so a chat tells
   the model what the block reads now and the open pass does not take the
   reworded block for a new one. An edit made in Obsidian still lets it go,
   as it does a line's authorship. `tests/tst_threads.qml`,
   `tests/test_threads.py`, and the live check that used to assert the
   opposite.
7. **The deadline popup's tick** — the same sound and feel as the page's
   (its own plugin, `plugin-deadline`); its day is already written by the
   check. *Done 2026-10-18*: the page's sound (the same file, written by
   `tools/make_tick.py` for both; off when the page's Settings turned it
   off, never under Do Not Disturb, never on reopening), and the row's mark
   pops, the strike is drawn left to right, the row glows. The popup's bar
   colours had the Qt 6.12 `Color` problem too, fixed. `tests/test_popup.py`.
8. **The logo follows the theme on the launcher** (the page's seal already
   does), and the live launcher looked at once. `docs/brand/README.md`
   tracks both. *Built 2026-10-18* (`tools/theme_icon.py`, a `theme-set`
   hook); the live launcher after a real theme change is still to be seen.

Small, when passing by:

- ~~**Making a project**~~ *built 2026-10-22* (a short grilling that day:
  where it starts, what it asks, what the agent may change, the agent's
  part). A project was a file in the agent's `knowledge/projects/` that
  only the agent or a hand-written file could make. Now the person makes
  one, the runner writes it (`longhand-agent project --tag T --name N`,
  `agent/projects.py`): from the note, `@name` or a new `#tag` when nothing
  matches offers "+ make #x a project" (`@`: Enter; `#`: ↓ then Enter, so
  Enter stays a new line), then asks "name?" under the line; from the
  sidebar, "+ new project" takes "Name #tag" (the name's words when no
  tag). Never over one that exists. The agent may add to a project's file
  but never rename or re-tag it (its H1 and `Tag:` put back by the runner),
  and never makes one: a new `project` proposal, a question only, accepted
  like any card. `tests/test_projects.py`, `tests/tst_tags.qml`, 11d' and
  12i in `tests/page/run.py`.
- ~~**Tag suggestions while typing**~~ *done 2026-10-18*: `#` and a letter
  offer the tags that exist — the projects', then those written in the
  notes, most used first (`Tags.js`) — in the `@` list; never for a lone
  `#` (a heading on its way), never once the word is a tag already.
- ~~**"on" as a cue word**~~ *done 2026-10-18*: "conference on the 8th of
  Feb" binds — but only when a weekday or a month follows "on", so "work on
  part 3" and "focus on today" stay words (`Bound.js`, `tests/tst_bound.qml`).
- ~~**The calendar and the open pass race**~~ *fixed 2026-10-18*: the open
  pass and the day's plan wait for the fetch the opening started (at most
  20 s); the live suite checks the order with a slow fetch.

Later, by the student's own word (2026-09-17: "explicitly later"):
**study mode** (14.8; the Anki hook of GitHub issue #7 belongs here — it
was closed with the pomodoro issues on 2026-10-17, reopen it when this
starts), **phone capture**, external reading; and from the old parked
list, analytics (`history`) and a daily counter.

### Not built, on purpose

Kept here (2026-10-19) so "what could we build next?" has its answer:
this list, with *Open, in order* above. Each says why it waits.

- **A block-selection mode on Esc** (Notion's: Esc selects the block,
  arrows move between blocks, Enter edits again; 2026-10-23): Esc is the
  only way out of the overlay, a mode would cost presses to leave, and
  Ctrl+A's second press, Ctrl+Shift+Up/Down, Alt+Up/Down and Ctrl+Enter
  already do what a block selection is for. Revisit if those prove short.
- **By design, not a gap:** the agent never rewords the person's boxes,
  never writes prose, and never raises its own autonomy (it may only
  suggest it, at 9 of the last 10 accepted).
- **How far does private go** (item 3 above) — a decision for the
  student, not a build: a dated box in a private note still binds, so its
  title and date reach the payload with the deadline store.
- **The agent's third tier** — the internet, tools for the agent — cuts
  against principle 3; a decision, not a build (item 2 above).
- **A second model route** (`codex exec`, the APIs; `docs/agent.md`,
  "Reaching a model") — when a second route is wanted.
- **Autonomy per project** — per kind of action only, for now.
- **The rest of the Page.qml split** (item 4): the note sheet, the logic
  into tested `.js` libraries, one deadline-store parser for both plugins.
  Install by symlink is out (Omarchy refuses symlinks).
- **A project as one continuous page** (item 5).
- **Later, by the student's word:** see the paragraph above (study mode,
  phone capture, external reading, history, a daily counter).
- **Small gaps noticed while building (2026-10-18):**
  - dotted dates ("12.11") are not read, after "by" or "on" alike (`Dates.js`);
  - scanned PDFs (9 of 67 in Downloads) have no text, so the agent cannot
    read them — no OCR;
  - the installed `longhand.pomo` plugin is not in this repo and still has
    the bare `Color` fallback Qt 6.12 broke (only used without a bar).

### Built — to evaluate in use

No work unless they bite; each says what would tell. The first four came
from 2026-09/10 and still stand.

- Whether **"ask"** is the right word for sending a block.
- Whether **"seen, nothing to say"** wants a mark.
- The type's **weight on a light theme**; the trackpad's **`gain`**.
- Whether the **seal as "made together"** reads as a status rather than
  an identity (fallback ◈; `docs/brand/README.md`).
- **The planner's new actions** (slice 5): whether proposals of each kind
  are accepted — the record in Settings → what the agent may do — and
  whether raising one to "do it and tell me" is ever wanted.
- **The planner prompt's stability:** `e11303c0f1` (2026-10-20: steps take
  a slot beside a big, clear box's do-date) passes all six cases in 3 of 4
  full runs; before it, the planner never proposed steps at all. Still
  wanted: an eval case for a deadline *stated in prose* (the 10-19 case
  turned out to be a box already in the store) and one for "looks done" —
  both wait for notes that have them. Its successor `c61d50c330`
  (2026-10-22, the `project` proposal) passed its four cases in one run.
  The day prompt `de82d8480d` (the same change) failed
  `day-seed-email-date` once (it asked which date was meant instead of
  proposing one), then passed it twice and all six together: watch it.
  Still wanted: an eval case where a project proposal is the right answer.
- **Deadlines #d10 "author response" and #d25 "Proposal of version 1"**
  were ticked done on 2026-10-16, a second apart, two months early: a slip
  or a test? If a slip, reopen them in the store — since 2026-10-20 the
  planner never proposes a deadline the store already has, open or closed.
- **The inbox's class-time match:** anything downloaded during a class
  looks like that course's — watch for wrong filing proposals.
- **A deadline's date history** (2026-10-23, from the student trying to
  reschedule the one overdue task through the agent): until then a moved
  date overwrote the old one, so a deadline moved and then met counted as
  on time. `longhand-check` now keeps each deadline's first date and every
  move (from, to, when) in the ledger, once both the line and the store
  hold the new date; the line keeps one `📅`, as docs/tasks.md requires.
  The dashboard row says "moved twice, first due 20 Oct"; `stats` counts
  on time by the first date, closed after a move, and moves later. History
  starts 2026-10-23: every earlier date counts as its first. What would
  tell: whether the postponements per course say anything the student acts
  on. Not recorded, on purpose for now: who moved it (note, dashboard,
  popup) and why — "the course moved it" and "I put it off" look the
  same; tag a move only if the numbers turn out to need it. Whether the
  agent may propose moving a `📅` (outside its reach, docs/agent.md) is
  still the student's call; with this, such a move would at least be on
  the record.
- **Talking with the planner** (2026-10-23): both real talks until then
  (10-20, 10-23) came back as a plan, `{"proposals": [], …}`, shown as
  "(nothing to add)" — the planner's prompt ends in the plan's format and
  the talk's payload opens with a whole plan. Now the talk's format is
  said again at the payload's end, a plan for an answer is asked for once
  more in the same session, and a second one is said as that; when asked
  for what it cannot do (a `📅`, the box's words, a tick) it says whose
  act it is and the key. Talks are an eval job of their own: the two
  failures are cases (`talk-overdue-due-date`, `talk-test-mark-done`),
  2/2 on `gpt-6.1-sol`. Its instructions live in code (`TALK_MESSAGE`),
  so the prompt version does not change with them — watch the next
  talks. Also since: a do-date or deadline proposed for a day now past is
  moot, and the page will not accept one.
- **The manual's how-to detection** (`manual.asks_how`) is generous on
  purpose: watch for answers that should have used it, or the reverse.
- **A conversation through word edits:** the trade is that a reworded
  question no longer gets a fresh answer — is that right in use?
- **"on" as a cue, and the `#` tag list:** does "on" bind what it should
  not; does the list help or intrude?
- **The notebook's corrections** are enforced by exact words: watch for a
  forgotten line coming back paraphrased.
- **Not yet seen by eye:** the launcher's icon after a real theme change
  (its tile disappears on the theme's own surface); the deadline popup's
  tick, its sound and feel.
- **The improvement loop:** whether replies get rated, and whether the
  weekly review earns its place.
- **Talking about a proposal** (built 2026-10-20, `docs/agent.md`): Enter
  on a proposal, a question or a thing done opens the margin beside the
  dashboard (Alt+→ on any task: the agent summoned to think it through); the planner answers
  on its own payload, may revise, and an agreement settles it. Watch: does
  the planner settle only when you both agree (it reads your words — the
  one place it decides an outcome)? Is one conversation per task (the margin's
  and the planner's merged, shared by the boxes under it) enough context, or
  too much — and does a long one want trimming? The conversation
  instructions are in code (`TALK_MESSAGE`), not in a prompt file, so they
  have no eval cases yet: add `talk` cases once there are payloads.
- **The day's conversation (slice 1, 2026-10-21):** is it opened (the
  `day` and `seal` counts in the usage log), and for what? Is the pane's
  width enough beside the note, and is the morning line welcome or noise?
  Does a whole day in one session stay fast, and are its answers grounded?
- **The day's eval cases are seeds** (2026-10-21): six, from a throwaway
  vault with made-up notes — a do-date grounded in the note, a date past
  its due refused, a brief, a search, a "how do I" read from the manual,
  "the one thing" without proposals. All pass. Replace them with real
  conversations: rate an answer "not helpful" in the pane (Alt+-), and the
  weekly review names the `eval add` command for it. Are the cards proposed
  only when the conversation calls for them, and do the briefs read right?
- **The day's search:** is it used, and does it find what you meant (its
  queries are in the turn: `searched`)? Is keyword search enough, or do
  you miss notes that say the thing in other words? Are the defaults —
  Daily, Studies, projects, Reference, Career, Archive on — right? The
  first real question (2026-10-21, a throwaway vault) took four searches
  and one whole note, and cited both lines it used.
- **The talk feature's live check "the question settled, its row gone"**
  failed once (2026-10-21) and passed the next run: watch it.
- **The calendar's live checks "…is fetched at once"** failed together
  once (2026-10-21, the calendar saying it had none yet) and passed the
  next run: watch them.
- **Making a project** (2026-10-22): whether the `#` row ("+ make #x a
  project", only for a tag written nowhere yet) is noise while typing new
  tags, or the right nudge — and whether the sidebar's name-derived tag
  (`master-thesis`) is ever kept, or always replaced by a typed `#tag`.
- **The agent's project proposals** (2026-10-22): whether it proposes
  them at all, and whether the ones it does are accepted (Settings → what
  the agent may do, "propose a new project").
- **Ctrl+A as a ladder and Esc letting go** (2026-10-23, from Notion's
  and Craft's select-all): line, then block, then the note; Esc drops a
  selection before it closes the overlay. Watch whether the extra Esc to
  leave after selecting is felt as a cost.
- **Three panes, the bracket keys, the pointer following** (2026-10-23,
  docs/navigation.md; the bracket layout is the student's): `Ctrl+[ \ ]`
  are the sidebar, the middle and the agent's pane, Alt+←/→ only move, Esc
  backs out one level and gives the keys back where they were, an accent
  frame is around the pane with the keys, and the pointer follows the
  selection. Watch: whether the days on `Alt+[ ]` are found (they were
  `Ctrl+[ ]`), whether anyone misses Alt+→ opening the margin (yes: back
  on 2026-10-25, in the note at the right edge), and whether
  "every selection" for the pointer is felt as help or as the mouse being
  taken (the `pointer` counts in the usage log).
- **A live check that failed once** (2026-10-18, then passed four runs):
  the "when?" box pushing the next line down (11j in `tests/page/run.py`).

### Decided against

- **Multi-language** cue words and prompts — refuted 2026-10-15 by the
  counts it waited for (61 English blocks to 3 Portuguese). Revisit only if
  the ratio moves.
- **Focus mode, and the pomodoro in this tool** — refuted 2026-10-15: no
  sessions in a month. `pomo` stays as the deadline CLI; GitHub issues #1–#8
  (the pomodoro era) were closed with this, pointing here.
- **Pi as the agent's harness** (2026-10-14) — everything it adds over
  opencode lives in the layer this agent switches off.
- **Classes in the page's calendar** (2026-10-17, the student's call) — the
  sidebar's next session and the agent only, for now.

### The record

Everything below is done, settled or superseded, kept as it was written on
the day; the reasoning is in the diary's decisions log.


Everything waiting, in one place. The freeze decided the order on
2026-10-15 with the stats above; new ideas still land here first (date,
where they came from, what they need) rather than in code.

**From the consistency grilling, 2026-10-17** (`docs/tasks.md`):

- **A project as one continuous page.** Every section of a project in one
  scroll, newest first, editable in place, each edit landing in its day's
  note — the Tana feel on markdown. Needs writing another day's note while
  it is on screen and finding blocks by identity, which the consistency work
  builds; after it.
- **A sent block keeps its conversation through edits.** Conversations are
  keyed by a hash of the block's words, so editing one word after asking
  detaches the reply. Identity in the layer (its last words and place,
  followed through every edit in the page), never a tag in the prose.

**From the week of classes, 2026-10-15** (the student's own three, on
lifting the freeze; the numbers above cannot see any of them):

- **Checkboxes have no depth.** As soon as a checkbox exists it tends to
  become a task with a deadline, so it has to be one of two things: a
  subtask of something that gives it its meaning, or self-contained enough
  to still mean something in a few days. Otherwise it is random text that
  will not be understood later — which is the 2/22 in different words.
  **Shaped 2026-10-15**, after an evening on it: three kinds of box told
  apart by one rule, lifespans for each, and a dashboard to meet them in.
  The design is item 2 of the order below; the reasoning is in the diary's
  decisions log. Nothing built yet.
- **The agent knows nothing, so it feels useless.** Asked a question, it
  has no access to anything and answers from nothing. It needs to get
  smarter and smarter. *First step done 2026-10-15:* a block sent from
  under a `# Course #tag` heading carries that project's sections of the
  earlier daily notes (recent ones in full, older named only) — that
  project only, private parts and `agent: false` days out, the open pass
  untouched. Still open, in the order they are worth: the timetable (item
  2) so it knows when the next session is; what the CLIs can do, for "how
  do I add a deadline?"; tier 1 observability. This is the live end of "the agent's tools" below,
  and the stats' 31 declines are its symptom: the student stopped offering
  because there was nothing to gain. Note the allowlist is the *design* —
  the payload is deliberately narrow and logged before inference — so
  "smarter" has to mean a wider allowlist and better local context
  (curriculum, projects, the timetable, its own history), not a shell and
  not a `read` tool. Tier 1 and 2 of that item are the cheap half.
- **The agent needs a way in that is not a keyboard shortcut** (2026-10-15,
  the student's answer when asked whether the send prompt should go): "this
  is a core feature that should not be only under a specific trigger."
  **Done the same day:** the header holds **ask** — outside the canvas,
  beside the date, the pin and the agent mark, so no mark goes back on the
  student's words (the gutter was the alternative and lost on exactly that
  ground). It sends the block the cursor is in, dim when that block carries
  a sign, faint when it does not, and says why when asked anyway. With it
  there, the send prompt went: nothing interrupts writing to offer the
  agent any more. **The second half, 2026-10-15 evening:** a pass in flight
  is now visible where the work is — the block's gutter mark carries a
  light travelling down it from the moment the student asks until the
  answer is back, and the header's **agent** brightens for the same span.
  Marked at the *ask*, not at the launch: a send waits for dates to bind
  and for the note to be written, and "did that go?" is precisely what the
  mark answers. A mark that moves is still thinking; a mark that rests is
  answered; the two are never the same shape. Left: whether the word "ask"
  is the right word once it has been lived with.
- **The agent had not been working at all** (found 2026-10-15, while
  answering "is the connection with opencode actually up?"). It was not:
  opencode 2.0.29 dropped `--pure`, `--dir` and `--variant`, printed its
  usage to *stdout* and exited **0**, so every pass of the day died and the
  page looked exactly as it does when the agent has nothing to say. Three
  fixes, in the order they matter: the invocation (`--standalone`, the
  working directory passed as the process's own, the variant riding on the
  model as `provider/model#variant`); a run that produces no text, no
  session and no error is now *recorded* as a failure and the page says so
  in a line under the cursor; and the invocation is a tested contract, not
  an implementation detail — `tests/test_agent.py` asserts the flags, the
  empty working directory, and that no flag opencode no longer knows is
  passed. The ledger also had to change: opencode stopped reporting cost in
  the event stream, so each pass reads its price back from its session
  (`opencode session export`), best effort — a pass that happened is never
  failed for want of its price. Verified live: a real `chat` pass came back
  with a reply, $0.0021, 7357 tokens.
- **Staging is not a useful state, and its mark is confused with the
  running one.** Once the student has decided *not* to send a block, being
  shown that it still "could be sent" is noise; `Ctrl+Enter` already sends
  a block on demand, so staging adds nothing a key does not. The hollow
  staged mark also reads as the loading indicator, which is a nice thing in
  itself. **Done 2026-10-15** (a fix): staging is gone — no `staged` state,
  no hollow gutter mark, nothing held between the prompt and the send. A
  block is sent from where the cursor is with `Ctrl+Enter` whenever the
  student wants it, asked about or not, and the only mark on the student's
  words is a reply (accent until read, dim after). A ticked box is now a
  sign of its own (`triggerFor`), so the tick trigger survives staging's
  removal. Left: whether the send prompt itself should stay, given it was
  answered yes once against no 41 times — the student's call, not the
  numbers'.

**To discuss, evening of 2026-10-12** (from a day of real use; each one is
a fix or a feature to decide first):

- **The veil hurts reading.** Done 2026-10-12 (a fix): the veil is gone;
  the student's words are always at full strength, and the gutter marks
  that were already there carry the agent's state (hollow staged, filled
  reply, accent until read). Left for after the freeze: whether "seen,
  nothing to say" needs any mark at all (a hairline while the cursor is in
  the block?).
- **The measure.** Done 2026-10-13 (a fix): a line holds at most 72
  characters of the page's own type, in the window and on the overlay
  alike (`measureChars`, counted with the font's average character width),
  so zoom keeps it: zoomed in, the column widens with the letters; zoomed
  out, the space beside it grows; a window narrower than the measure wraps.
  In the window the column is centred beside the sidebar, and an open
  margin moves it left only as far as it must. Left: a proportional face
  for prose (the page draws in the system monospace).
- **Vertical rhythm.** Done 2026-10-12 (a freeze exception the student
  asked for): the space above each row comes from what it is and what came
  before (Rows.js `SPACE`, in body ems) — headings 1.75 / 1.4 / 1.1 / 0.9
  above and 0.35 below, list items 0.25, lines of text 0.25, a change of
  kind 0.5, the lines of one quote / fence / frontmatter 0. Blank lines are
  one paragraph's space (0.75) however many, and count towards a heading's.
  Left: lines that wrap inside one row keep the font's own line height
  (~1.3) — Qt's TextEdit has no line-height setting.
- **Numbered lists don't nest.** Fixed 2026-10-12: Tab / Shift+Tab move an
  item into the kind of its new level (after "1." a bullet moved out is
  "2."; under bullets a number moved in is a bullet), a first child that is
  numbered starts at 1, and the list's numbers count on within each level
  (Rows.relist). A marker typed into an empty item replaces it ("2. " then
  "- " is a bullet).
- **Trackpad scrolling felt slow.** Fixed 2026-10-13: Qt's Flickable moves
  1:1 with the fingers and stops dead on lift, where the rest of the
  desktop scrolls further and glides (and Omarchy scales all touchpad
  scrolling by 0.4). TouchScroll.qml takes the two-finger scroll on the
  note, the margin and what's next: `gain` 2.0 while moving (1.6 at first; "a bit faster"), the
  Flickable's own glide after a quick lift; a mouse wheel is untouched.
  Tune `gain` (and the glide's deceleration) from use.
- **The "deadline?" prompt lost to list writing, and to the agent.** Fixed
  2026-10-13 (the student counted two broken parts at odds as one fix):
  the prompt is gone. Dates.js reads a checkbox's date in the page as it is
  typed — the same phrases `pomo deadline when` reads, the same way
  (tst_dates.qml), handing the store an exact `YYYY-MM-DD HH:MM` — so the
  date lights up with its pill pending, and leaving the line binds it, as
  Todoist does. Backspace right as it lights up, Ctrl+D, or Ctrl+Z after
  the binding keep it words (the last removes the deadline it made). Only a
  line typed in is recognised: an old note's "by friday" stays words until
  Ctrl+D. A list is staged for the agent only when the deadline queue is
  idle, so the agent sees its dates as deadlines and proposes none — the
  root of the 2026-10-12 tangles and duplicates. Found on the way: the page
  read the cursor's line a moment before the editor's text caught up, so a
  keystroke at a line's end looked like leaving the line (the prompt storms
  in usage.tsv); the line is now read once the edit is whole. Still open:
  "on" as a cue word ("conference on the 8th of Feb").

**Proposed order** (unless the numbers say otherwise):

1. ~~**Projects for notes** (14.6i)~~ — **done 2026-10-15**, the first thing
   off the lot; see the step above. Left for later: the sections as one
   readable run instead of a list to jump from, and a project's deadlines
   beside its notes. Class notes findable by course without
   knowing the date. Convention in use since 2026-10-12: one `# Course #tag`
   H1 per class, notes under it with H2/H3…, course deadlines carry the same
   tag. Rule: a tagged heading claims everything under it until the next
   heading of the same or a higher level — an H2 never ends an H1. First
   version: from the sidebar's projects, every section of that tag across
   days, newest first, opened in place.
2. **Tasks that live, and a dashboard to work them** (designed 2026-10-15;
   Basecamp's Fizzy read for its archival rule). Three layers, in the order
   they are worth:
   - *Depth, with no new syntax.* Markdown already carries both hierarchies
     and the page already edits them: indentation under a box is a subtask
     (`Rows.relist`), and the heading chain is project › section (the tagged
     H1 rule of item 1). The store records neither. Binding should keep the
     **heading path** and the **parent box's id**, so a bare box — no
     project, no parent — becomes detectable, and every view can show a task
     where it came from: "Design Theory › Essay 2 › draft intro" instead of
     "draft intro". That answers "random text I will not understand later"
     by display, rather than by asking the student to write better boxes.
     **Done 2026-10-15:** one grammar for a checkbox line —
     `plugin-page/Task.js` with its Python twin `agent/task.py`,
     cross-checked over 32 lines and 9 notes by `tests/test_task.py`. It
     replaced four regexes in the agent, reads the whole Obsidian Tasks
     vocabulary (📅 due, ⏳ the do-date, 🛫 ➕ ✅ ❌, 🔁 recurrence, the five
     priority glyphs, `[est:: ]`, `^dN`), tells the three kinds apart, and
     carries each box's heading path, project, parent and depth. Two things
     the old regexes got wrong came out with it: a checkbox inside a fence
     or the frontmatter counted as a task, and the payload's intentions
     section read days marked `agent: false`. `stats` now counts
     commitments (a box with a date or a priority) apart from note boxes,
     so the number the tool is judged by survives the new rule.
   - *Lifespans.* One rule tells the kinds apart: **a box becomes a task the
     moment it is given a date or a priority, and stays a note box
     otherwise.** A **note box** is thinking, disposable, and carries 7 days
     of silence; a **task** 30; a **deadline** never decays by silence,
     because it is judged by its date — but one whose date passed with
     nothing done to it for a fortnight is auto-**hidden**, the state the
     store already has. Silence is reset by any touch: edited, ticked,
     rescheduled, named again in a later note, or kept on purpose. Two rules
     keep it humane. The decay is **in the view, never in the file** — an
     old note is history, so the line is not rewritten and stays findable
     through its project, which also makes archival reversible for free. And
     **nothing goes without first appearing as about to go**: a dim
     countdown on the row through the last quarter of its life (Fizzy warns
     at 75% of its 30 days, and turning the knob down touches every card so
     a settings change never evicts anyone). The panel's `recent = age < 7`
     with older days folded is already a crude one-period version of this.
   - *The second encounter.* Three verbs an old box does not have today:
     **when** (give it a do-date), **not now** (postpone by hand), **drop**
     (`- [-]` with a cancelled date). Ticking it is a lie, ignoring it is
     the 2/22, and those are currently the only two options.
     **Done 2026-10-15:** the dashboard, full width, `Ctrl+T` (it replaces
     the margin's narrow what's-next). Rows group by what they ask of you —
     DUE, DOING (a do-date), TO SCHEDULE (a priority and no day) — and then
     by project, each row carrying its heading path, its dates and when it
     was written. The verbs: **Enter** opens the line in the note,
     **Ctrl+Enter** closes it out, **t** asks when in words (read by the
     note's own `Dates.js`, written as `⏳ YYYY-MM-DD`), **p** walks the
     three priorities, **Del** drops (`- [-] … ❌ <day>`), **Ctrl+Z** takes
     a tick or a drop back. Every edit is surgical — `Task.js` keeps the
     words byte for byte and rebuilds only the metadata tail — and lands in
     the day the line was written, whether that is today's note in the
     editor or another day's on disk. Enter in the deadline popup opened
     *nothing* and meant *done*; it now opens the line there too (`d` still
     closes out), so one key means one thing across the page, the popup and
     the dashboard. **Not now** (`s`) and `g` (grade) came with the
     lifespans, 2026-10-17. Tests: `tests/test_task.py` for the line editing,
     `tests/page/run.py` for the dashboard driven live.
     **Drawn 2026-10-15**, after the first version read as a wall of data:
     the dashboard borrows the note's own idiom rather than inventing one.
     A date is a pill as it is in the note (outlined for the day it is
     owed, filled for the day you mean to work on it, urgent when it is
     late); a box is the note's checkbox, clickable; priority is a mark
     beside the box, not a word in the row. Bands carry the course's own
     name with its tag beside it — the curriculum's name, else the heading
     the notes themselves use — in the theme's heading colours, one for the
     three bands that say what a row asks of you and another for the
     courses. The dated sections are banded by month. Under the words, in
     faint, the section it was written in and how long ago, with the course
     dropped when the band above already says it. A row's space comes from
     what it is, as `Rows.js` does for the note, and the column is 1.45
     measures wide and centred, because a list is wider than prose but not
     as wide as the wall.
     **Lifespans built 2026-10-17:** the silence clock lives in the layer
     (`agent/lifespan.py`, `silence.json`), the note is never rewritten,
     and what runs out waits folded under **not now** with whatever `s`
     put there by hand; `r` keeps a box, `g` grades a deadline, and a
     deadline open a fortnight past its date steps aside through
     `longhand-check`. Every row counts down through its last quarter, and
     on the clock's first day nothing past its life went without that
     countdown. Reasoning in the diary's decisions log; tests in
     `tests/test_lifespan.py`, `tests/test_check.py` and the dashboard
     section of `tests/page/run.py`.
   Also settled: **two dates, due and do.** The due date is a fact you
   receive; the do-date is the decision students avoid, which makes it the
   agent's job — workload across the next fortnight by project, proposed
   do-dates on the empty days, and a proposed **effort estimate**, offered
   and accepted rather than asked for, because nobody fills those in. All of
   it is arithmetic over the deadline store and the task list, both already
   in the payload; the timetable (item 3) is what turns "the 24th is free"
   from a guess into a fact.
   The line keeps the Obsidian Tasks vocabulary it already half-speaks (📅
   due; then ⏳ / 🛫 for the do-date, 🔁 recurrence, 🔺⏫🔼🔽⏬ priority, ✅ a
   done date, `- [/]` and `- [-]` as states), so a note still reads in
   Obsidian on the Mac and as plain text anywhere. Richness on disk, quiet
   on screen: the page draws its own rows, so metadata appears as marks and
   pills rather than emoji soup.
   **The dashboard** is full-screen, and the pinned twin of `SUPER+ALT+D`
   the way `SUPER+ALT+\` is of `SUPER+ALT+=`: the popup is the glance, the
   dashboard is where the work gets done. Marking something done there ticks
   the line in the daily note — which means the dashboard has to be a
   **shape of the page**, because the page is the one writer (`longhand-agent
   tasks` is read-only for exactly that reason). The gathering already
   exists: `longhand-agent next` returns every unticked box in every note
   ever, and `buildTaskRows()` already assembles deadlines, boxes by day and
   what the agent raised into one list. What it needs is context on each
   row, grouping by project and by week, the three verbs, the entropy
   countdown, and **one verb alphabet** shared with the popup (Enter go,
   Space tick, `t` when, `p` priority, `s` not now, `g` grade, `x` drop —
   today Enter means done in the popup and go-to in the panel). In the note,
   language; in the dashboard, keys — with rescheduling the one place that
   takes typed words, parsed by the note's own `Dates.js`.
3. **Timetable sync** (2026-10-11) — the project list follows the real
   timetable instead of the copy written on 2026-10-11. Pull, not push:
   when the page or sidebar opens and the last copy is older than an
   interval (an hour?), the runner re-fetches the university's `.ics` feed
   (with "unchanged" checks, so it costs nothing when nothing moved), keeps
   it in the state folder, and matches courses by timetable code
   (`M_IC_IntSem_W26`). The course list moves out of the agent's knowledge
   into a file the model cannot rewrite, so an agent edit can never drop a
   schedule; today's session lines stay as a fallback. **Built
   2026-10-17** (`agent/timetable.py`, `tests/test_timetable.py`): the
   sidebar's next session and the agent's next two weeks follow the feed;
   classes stay out of the page's calendar for now. Set in the page since
   the same evening: **Settings → Calendar** (`Ctrl+,`) takes the address,
   fetches it at once and says which courses it found. First real link
   (2026-10-17): IT:U's `ical-stream.php` token link redirects to its
   sign-in, so it does not work yet — **needs** a link the portal serves
   without a login (a subscribe link, or a renewed token).
4. **Multi-language** — cue words ("bis Freitag", "até sexta", "para el
   viernes") and the page's prompts in DE / PT / ES, at no cost in speed.
   *Refuted 2026-10-15 by the counts it was waiting for* (61 English blocks
   to 3 Portuguese). Stays here; revisit if the ratio moves.
5. **Focus mode** (14.7) — where the pomodoro comes back in (resurface it
   then, per 2026-10-11). *Refuted 2026-10-15*: 0 sessions in a month. The
   question to settle first is whether the pomodoro belongs in this tool at
   all, not how to dress it.
6. **Structure** — split `Page.qml` into tested modules (bound lines,
   runner queue, what's next); install by symlink so the repo is the
   install; one deadline-store parser for both plugins.

**Not ordered yet:**

- **How far does private go?** (2026-10-15, from asking what the new toggle
  actually covers.) The toggle is the whole note; a `> [!private]` callout is
  the block. The model and its edges are written up under "Privacy" in
  `docs/diary.md`; the one that needs a decision is the first: a dated
  checkbox in a private note still binds, so its title, project and date are
  in the store, and every payload carries the store whole. Three ways out,
  none obviously right: a private note binds nothing (you lose the deadline
  you meant to keep); it binds but the deadline is marked private too and
  left out of the payload (the store grows a privacy flag, and "what is
  due?" stops being one list); or it stays as it is and the rule is stated
  plainly — your words are private, the commitments you make are not. Also
  waiting: a keystroke and a visible treatment for the block-level callout,
  which is typed by hand today and reads as a callout rather than a
  guarantee.

- ~~**A face for prose** (2026-10-13)~~ — **done 2026-10-15.** The page is
  set in iA Writer Quattro S (from `ttf-ia-writer`, already on the machine),
  chosen against Duo S and the monospace by rendering a real class note in
  each: Quattro stops headings wrapping and carries noticeably more words a
  line. Code and frontmatter keep the monospace. `font` / `codeFont` in the
  config name others; the default is the first face present of Quattro S,
  Duo S, the shell's own. The measure is now counted on a lowercase
  alphabet (72 characters is 2.8 alphabets) rather than Qt's
  `averageCharacterWidth`, which over-counts capitals on a proportional
  face and is identical for a monospace — at zoom 1 the column went from
  661px to 631px for the same 72 characters. Left: nothing, unless the
  weight reads heavy on a light theme after a day's use.
- ~~**Emphasis, drawn** (2026-10-15)~~ — **done the same day.** The fear was
  that styled spans needed a mapping between drawn offsets and the body's,
  the riskiest change in the editor. They do not: a row with emphasis becomes
  rich text whose *plain* text is the body character for character, with the
  markers in a span one pixel tall and transparent. Qt keeps one document
  position per character either way, so the cursor, the selection, the search
  painting and the bound-line rewriting never learn that anything changed —
  `prefix + body == line` holds exactly as before, and a row without emphasis
  is still plain text and takes no new code path at all. The question the
  entry left open answered itself: the markers are hidden only while they are
  doing a job, so breaking a pair (deleting one `*`) brings them back at full
  size, which is how you see them to edit them. No cursor-dependent reflow,
  no jiggle on entering a line. `white-space:pre-wrap` is load-bearing —
  without it the renderer eats runs of spaces and the trailing space of a
  line being written, and every offset after them is off by one; the test
  that proves the drawn text strips back to the body covers it.
  What this also found: the page was heavy because the iA Writer families
  declare the same weight for every style, so Qt handed back the **Bold**
  file for a normal weight — `**bold**` had nowhere heavier to go. Naming
  the cut (`font.styleName: "Regular"`) fixes both, and the contrast
  softening of the morning (a fifth back from the theme's maximum) went
  with it: it was treating a symptom, and with the real Regular in place it
  only cost legibility.
- ~~**Hidden markers are still editable, and Backspace eats them**~~ — **fixed 2026-10-15**
  (`60c5664`, a pair of markers is one thing to the cursor). (bug,
  2026-10-15, the student's, the evening emphasis landed). A marker drawn to
  nothing is still a character: the cursor can stand between the two stars
  of a pair and Backspace takes one. Measured, from the end of each:

  | from | Backspace 1 | 2 |
  | --- | --- | --- |
  | `a **bold**` | `a **bold*` — **markers appear** | `a **bold` |
  | `a *it*` | `a *it` — markers appear | `a *i` |
  | `` a `c` `` | `` a `c `` — markers appear | `` a ` `` |
  | `a ~~gone~~` | `a ~~gone~` — markers appear | `a ~~gone` |
  | `a ***both***` | `a ***both**` — *nothing visibly happens* | `a ***both*` — markers appear |

  So one keystroke changes nothing you can see except make the markdown
  pop into view, and on `***both***` the first one silently demotes bold
  italic to bold with no feedback at all. Walking right with the arrow keys
  costs two dead presses at each boundary (`a **b** c`: 2→3→4 crosses the
  two hidden stars).

  The rule it comes from was a choice made the same evening — markers are
  hidden only while they are doing a job, so breaking a pair brings them
  back "which is how you see them to edit them". Lived with for an hour,
  that is wrong: it makes an invisible character deletable and turns an
  ordinary Backspace into a mode change.

  **Wanted** (the student's own words): never see the `**` again once they
  are in. To take emphasis off, either delete the whole emphasised text or
  select it and press the key again. Which means the pair has to behave as
  one thing — the cursor steps over it rather than into it, Backspace at
  the outer edge takes the pair (or the last letter, never a marker),
  Delete likewise, and a selection's ends snap outside it. That is cursor
  arithmetic on top of the drawn row, not a change to how it is drawn, so
  `Emph.js` and the one-position-per-character guarantee stay as they are.
  Test every marker and the nested combinations (`**`, `*`, `` ` ``, `~~`,
  `***both***`, `**bold *and* italic**`), since they already differ.
- ~~**Asking an answered block again**~~ (bug, 2026-10-15, the student's) —
  **fixed the same day.** `Ctrl+Enter` on a block that already carried an
  answer ran the whole pass again. Two things made that clearly wrong rather
  than merely wasteful: a block's identity is the fnv1a of its *text*
  (`Blocks.js`), so a block that still carries its answer is text that has
  not changed — the second pass sends the identical payload; and `apply()`
  does `rec.update({... "reply": ...})`, so the second answer *overwrites*
  the first. It was not two opinions to compare, it was paying ~7k tokens to
  destroy one. Now the word in the header reads "reply" and the key opens
  the conversation on that block, cursor in the box — which continues the
  opencode session the first pass opened, so only the new message travels.
  No escape hatch for a forced re-run, deliberately: edit the words and it
  is a new block that runs as usual, and if the answer was poor the thing
  you want is the follow-up, not the same question.
- ~~**A sent chat message vanished until the answer came**~~ (2026-10-15) —
  the turns were read from the day's state file, which the runner writes
  only when the pass is done, so the box emptied and nothing appeared for
  the length of a run. The page now holds the turn it just sent and draws it
  at once, with *thinking* under it (breathing, and counting seconds after
  four of them — the difference between a slow pass and a hung one), and
  lets go of the held turn when the runner's own copy arrives.
  That uncovered a real one underneath: **a binding is not refreshed until
  after the handlers of the property it depends on have run**, so anything
  reached from `AgentState.onStateChanged` that read the `blocks` binding —
  the chat settling, `checkAccept`, the unread count — was looking at the
  state *before* the one that had just arrived. It showed as the sent
  message drawn twice, and only sometimes, because any other read of
  `blocks` in between would refresh it. `record()` and `recount()` now read
  `state` directly. Worth remembering next to the `advanceWidth` lesson:
  that one was a dependency that was never captured, this one is a captured
  dependency that is not yet up to date.
- **Tag suggestions while typing** (idea, 2026-10-11) — typing `#` offers the
  tags that exist (the projects list), so a new tag is a choice, not a typo.
  The sidebar list is the first step; this would be the stronger guard.
- **The agent's tools: observability and onboarding** (2026-10-14, from
  asking whether the loop needs a harness of its own) — it already runs
  inside one: `opencode run --pure --format json --agent longhand`, with
  every tool and permission denied in `agent/opencode/longhand.md`. Pi
  (pi.dev, MIT) was weighed as a replacement and rejected — everything it
  adds over opencode (TUI, extensions, skills, session trees) lives in the
  layer this agent switches off, so it would be a new dependency for no new
  behaviour. The question worth keeping is the opposite one: use *more* of
  the harness, so whoever is onboarding can ask what the software does and
  so the loop can be understood under the hood. `docs/diary.md` already
  left the door open ("adding tools later is one line in the agent
  definition"); three tiers, to decide separately:
  1. *Observability* — a second agent definition (`student-dev`) with
     tools, pointed at the repo and `~/.local/state/longhand`, never
     at the daily folder; behind something like `longhand-agent explain
     --date D`, answering "what did it see, what did it say, what did it
     cost, why was it silent" from the payload log, the event stream and
     `cost.tsv`. It reads logs, not notes, so it costs nothing in consent.
     Free of the trade below.
  2. *Self-knowledge* — "what can you do?", "how do I add a deadline?"
     needs a payload section (the CLIs' own `--help`, or a written
     capability list), not a shell. Static, auditable, cheap.
  3. *Internet, and tools for the student agent itself* — the one that
     needs a decision, because it cuts against principle 3. With a `read`
     tool the private-block strip is decorative: `guard_write` guards
     writes only, nothing guards reads, and the acceptance test inspects
     the payload. The payload log also stops being the complete record
     *before* inference — what the model actually read would only appear
     afterwards in `.events.jsonl`, a trace instead of an audit. And
     `websearch` turns a diary line into a query at a third party, which is
     a consent question for a tool meant for other students, not a config
     flag. The shape that survives: the model *asks* for a lookup in its
     structured reply, local code fetches it and puts the result in the
     next pass's payload — the same inversion already used for proposals,
     where local code runs the command and the model never does. Costs a
     round-trip; keeps the audit trail and the student's say.
- ~~**To decide, not build:**~~ — **settled 2026-10-17** by rule 7 of `docs/tasks.md`
  (Enter writes a deadline no line holds into today's note, which makes the
  words the person's). Enter twice on a deadline in what's next writes
  its whole line into today's note — the words are the deadline's title,
  which may have come from an agent proposal. Keep, or offer only to bind an
  existing line? (principle 2, 2026-10-11)
- 14.8 study mode · 14.9 phone capture, external reading.
- From the old parked list: analytics (`history`), daily counter. (Deadline
  entry from the popup was absorbed by 14.4; `.ics` import became the
  timetable sync above.)

## v0.1 Keyboard contract
```bash
pomo toggle  # start/pause/resume
pomo skip    # next phase
pomo status  # JSON for scripts/bar
```

Hypr bindings (the page's keys sheet can take these over into
`~/.config/hypr/longhand.lua` instead, since 2026-10-16; see the README,
"Every key, and moving one"):
```lua
o.bind("SUPER + ALT + P", "Pomo toggle", "pomo toggle")
o.bind("SUPER + ALT + N", "Pomo skip", "pomo skip")
o.bind("SUPER + ALT + O", "Pomo popup", "omarchy-shell longhand.pomo toggle")
o.bind("SUPER + ALT + D", "Deadlines popup", "omarchy-shell longhand.deadline toggle")
o.bind("SUPER + ALT + equal", "Page (today's note)", "omarchy-shell shell toggle longhand.page '{}'")
o.bind("SUPER + ALT + backslash", "Page alongside", "omarchy-shell shell summon longhand.page '{\"shape\":\"alongside\"}'")
```

## Decisions
Longer-form design thinking lives in `docs/student-os.md` (agentic-first, cadence, progress, research).

- 2026-09-05: Hybrid, name omarchy-student, v0.1 = keyboard shortcuts
- 2026-10-16: Renamed **Longhand**. The old name said the platform and the
  audience, not the product; the product is the inversion of "agents drive,
  humans steer": the person writes and owns their threads, the agent lends
  help when called and writes only in the margin. Plugin ids `longhand.*`,
  `~/.config/longhand`, `~/.local/state/longhand`, `longhand-agent`,
  `hypr/longhand.lua`, vault `agents/longhand/`; `tools/migrate-to-longhand`
  moves an old install once and leaves the old paths as symlinks. The GitHub
  repo and the local folder keep the old name for now.
- 2026-09-07: Deadlines are manual-first and stay that way. Import was weighed
  and rejected for now: over years of study the feeds were "nothing but chaotic",
  and the deadlines that drive a study week (read ch.7, draft by Sunday, meet
  supervisor) never live in an LMS anyway. So entry has to be forgiving, and the
  store is deliberately shaped for a later read-only ICS sync — imported items
  would land in a separate file, keyed by UID, never written back, so "sync" is
  refetch-and-replace with no merge logic.
- 2026-09-09: Deadline ids are stable references, not row numbers. Sessions
  will attach to a deadline id (student-os.md D7), so a recycled id would make
  old log lines silently point at a different deadline, and rm+add to fix a
  wrong time would orphan a deadline's own history — hence `set`. Plain
  integers are enough because there is one writer: sync is parked and ICS
  import is read-only into a separate file keyed by UID, so the two namespaces
  stay distinguishable on sight (integer = manual, UID = imported). Revisit
  only if a second writer ever appears.
- 2026-09-05: Calendar parked — direct Google/Outlook sync needs two OAuth flows, too heavy. When revisited, start with local `.ics` export (importable anywhere), not live sync. Next: daily counter.
- 2026-09-15: GitHub for phone capture goes in as an *inbox*, not the truth.
  Reasons: no daemon, no API, no auth on this machine (student-os.md principle
  1); Tailscale on a phone is not free (~9%/day typical, known spikes); and
  GitHub can't push to a sleeping laptop, so the laptop pulls on a timer.
  Priority vocabulary is must/should/could — consequence, not date. Full
  reasoning in the git history of `docs/todo-capture.md` (deleted 2026-09-17;
  phone capture is now phase 14.9 and GitHub is no longer assumed at all).
- 2026-09-16: The plan pivots. Daily note, not a todo app: the agent reads and
  answers, consent is per block, enforced by local code that logs every payload
  before inference. The agent may see drafts and essays but produces nothing
  submittable. The loop runs on the laptop only.
- 2026-09-17: Full design review, all branches settled; `docs/diary.md` is the
  reference. Headlines: own editor in the shell (blank page, Omarchy theme), and
  it comes *before* the loop; the agent never writes the note — the page is the
  only writer and also the only trigger (checkbox, `@`, `?`, tick, page open —
  never a schedule); the model has no tools and returns one structured message
  that local code applies; context is an allowlist, so `human/` is simply not
  on it; store wins over note; project = subject, milestones = deadlines;
  unticked boxes go to a panel, never to a question; suggestions carry evidence
  and dismissals are remembered; no cost caps until usage is known. Syncthing,
  the Mac, and the phone are out of the design for now.
- 2026-10-16: The keys sheet may write into the student's Hyprland config, but
  only into a file it owns. Four ways were weighed: a snippet to paste (the
  sheet writes nothing), a file of its own (`hypr/longhand.lua`) loaded by one
  line added to `bindings.lua`, a managed block inside `bindings.lua`, or a
  file in Omarchy's toggles folder. The own file won. `bindings.lua` is
  touched once, with consent given in the sheet and a backup taken first, and
  never rewritten after that. `omarchy refresh hyprland` leaves the file
  alone, and it is plain to see in `~/.config/hypr/`. A key must hold Super;
  a key taken from another bind is unbound with a note and given back when
  the action moves off it. While the sheet waits for a key, Hyprland sits in a
  submap with nothing bound, which it leaves by itself after 30 s.
