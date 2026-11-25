// Layout — where the note sits beside the panes (docs/navigation.md).
//
// One rule for everything in the middle (2026-11-25): the panes stand
// against the window's edges, and the note, a paper, the dashboard and the
// lists are centred in the room the panes leave between them. A pane
// opening slides the note by half its width, so the margins either side of
// the note stay even. Only when the room is narrower than the note does the
// note narrow.
.pragma library

// `width`: the window's; `want`: the note's own width (the measure and its
// padding); `edge`: kept clear at both window edges; `left`, `right`: the
// room a pane at that edge takes (its width and the gap), 0 when none.
// Returns { x, width }.
function note(width, want, edge, left, right) {
  var room = Math.max(0, width - 2 * edge - left - right)
  var w = Math.min(want, room)
  return { x: edge + left + Math.round((room - w) / 2), width: w }
}

// Whether both side panes fit simultaneously while keeping the note at least
// `minNote` wide. When false, opening one side pane closes the opposite one.
function bothFit(width, edge, leftSpace, rightSpace, minNote) {
  return width - 2 * edge - leftSpace - rightSpace >= minNote
}

// Right pane width beside the note. Returns 0 when the window cannot fit even
// `minPane` beside a `minNote`-wide note (making the "too narrow" guard real).
function rightPane(width, edge, sheetFor, sideSpace, gap, minPane, maxPane, minNote) {
  var avail = width - 2 * edge - sideSpace - gap - minNote
  if (avail < minPane) return 0
  var ideal = width - 2 * edge - sideSpace - gap - sheetFor
  var want = Math.max(minPane, Math.min(maxPane, ideal))
  return Math.max(0, Math.min(Math.round(width * 0.45), Math.min(avail, want)))
}

// ------------------------------------------------ the agent's pane, sized by hand
//
// (docs/explorations/chat-width, 2026-11-22.) The pane is dragged by its
// edge, nudged by keys, and flipped between two remembered widths:
// *reading* (the middle wide) and *discussing* (the chat wide). Nothing
// moves place; only the edge does.
//
// `o` says what the middle and the pane share:
//   room       the window's width less its edges, the sidebar and the gap
//   min        the pane's least width (300 px)
//   ceiling    the most the chat can use: its answers' measure, and the
//              rail of quoted words beside a paper. Past it the width stays
//              with the middle.
//   floor      the middle's least, kept by the keys: a paper's width where
//              its text is still about 11 px, a note's least
//   hardFloor  the middle's least for a drag of the edge (a paper squeezed
//              to glance at a figure)
//   reading    the reading width before any is remembered (today's width)

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// What the edge may do: { alone, min, keyMax, dragMax }. `alone` when the
// middle's floor and the pane's least do not fit side by side: then they
// show one at a time.
function paneRange(o) {
  var keyMax = Math.min(o.ceiling, o.room - o.floor)
  var dragMax = Math.max(keyMax, Math.min(o.ceiling, o.room - o.hardFloor))
  return { alone: keyMax < o.min, min: o.min, keyMax: Math.max(o.min, keyMax), dragMax: Math.max(o.min, dragMax) }
}

// The pane's width in a split (`state`: "reading" or "discussing"), given
// the width remembered for it (`want`, 0 when none). Discussing starts at
// the most the keys allow: the middle at its floor, or the chat at its
// ceiling. 0 when the two show one at a time.
function paneWidth(o, state, want) {
  var r = paneRange(o)
  if (r.alone) return 0
  if (want > 0) return Math.round(clamp(want, r.min, r.dragMax))
  if (state === "discussing") return Math.round(r.keyMax)
  return Math.round(clamp(o.reading, r.min, r.keyMax))
}

// A nudge of the edge by `by` (positive: the pane wider). Wider stops at
// the middle's floor (or where the pane already is, if a drag took it past
// that); narrower stops at the pane's least.
function nudge(o, cur, by) {
  var r = paneRange(o)
  if (by > 0) return Math.round(Math.max(cur, Math.min(cur + by, r.keyMax)))
  return Math.round(Math.max(r.min, cur + by))
}

// A drag of the edge to a pane `w` wide, as far as the edge may go.
function drag(o, w) {
  var r = paneRange(o)
  return Math.round(clamp(w, r.min, r.dragMax))
}

// Where a paper stops being readable (its floor): the column at which its
// body text, fitted as PdfPane fits it (its text about the page's middle,
// 14 pt beside it), is `px` pixels. `span` is longhand-read's: x0, x1, w,
// and h, the paper's usual word height in points (about 1.2 × its type
// size). Without a span, a page of `pageW` points at 10 pt type.
function paperFloor(span, pageW, px, pad) {
  var reach, typePt = 10
  if (span && span.w > 0) {
    var mid = span.w / 2
    reach = Math.max(mid - span.x0, span.x1 - mid) + 14
    if (span.h > 0) typePt = span.h / 1.2
  } else reach = (pageW > 0 ? pageW : 612) / 2
  return Math.ceil(2 * reach * (px / typePt)) + pad
}
