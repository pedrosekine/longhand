import QtQuick
import qs.Commons

// One turn of a conversation, as the agent's panes draw it (2026-10-25):
// the student's words in a bubble at the right, the agent's across the
// pane. Until then both ran down the left, told apart only by a shade of
// grey. Either can be selected with the mouse and copied (Ctrl+C from the
// box, Page.copyChatSelection); the keys stay in the box all the while, so
// a press here never takes them. The selection is the theme's colour — a
// selectable text left alone draws Qt's own blue.
Item {
  id: turn
  required property Item page
  property bool mine: false
  property string text: ""
  property bool markdown: !mine
  property color color: page.foreground
  property int pixelSize: page.fs(Style.font.title)
  // Words picked in the agent's answer can be answered (2026-11-18): an
  // "answer" at the end of the selection, or Ctrl+R; several at once, each
  // its own answer above the box.
  property bool answerable: false
  property string pane: "day"          // the pane this turn is in, and its time: what a reply is to
  property string at: ""
  // The passages replied to in these words (Page.passageMarks): lit while
  // the reply is written ("open"), underlined with their number once
  // attached or sent.
  property var marks: []
  signal linkActivated(string link)
  signal answer(string passage)
  function answerSelection() {
    var s = String(said.selectedText).replace(/\s+/g, " ").trim()
    if (!turn.answerable || s === "") return false
    turn.answer(s)
    said.deselect()
    return true
  }

  // A selectable text has no linkColor, and its palette does not reach the
  // markdown's links: they came out pure blue on the dark ground. A link
  // written as an anchor with its own colour does take it, so links are
  // rewritten so (outside code, where brackets are only brackets).
  function linked(md) {
    var c = String(page.accent)
    function a(href, label) { return "<a href=\"" + href.replace(/"/g, "&quot;") + "\" style=\"color:" + c + "\">" + label + "</a>" }
    return String(md).split(/(```[\s\S]*?```|`[^`\n]*`)/).map(function (part, i) {
      if (i % 2 === 1) return part
      return part.replace(/(^|[^!])\[([^\]\n]+)\]\(([^)\s]+)\)/g, function (m, pre, label, href) { return pre + a(href, label) })
        .replace(/<(https?:\/\/[^>\s]+)>/g, function (m, href) { return a(href, href) })
    }).join("")
  }

  readonly property int padX: page.sp(10)
  readonly property int padY: page.sp(6)

  width: parent ? parent.width : 0
  implicitHeight: mine ? bubble.height : said.implicitHeight

  // How wide the words run unwrapped: a short message gets a short bubble,
  // a long one wraps at four fifths of the pane.
  Text {
    id: natural
    visible: false
    textFormat: Text.PlainText
    text: turn.mine ? turn.text : ""
    font: said.font
  }

  Rectangle {
    id: bubble
    visible: turn.mine
    anchors.right: parent.right
    width: Math.min(Math.ceil(natural.implicitWidth) + 2, Math.round(turn.width * 0.8) - turn.padX * 2) + turn.padX * 2
    height: said.implicitHeight + turn.padY * 2
    radius: Style.cornerRadius
    color: Util.alpha(page.accent, 0.14)
  }

  // Where a passage's words are, as rectangles a line each, in the words'
  // own frame. Found by its words, whitespace and case aside.
  FontMetrics { id: wordMetrics; font: said.font }
  function passageRects(quote) {
    var plain = said.getText(0, said.length), norm = "", map = [], space = false
    for (var i = 0; i < plain.length; i++) {
      var c = plain.charAt(i)
      if (/\s/.test(c)) { if (!space && norm !== "") { norm += " "; map.push(i) } space = true; continue }
      space = false
      norm += c.toLowerCase()
      map.push(i)
    }
    var want = String(quote || "").replace(/ …$/, "").replace(/\s+/g, " ").trim().toLowerCase()
    var at = want === "" ? -1 : norm.indexOf(want)
    if (at < 0) return []
    var a = map[at], b = map[at + want.length - 1] + 1, lines = []
    for (var k = a; k < b; k++) {
      var r = said.positionToRectangle(k), next = said.positionToRectangle(k + 1)
      var right = Math.abs(next.y - r.y) < 1 ? next.x : r.x + wordMetrics.averageCharacterWidth
      var line = lines.length > 0 && Math.abs(lines[lines.length - 1].y - r.y) < 1 ? lines[lines.length - 1] : null
      if (!line) { line = { x: r.x, y: r.y, w: 0, h: r.height }; lines.push(line) }
      line.w = Math.max(line.w, right - line.x)
    }
    return lines
  }
  readonly property var markRects: {
    said.contentWidth; said.contentHeight; said.text; turn.width
    return turn.marks.map(function (m) { return { m: m, rects: turn.passageRects(m.quote) } }).filter(function (x) { return x.rects.length > 0 })
  }
  Repeater {
    model: turn.markRects
    Item {
      id: markItem
      required property var modelData
      x: said.x
      y: said.y
      readonly property bool open: modelData.m.state === "open" || modelData.m.state === "hover"
      readonly property var last: modelData.rects[modelData.rects.length - 1]
      Repeater {
        model: markItem.modelData.rects
        Item {
          required property var modelData
          x: modelData.x
          y: modelData.y
          width: modelData.w
          height: modelData.h
          Rectangle {
            visible: markItem.open
            anchors.fill: parent
            radius: 2
            color: page.palette.selection
          }
          Rectangle {
            visible: !markItem.open
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: markItem.modelData.m.state === "sent" ? page.dim : page.accent
          }
        }
      }
      // Its number, at the end of its words.
      Rectangle {
        x: markItem.last.x + markItem.last.w + 1
        y: markItem.last.y - height / 3
        width: Math.max(height, markNum.implicitWidth + 6)
        height: markNum.implicitHeight + 1
        radius: height / 2
        color: markItem.open ? page.accent : page.dim
        Text {
          id: markNum
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(markItem.modelData.m.n)
          color: page.background
          font.family: page.fontFamily
          font.pixelSize: Math.round(page.textSize * 0.6)
        }
      }
    }
  }

  TextEdit {
    id: said
    x: turn.mine ? bubble.x + turn.padX : 0
    y: turn.mine ? turn.padY : 0
    width: turn.mine ? bubble.width - turn.padX * 2 : turn.width
    readOnly: true
    selectByMouse: true
    activeFocusOnPress: false
    persistentSelection: true
    textFormat: turn.markdown ? TextEdit.MarkdownText : TextEdit.PlainText
    wrapMode: TextEdit.Wrap
    text: turn.markdown ? turn.linked(turn.text) : turn.text
    color: turn.color
    selectionColor: page.palette.selection
    selectedTextColor: page.foreground
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: turn.pixelSize
    onLinkActivated: function (link) { turn.linkActivated(link) }
    onSelectedTextChanged: {
      if (selectedText !== "") page.chatSelected(said)
      // Offered over the box too, while it is selected (the bar, cue 3).
      if (turn.answerable && selectedText.trim() !== "")
        page.replyOffer = { pane: turn.pane, at: turn.at, quote: String(selectedText).replace(/\s+/g, " ").trim(), item: turn }
      else if (page.replyOffer && page.replyOffer.item === turn) page.replyOffer = null
    }
    HoverHandler { cursorShape: said.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor }
  }

  // "reply", over the words selected (2026-11-18): drawn as the hover
  // hints are — the sheet's darker paper, a faint edge, no shadow — the word
  // and its key set apart, above the selection's first line so it never
  // covers what is picked. The word turns accent under the pointer, as every
  // button of the page does.
  Rectangle {
    id: replyTool
    readonly property rect start: said.positionToRectangle(Math.min(said.selectionStart, said.selectionEnd))
    readonly property color edge: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
    visible: turn.answerable && said.selectedText.trim() !== "" && page.chatSelection === said
    x: Math.max(0, Math.min(said.x + start.x - page.sp(2), turn.width - width))
    y: said.y + start.y - height - page.sp(8)
    z: 3
    width: toolRow.implicitWidth + page.sp(22)
    height: toolRow.implicitHeight + page.sp(12)
    radius: Style.cornerRadius
    color: page.sunk
    border.width: 1
    border.color: edge
    Row {
      id: toolRow
      anchors.centerIn: parent
      spacing: page.sp(18)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "reply"
        color: toolArea.containsMouse && page.handOn ? page.accent : page.foreground
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      KeyCaps {
        anchors.verticalCenter: parent.verticalCenter
        page: turn.page
        key: page.keyName("chatAnswer")
      }
    }
    MouseArea {
      id: toolArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: turn.answerSelection()
    }
  }
}
