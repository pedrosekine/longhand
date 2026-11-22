// PdfPlaces — where each PDF was left, so it opens there again (plan.md,
// item 9, "Left by the build": "PDFs: remember the place between openings").
//
// The record is pdfs.json in the state folder, by the PDF's path (as the
// page opens it: in the vault, or whole for one outside it):
//
//   { "Studies/Course A/Reading.pdf": { page: 4, frac: 0.35, zoom: 1.2, at: 1763150000000 } }
//
// `page` counts from 0, `frac` is how far down that page the top of the view
// is (0 its top, 1 its foot), `zoom` the size over the column's width, `at`
// when it was left. A place by page and fraction holds at another window
// width or size, where a distance in pixels would not.
.pragma library

// The newest this many are kept; an older one is forgotten.
var KEEP = 100

// Where each page's top is, in pixels below the first page's top: the
// pages' heights (already at the view's scale) and the gap between them,
// added up. The view lays every page exactly here, at any scale, so a
// place worked out from these is the place shown (Qt's view guessed at
// the pages it had not laid and kept stale places after a rescale; a
// quote on page 14 went to page 16, 2026-11-22).
function tops(heights, spacing) {
  var out = new Array(heights ? heights.length : 0), y = 0
  for (var i = 0; i < out.length; i++) {
    out[i] = y
    y += Math.max(1, heights[i]) + spacing
  }
  return out
}

// The page at `y` (same pixels as `tops`): the last whose top is at or
// above it, so the gap under a page is that page's. 0 above the first.
function pageAt(tops, y) {
  if (!tops || tops.length === 0) return -1
  var lo = 0, hi = tops.length - 1
  while (lo < hi) {
    var mid = (lo + hi + 1) >> 1
    if (tops[mid] <= y) lo = mid
    else hi = mid - 1
  }
  return lo
}

function round(x) { return Math.round(x * 1000) / 1000 }

// The record with `path` left at `place` ({ page, frac, zoom }) at `now`,
// the oldest past KEEP dropped. A new object: the old one is not changed.
// A PDF left at its very top, at its own size, needs nothing kept: its
// entry goes.
function put(places, path, place, now) {
  var out = {}
  for (var k in places) if (k !== path) out[k] = places[k]
  var zoom = isFinite(place.zoom) ? round(place.zoom) : 1
  if (!(place.page === 0 && place.frac === 0 && zoom === 1))
    out[path] = { page: place.page, frac: place.frac, zoom: zoom, at: now }
  var keys = Object.keys(out)
  if (keys.length > KEEP) {
    keys.sort(function (a, b) { return (out[b].at || 0) - (out[a].at || 0) })
    for (var i = KEEP; i < keys.length; i++) delete out[keys[i]]
  }
  return out
}

// Where `path` was left, checked against the PDF as it is now (`pages`
// pages); null when it was never left anywhere but its top, or the record
// makes no sense. A PDF that has since lost pages opens at its last.
function get(places, path, pages) {
  var p = places ? places[path] : null
  if (!p || typeof p !== "object" || !(pages > 0)) return null
  var page = Math.floor(Number(p.page)), frac = Number(p.frac), zoom = Number(p.zoom)
  if (!isFinite(page) || page < 0) return null
  if (page > pages - 1) { page = pages - 1; frac = 0 }
  if (!isFinite(frac)) frac = 0
  if (!isFinite(zoom) || zoom <= 0) zoom = 1
  return { page: page, frac: Math.max(0, Math.min(1, frac)), zoom: Math.max(0.3, Math.min(4, zoom)) }
}
