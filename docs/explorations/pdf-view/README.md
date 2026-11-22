# The PDF reader's own page view — 2026-11-22

The reader was built on Qt's `PdfMultiPageView`. Most PDF bugs of 14 to 22
November were in that view, not in PDFium: its table guessed where pages
were and kept stale places after a resize, its own jump slid pages
sideways, it measured its column before taking in a new size, its page
pictures raced, its current page went stale, and its dragging and touchpad
handling fought word selection. Longhand also reached into its undocumented
insides. The view is replaced by Longhand's own; PDFium stays
(`PdfDocument`, `PdfPageImage`, `PdfSelection`, `PdfLinkModel`), and so does
Poppler's `pdftotext` in `cli/longhand-read`.

## The feel before the switch (from the code, 2026-11-22)

The new view keeps these numbers and handlers. A change to any of them is
a decision, not a side effect.

| What | How it felt | Where |
|---|---|---|
| Mouse wheel | one notch (120) = `sp(60)` px down; a wheel with pixel deltas: 2× the pixels | `PdfPane.wheel()` |
| Ctrl+wheel | one notch = zoom × 1.1 (pixel deltas: 40 px a notch), zoom held to 0.3–4; the view's top stays where it is, the page re-centred | `wheel()`, then `fit()` |
| Sideways wheel or swipe | only when sized past the fit (zoom > 1.01) and the page is 40 px wider than the column; same step as up and down | `wheel()` |
| Touchpad two-finger scroll | 2× the finger travel; on lift, a flick at the speed of the last 90 ms if over 120 px/s (the Flickable's own deceleration); resting the fingers first means stop; sideways or Ctrl passed on | `TouchScroll.qml` (shared with the note) |
| Pinch | Qt's own: the one page under the fingers scaled about them while pinching, the other pages still; on lift, if the change was over 10%, the view's scale taken and the place under the fingers kept, then re-centred 60 ms later by `align()` (a sideways jump at the end); under 10% the page snapped back. The scale is then taken back as `zoom` over `fitBase` | `PdfMultiPageView`'s `PinchHandler`, `onRenderScaleChanged` |
| `+` / `-` | zoom × 1.2 / ÷ 1.2, held to 0.3–4 | `key()` |
| `0` | zoomed: back to the fit; fitted: text fit ↔ whole page | `fitToggle()` |
| Text fit | scale = (column / 2) / (the text's farther side from the page's middle + 14 pt); no span: the first page's width to the column | `fit()` |
| Centring | the page's middle in the column's middle, always, after any size change | `align()` |
| Gap between pages | 6 px | Qt's `rowSpacing` |
| `j`/`k`, ↓/↑ | `sp(60)` px, at once | `key()` → `scrollBy` |
| PgDn/Space, PgUp/Shift+Space | the same distance down the next (previous) page as the view's top is down this one; glides | `turn()` → `jumpTo` |
| Home / End | the first page's top / the last page's top, as far as it goes; glides | `key()` |
| `g` | a page number, Enter jumps to its top; glides | `commitGoto()` |
| The glide | `contentY` over 400 ms, `Easing.OutQuart`, up or down only; a key or the wheel stops it | `jumpTo()` |
| Drag | with a mouse, a stylus or a touchpad: selects words on the page pressed; never pans | `tame()`, `touchpad()` |
| Click | on a mark: picks it (the smallest first); away from marks: lets go; clears the selection | marks layer |
| In-PDF link | Qt's own jump, at once, then re-centred | `PdfLinkDelegate` in Qt's view |
| The foot's page | the page across the view's middle, worked out 50 ms after a scroll | `track()` |
| Its place | kept 800 ms after scrolling stops, and on close; opens there again | `keep()`, `arrive()` |

## What changed on purpose

- **Pinch.** The whole view sizes about the fingers as they move (the place
  under them stays under them), and nothing moves when they lift: no 10%
  threshold, no re-centring after. Zoomed past the fit, the page stays
  where the pinch left it sideways; at or under the fit it stays centred.
  The pictures are stretched while the fingers move and drawn sharp 150 ms
  after they rest.
- **A link inside the PDF** glides there as any jump does, and the back
  key (`Ctrl+[`) returns, as from an acronym's definition.
- **One selection at a time.** Starting a drag on one page lets go of
  words selected on another.
- **A far jump** (a page not drawn) is put most of a view short of it and
  glides the last stretch, as before; the pages flown past are never drawn.

## Memory before and after

Measured with the page in its private Hyprland (scale 2), scrolling a
20-page paper with figures by the wheel and a 300-page one (the same paper
fifteen times) by PgDn, then five far jumps (`mem.py`, kept outside the
repo). RSS of the page's process in MiB, two runs each.

| | opened | peak while scrolling | at the end |
|---|---|---|---|
| 20 pages, Qt's view | 432–436 | 533–536 | 441–445 |
| 20 pages, own view | 409–425 | 515–525 | 431–443 |
| 300 pages, Qt's view | 425–430 | 610–633 | 485–498 |
| 300 pages, own view | 416–428 | 530–542 | 440–452 |

The first build of the own view peaked at 4.2 GB on the 300-page paper:
the first and last pages to draw were two values, and on a jump up the
paper the first moved before the last, so for that moment every page in
between was asked to draw. They are one value now (`range`).
