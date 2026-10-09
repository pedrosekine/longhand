# Plan — omarchy-student

## Architecture
- `cli/` — single-source timer + deadline core (bash, no deps)
  - state in `~/.local/state/omarchy-student/` (`state.json`, `deadlines.tsv`, `pomo.log`)
  - commands: start, pause, resume, toggle, reset, skip, status, stats, deadline, report
- `plugin/`, `plugin-deadline/` — thin Omarchy bar widgets that read the state files
- `page/` (next) — Quickshell full-screen panel: today's note, blank page, the trigger
- `agent/` (next) — the runner: allowlist context builder, payload log, tool-less
  opencode agent, transcript + state file. Reference: `docs/diary.md`

## Steps (one at a time)
- [x] Step 1 — folder + README + this plan
- [x] Step 2 — `gh repo create pedrosekine/omarchy-student --public --source .` (done, origin set)
- [x] Step 3 — v0.1 CLI prototype: `cli/pomo` bash script + state file — on PATH via `ln -sfn "$PWD/cli/pomo" ~/.local/bin/pomo` (absolute target: re-link after moving the repo, or the bindings and both widgets fail with "binary could not be found")
- [x] Step 4 — Hypr bindings: `SUPER+ALT+P` toggle, `SUPER+ALT+N` skip in `~/.config/hypr/bindings.lua` (SUPER+P was taken by Pseudo window)
- [x] Step 5 — v0.2 bar widget: `plugin/` QML (`student.pomo`: countdown label + progress popup, left=popup, right=toggle, middle=skip). Installed as real files in `~/.config/omarchy/plugins/student.pomo` (symlinks not allowed there — copy on change, shell auto-reloads).
- [x] Step 6 — session counter: `pomo stats [day|week|month|--json]` (calendar week Mon–Sun) + popup segmented Day/Week/Month selector with live count. Counts `focus started` lines in `pomo.log`.
- [x] Step 7 — finish cue: `pomo bell` (desktop notification + bell sound), auto-fired once by the widget on running→expired edge. Sound: `sounds/done.wav` (Mixkit "Uplifting flute notification", free license, see sounds/README.md).
- [x] Step 8 — auto-start flow: `auto` flag in state.json, `pomo autostart [on|off|toggle]`, `pomo expired` edge handler (bell + auto-advance), popup switch. Provisional name "auto-start" — naming decision tracked in issue #1.
- [x] Step 9 — popup controls: icon buttons (play/pause, skip, reset) side by side; tap-timer duration picker (15/25/45/60 min chips when idle, tap toggles picker, tap while running pauses/resumes). CLI `pomo start [focus|break] [minutes]` with per-phase default persisted (`focus_len`/`break_len`/`total` in state.json).
- [x] Step 10 — typed minutes (idle timer is a minutes field, Enter starts) + completions-only counting (`focus completed` logged at expiry; CLI stats + popup recount).
- [x] Step 11 — microwave-style entry, no caret: plain focusable Text (cursor impossible), digits shift in (--:-2 → --:25 → 25:00 → 250:00), Backspace deletes, Enter starts, Escape blurs.
- [x] Step 12 — deadlines (manual): `pomo deadline add|list|rm|next`, stored as
      `deadlines.tsv` (`id<TAB>epoch<TAB>title`). Free-text dates via `date -d`
      ("next friday 17:00", "in 3 hours", "3d", "by friday"); a bare day snaps to
      23:59 because a deadline means the end of that day. New `student.deadline`
      bar widget (`plugin-deadline/`): calendar glyph + countdown to the next
      deadline, urgent-coloured inside 24h, popup lists the next 6 with `x` to
      remove. Installed alongside `student.pomo` in the bar's center section.
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
      - [x] 14.1 the page — `plugin-page/` (`student.page`, kind `overlay`,
            keepLoaded). Themed sheet, date, today's note as plain text, save
            per keystroke (300 ms coalesce, flush on Enter/close, atomic
            writes), Esc closes, Enter continues list items and checkboxes,
            Ctrl+Up/Down jump blocks. Block splitting in `Blocks.js` with a
            Python twin `agent/blocks.py`; `tests/test_blocks.py` cross-checks
            them. Config: `~/.config/omarchy-student/config.json` (see
            `config.example.json`). Note created from
            `<vault>/agents/student/templates/daily.md` by whoever gets there
            first — the same file is set as Obsidian's daily-notes template.
            Install: copy to `~/.config/omarchy/plugins/student.page/`, add
            `{"id":"student.page"}` to `plugins[]` in shell.json, bind
            `SUPER+ALT+=` → `omarchy-shell shell toggle student.page '{}'`.
            Gotcha: overlays are toggled via the `shell` target, not their id.
      - [x] 14.2 the loop — `agent/student-agent` (Python, no deps): builds
            the payload from the allowlist (note minus private blocks and the
            link line, knowledge files, curriculum folder, `pomo report`),
            logs it to `~/.local/state/omarchy-student/payloads/`, runs
            `opencode run --pure --agent student --format json` with the
            tool-less agent in `agent/opencode/student.md` (DeepSeek 4.1
            flash via OpenCode Go), parses one fenced JSON block (reply,
            proposals, suggestions, knowledge), and applies it: transcript
            `agents/student/daily/<date>.md`, state `<date>.json`, knowledge
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
            for a second marks it read (`student-agent ack`). `Ctrl+Enter`
            focuses the chat field, Enter sends (`student-agent chat`
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
            accepts one: `student-agent accept --hash --index` runs `pomo
            deadline add` with title/subject/link/when, records the new id
            in state and transcript, never twice. The prompt now flags
            disagreements between the note and the deadline store (the
            store is the truth). Tasks panel on `Ctrl+T`: `student-agent
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
            dismissals as "do not raise again". `student-agent next` lists
            open tasks plus undismissed suggestions and open-pass
            observations across the last 7 days; the `Ctrl+T` panel is now
            "what's next": tasks on top, "from the agent" below, Enter ticks
            a task or waves off a suggestion. `curriculum` folder in config
            (`agents/student/curriculum`); `student-agent curriculum`
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
            undo is the editor's own (cross-field). Page logic (staging,
            send prompt, panel) is unchanged and talks to the editor through
            the same `text`/`cursorPosition`/`insert`/`remove`. Not yet:
            selecting across lines (selection is per line).
            `tests/tst_editor.qml` drives it offscreen with qmltestrunner.
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
            moment, kept in `~/.local/state/omarchy-student/page.json`.
      - [x] 14.6d find — Ctrl+F opens a line under the date; matches are
            case-insensitive, in the rows' words only (never the lifted
            markdown), painted under the text (current one stronger) and
            counted "n / m". Enter / Shift+Enter step with wrap-around;
            Ctrl+Enter selects the match and closes; Esc returns the cursor
            to where the search began.
      - [ ] 14.7 focus mode · 14.8 study mode · 14.9 phone capture, external reading.
- [ ] Parked — deadline entry from the popup (absorbed by 14.4), `.ics` import,
      analytics (`history`), daily counter

## v0.1 Keyboard contract
```bash
pomo toggle  # start/pause/resume
pomo skip    # next phase
pomo status  # JSON for scripts/bar
```

Hypr bindings (active):
```lua
o.bind("SUPER + ALT + P", "Pomo toggle", "pomo toggle")
o.bind("SUPER + ALT + N", "Pomo skip", "pomo skip")
o.bind("SUPER + ALT + O", "Pomo popup", "omarchy-shell student.pomo toggle")
o.bind("SUPER + ALT + D", "Deadlines popup", "omarchy-shell student.deadline toggle")
o.bind("SUPER + ALT + equal", "Page (today's note)", "omarchy-shell shell toggle student.page '{}'")
o.bind("SUPER + ALT + backslash", "Page alongside", "omarchy-shell shell summon student.page '{\"shape\":\"alongside\"}'")
```

## Decisions
Longer-form design thinking lives in `docs/student-os.md` (agentic-first, cadence, progress, research).

- 2026-09-05: Hybrid, name omarchy-student, v0.1 = keyboard shortcuts
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
