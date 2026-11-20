// Layout — where the note sits beside the panes (docs/navigation.md).
//
// One rule for both shapes and both sides (2026-10-24): the panes stand
// against the window's edges, the note is centred in the window, and a
// pane opening does not move it while there is room for both. Only when
// there is not does the note step aside, as far as it has to, and it
// narrows last.
.pragma library

// `width`: the window's; `want`: the note's own width (the measure and its
// padding); `edge`: kept clear at both window edges; `left`, `right`: the
// room a pane at that edge takes (its width and the gap), 0 when none.
// Returns { x, width }.
function note(width, want, edge, left, right) {
  var w = Math.max(0, Math.min(want, width - 2 * edge - left - right))
  var x = Math.max(edge + left, Math.min(Math.round((width - w) / 2), width - edge - right - w))
  return { x: x, width: w }
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
