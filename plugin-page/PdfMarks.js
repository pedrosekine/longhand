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
