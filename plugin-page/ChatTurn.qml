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
  signal linkActivated(string link)

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
    radius: Math.max(Style.cornerRadius, page.sp(10))
    color: Util.alpha(page.accent, 0.14)
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
    onSelectedTextChanged: if (selectedText !== "") page.chatSelected(said)
    HoverHandler { cursorShape: said.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor }
  }
}
