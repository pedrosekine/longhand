import QtQuick
import qs.Commons

// What a message pointed at — a passage of the paper, a block, a task —
// over the student's bubble (2026-11-19, chat readability). It was a faint
// caption, right-aligned and cut at one line: "↳ p. 6 “Additionally, we
// also introduced a route adheren…”", too small and too pale to read, and
// it hung off the bubble's right edge while the bubble's words started at
// its left. Now it is quoted as a reply quotes: a rule in the accent, the
// words dim, up to two lines, starting where the bubble starts.
Item {
  id: ref
  required property Item page
  property string text: ""
  property int alignTo: 0              // the bubble's width under it, to start where it starts
  readonly property int rule: page.sp(2)
  readonly property int inset: Math.round(page.chatSize * 0.6)
  readonly property int maxW: Math.round(width * 0.8)
  readonly property int blockW: Math.min(maxW, Math.max(words.implicitWidth + rule + inset, alignTo))
  visible: text !== ""
  width: parent ? parent.width : 0
  implicitHeight: visible ? words.height + page.sp(2) : 0

  Rectangle {
    x: ref.width - ref.blockW
    y: page.sp(1)
    width: ref.rule
    height: words.height
    color: page.accent
  }
  Text {
    id: words
    x: ref.width - ref.blockW + ref.rule + ref.inset
    y: page.sp(1)
    width: ref.blockW - ref.rule - ref.inset
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
    lineHeight: 1.15
    text: ref.text
    color: page.dim
    font.family: page.fontFamily
    font.pixelSize: Math.round(page.chatSize * 0.8)
  }
}
