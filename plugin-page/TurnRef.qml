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
  property bool clickable: false
  // Several things pointed at (2026-11-28): each its own link, `clickedAt`
  // with its place — one click target for all went to the first.
  property var parts: []
  readonly property bool several: parts.length > 1
  signal clicked()
  signal clickedAt(int i)
  function _esc(x) { return String(x).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
  readonly property int rule: page.sp(2)
  readonly property int inset: Math.round(page.chatSize * 0.6)
  readonly property int maxW: Math.round(width * 0.8)
  readonly property int blockW: Math.min(maxW, Math.max(words.implicitWidth + rule + inset, alignTo))
  visible: text !== "" || parts.length > 0
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
    textFormat: ref.several ? Text.RichText : Text.PlainText
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
    lineHeight: 1.15
    text: !ref.several ? (ref.parts.length === 1 ? ref.parts[0] : ref.text)
      : ref.parts.map(function (p, i) {
          return "<a href=\"" + i + "\" style=\"color:" + (words.hoveredLink === String(i) && page.handOn ? page.accent : page.dim)
            + ";text-decoration:none\">" + ref._esc(p) + "</a>"
        }).join("&nbsp;&nbsp;·&nbsp;&nbsp;")
    onLinkActivated: function (link) { if (ref.clickable) ref.clickedAt(parseInt(link)) }
    color: ref.clickable && refArea.containsMouse && page.handOn ? page.accent : page.dim
    font.family: page.fontFamily
    font.pixelSize: Math.round(page.chatSize * 0.8)
    font.underline: ref.clickable && refArea.containsMouse && page.handOn
  }
  MouseArea {
    id: refArea
    x: ref.width - ref.blockW
    y: 0
    width: ref.blockW
    height: words.height + page.sp(2)
    enabled: ref.clickable
    hoverEnabled: ref.clickable
    // With several, the words' own links take the click; this only shows
    // the hand over one.
    acceptedButtons: ref.several ? Qt.NoButton : Qt.LeftButton
    cursorShape: !ref.clickable ? Qt.ArrowCursor : !ref.several || words.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: { ref.clicked(); ref.clickedAt(0) }
    Tip { host: ref.page; shown: parent.containsMouse && ref.clickable; text: "Jump to this reference" }
  }
}
