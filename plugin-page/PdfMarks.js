// PdfMarks — which mark a click on a PDF's page picks (2026-11-16).
//
// Marks overlap: a highlight on one word inside a question on its whole
// sentence. A click picks the smallest mark under it; another click there
// goes to the next larger one, and after the largest lets go. A lone mark
// clicked again lets go too, as it always did.
//
// `marks` as longhand-read hands them back ({ id, boxes: [{ page, rects:
// [[x, y, w, h]] }] }), `page` from 0, `x`/`y` in the page's own points,
// `picked` the mark picked now ("" for none), `pad` how far outside a
// rectangle still counts. Returns the id to pick, "" to let go.
.pragma library

function area(m) {
  var a = 0
  for (var b = 0; b < m.boxes.length; b++)
    for (var r = 0; r < m.boxes[b].rects.length; r++)
      a += m.boxes[b].rects[r][2] * m.boxes[b].rects[r][3]
  return a
}

// The marks under the point, smallest first.
function under(marks, page, x, y, pad) {
  pad = pad || 0
  var out = []
  for (var i = 0; i < (marks || []).length; i++) {
    var m = marks[i], hit = false
    for (var b = 0; b < (m.boxes || []).length && !hit; b++) {
      if (m.boxes[b].page !== page) continue
      for (var r = 0; r < m.boxes[b].rects.length && !hit; r++) {
        var q = m.boxes[b].rects[r]
        hit = x >= q[0] - pad && x <= q[0] + q[2] + pad && y >= q[1] - pad && y <= q[1] + q[3] + pad
      }
    }
    if (hit) out.push({ id: m.id, a: area(m), i: i })
  }
  // The same size: the later one first, as it is drawn over the other.
  out.sort(function (p, q) { return p.a - q.a || q.i - p.i })
  return out.map(function (o) { return o.id })
}

function pick(marks, page, x, y, picked, pad) {
  var ids = under(marks, page, x, y, pad)
  if (ids.length === 0) return picked || ""
  var i = ids.indexOf(picked)
  if (i < 0) return ids[0]
  return i + 1 < ids.length ? ids[i + 1] : ""
}

// The marks of one page as pieces to paint, none over another (2026-11-17).
//
// Two marks on the same words were once drawn into a layer of their own
// (an offscreen texture a page) at 0.4, so their colour stayed the same
// where they crossed. Qt keeps a page's holder and hands it the next page
// as the view scrolls, and the texture could keep the page before's marks:
// page 5's two questions came out over page 2's words, where page 2's own
// marks were not (seen 2026-11-17). Each piece here is painted once, at
// its own strength, with no layer; where marks cross the later one shows,
// as it did.
//
// `rects` in drawing order ([{ kind, r: [x, y, w, h] }], points), `pad`
// how far each is widened on either side. Returns [{ kind, x, y, w, h,
// round }] in points: `round` for a piece no other touches, whose corners
// may be rounded (one that meets another would show a notch).
function paint(rects, pad) {
  pad = pad || 0
  var EPS = 0.01
  var boxes = []
  for (var i = 0; i < (rects || []).length; i++) {
    var r = rects[i].r
    if (!r || !(r[2] > 0) || !(r[3] > 0)) continue
    boxes.push({ kind: rects[i].kind, x0: r[0] - pad, x1: r[0] + r[2] + pad, y0: r[1], y1: r[1] + r[3] })
  }
  var ys = []
  boxes.forEach(function (b) { ys.push(b.y0, b.y1) })
  ys.sort(function (a, b) { return a - b })
  var cuts = []
  ys.forEach(function (y) { if (cuts.length === 0 || y - cuts[cuts.length - 1] > EPS) cuts.push(y) })
  var pieces = [], open = {}
  for (var c = 0; c + 1 < cuts.length; c++) {
    var y0 = cuts[c], y1 = cuts[c + 1]
    // The top one first: what it covers is taken, what is left goes on down.
    var taken = [], band = []
    for (var k = boxes.length - 1; k >= 0; k--) {
      var b = boxes[k]
      if (b.y0 > y0 + EPS || b.y1 < y1 - EPS) continue
      var free = [[b.x0, b.x1]]
      taken.forEach(function (t) {
        var next = []
        free.forEach(function (f) {
          if (t[1] <= f[0] || t[0] >= f[1]) { next.push(f); return }
          if (t[0] > f[0]) next.push([f[0], t[0]])
          if (t[1] < f[1]) next.push([t[1], f[1]])
        })
        free = next
      })
      free.forEach(function (f) { if (f[1] - f[0] > EPS) band.push({ kind: b.kind, x0: f[0], x1: f[1] }) })
      taken.push([b.x0, b.x1])
    }
    band.sort(function (a, b) { return a.x0 - b.x0 })
    var merged = []
    band.forEach(function (s) {
      var last = merged[merged.length - 1]
      if (last && last.kind === s.kind && s.x0 - last.x1 <= EPS) last.x1 = Math.max(last.x1, s.x1)
      else merged.push({ kind: s.kind, x0: s.x0, x1: s.x1 })
    })
    // A run the band before had too, the same width and kind: one piece, taller.
    var still = {}
    merged.forEach(function (s) {
      var id = s.kind + "|" + s.x0.toFixed(2) + "|" + s.x1.toFixed(2)
      var p = open[id]
      if (p && Math.abs(p.y + p.h - y0) <= EPS) p.h = y1 - p.y
      else { p = { kind: s.kind, x: s.x0, y: y0, w: s.x1 - s.x0, h: y1 - y0, round: true }; pieces.push(p) }
      still[id] = p
    })
    open = still
  }
  for (var a = 0; a < pieces.length; a++)
    for (var z = a + 1; z < pieces.length; z++) {
      var p = pieces[a], q = pieces[z]
      var side = Math.min(p.y + p.h, q.y + q.h) - Math.max(p.y, q.y) > EPS
        && (Math.abs(p.x + p.w - q.x) <= EPS || Math.abs(q.x + q.w - p.x) <= EPS)
      var over = Math.min(p.x + p.w, q.x + q.w) - Math.max(p.x, q.x) > EPS
        && (Math.abs(p.y + p.h - q.y) <= EPS || Math.abs(q.y + q.h - p.y) <= EPS)
      if (side || over) { p.round = false; q.round = false }
    }
  return pieces
}
