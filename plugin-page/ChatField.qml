import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The box a conversation is written in (2026-10-25). The one-line field it
// replaced ran a long message off sideways, out of sight; this one wraps,
// grows with what is written up to `maxLines`, then scrolls. The pane's
// keys come first (`keyPressed`: Enter sends, as before); Shift+Enter is
// left to the box, a new line. Drawn as the shell's TextField is.
FocusScope {
  id: box
  required property Item page
  // What is written, as plain text: the box itself is rich text only so its
  // lines can stand at the chat's leading (2026-11-22, below).
  property string text: ""
  property alias cursorPosition: area.cursorPosition
  property alias readOnly: area.readOnly
  property alias placeholderText: area.placeholderText
  readonly property alias selectedText: area.selectedText
  property int maxLines: 8
  // While the agent answers (2026-11-18): a square at the box's end stops
  // it, as a send button turns into one in the chat apps — drawn the page's
  // way, flat, dim, the accent under the pointer. Esc does the same.
  property bool busy: false
  signal stop()
  readonly property Item stopButton: stopSquare
  // The pane's own keys, before the box's: a handler that takes one sets
  // `event.accepted`.
  signal keyPressed(var event)
  function remove(a, b) { area.remove(a, b) }
  function insert(at, s) { area.insert(at, box._esc(s)) }

  // At the chat's own leading (2026-11-22): a TextArea has no line height,
  // and plain text none at all, so the box is rich text, one paragraph with
  // the chat's line-height, as the note's rows are (NoteEditor.leading);
  // one document position per character, so the cursor, a selection and a
  // name's place are the plain text's. `text` is read back as plain.
  readonly property int leadPct: page.chatLeading
  readonly property string _open: "<p style=\"line-height:" + box.leadPct + "%;margin:0;white-space:pre-wrap\">"
  function _plain() { return area.getText(0, area.length).replace(/[\u2028\u2029]/g, "\n") }
  property bool _syncing: false
  function _render(t) {
    var c = area.cursorPosition
    box._syncing = true
    area.text = box._open + box._esc(t) + "</p>"
    box._syncing = false
    area.cursorPosition = Math.max(0, Math.min(c, area.length))
    box._moved(t)
  }
  onTextChanged: if (!box._syncing && box.text !== box._plain()) box._render(box.text)
  onLeadPctChanged: box._render(box.text)
  Component.onCompleted: box._render(box.text)
  // A paste is its words only: rich text from elsewhere would bring its own
  // paragraphs and their spacing.
  TextEdit { id: clip; visible: false; textFormat: TextEdit.PlainText }
  function _paste() {
    clip.text = ""
    clip.paste()
    if (clip.text === "") return
    if (area.selectedText !== "") area.remove(area.selectionStart, area.selectionEnd)
    area.insert(area.cursorPosition, box._esc(clip.text))
  }

  // A paper or a note picked by @ (2026-11-19): its name stays in the
  // sentence, in the accent as a link is, tied to its chip above. One goes
  // with the other: Backspace on the name gives back the `@` as typed (the
  // list opens again, to pick another), the chip's × takes the name out,
  // and an edit inside the name leaves it words and lets the chip go.
  // `chipKeys` (the chips' `refKey`s): a name whose chip went another way
  // is words again.
  property var chipKeys: []
  property var mentions: []             // [{ start, len, key, query }]
  signal mentionGone(string key)
  readonly property var liveMentions: box.mentions.filter(function (m) { return box.chipKeys.indexOf(m.key) >= 0 })
  onChipKeysChanged: if (box.liveMentions.length !== box.mentions.length) box.mentions = box.liveMentions
  property string _was: ""
  function pickMention(start, end, name, key, query) {
    area.remove(start, end)
    var spaced = box.text.charAt(start) === " "
    area.insert(start, box._esc(spaced ? name : name + " "))
    box.mentions = box.mentions.concat([{ start: start, len: name.length, key: key, query: query }])
    area.cursorPosition = start + name.length + 1
  }
  function dropMention(key) {
    var gone = box.mentions.filter(function (m) { return m.key === key }).sort(function (a, b) { return b.start - a.start })
    if (gone.length === 0) return
    box.mentions = box.mentions.filter(function (m) { return m.key !== key })
    gone.forEach(function (m) {
      var end = m.start + m.len
      area.remove(m.start, box.text.charAt(end) === " " ? end + 1 : end)
    })
  }
  function _lastOf(key) { return !box.mentions.some(function (m) { return m.key === key }) }
  // Where an edit fell: at the cursor when that explains it (typing next
  // to a name whose letters repeat), else the common ends.
  function _edit(was, now) {
    var d = now.length - was.length, c = area.cursorPosition
    if (d > 0 && c - d >= 0 && was.substring(0, c - d) === now.substring(0, c - d) && was.substring(c - d) === now.substring(c))
      return { at: c - d, end: c - d, d: d }
    if (d < 0 && was.substring(0, c) === now.substring(0, c) && was.substring(c - d) === now.substring(c))
      return { at: c, end: c - d, d: d }
    var p = 0, n = Math.min(was.length, now.length)
    while (p < n && was.charAt(p) === now.charAt(p)) p++
    var s = 0
    while (s < n - p && was.charAt(was.length - 1 - s) === now.charAt(now.length - 1 - s)) s++
    return { at: p, end: was.length - s, d: d }
  }
  function _moved(now) {
    var was = box._was
    box._was = now
    if (box.mentions.length === 0 || was === now) return
    if (now === "") { box.mentions = []; return }
    var e = box._edit(was, now), keep = [], broken = []
    box.mentions.forEach(function (m) {
      var end = m.start + m.len
      if (end <= e.at) keep.push(m)
      else if (m.start >= e.end) keep.push({ start: m.start + e.d, len: m.len, key: m.key, query: m.query })
      else broken.push(m)
    })
    box.mentions = keep
    broken.forEach(function (m) { if (box._lastOf(m.key)) box.mentionGone(m.key) })
  }
  function _backspace(event) {
    if (event.key !== Qt.Key_Backspace || event.modifiers !== Qt.NoModifier || area.selectedText !== "" || area.readOnly) return false
    var c = area.cursorPosition, t = box.text
    var m = box.liveMentions.find(function (x) { var end = x.start + x.len; return c === end || (c === end + 1 && t.charAt(end) === " ") })
    if (!m) return false
    box.mentions = box.mentions.filter(function (x) { return x !== m })
    area.remove(m.start, m.start + m.len)
    area.insert(m.start, box._esc("@" + m.query))
    area.cursorPosition = m.start + 1 + m.query.length
    if (box._lastOf(m.key)) box.mentionGone(m.key)
    return true
  }
  // The box's words as rich text, the names in the accent: drawn over the
  // box's own (then clear), laid out by the same engine, only while a
  // name is there.
  function _esc(x) { return String(x).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
  readonly property string _drawn: {
    var ms = box.liveMentions.slice().sort(function (a, b) { return a.start - b.start })
    if (ms.length === 0) return ""
    var t = box.text, out = "", at = 0
    ms.forEach(function (m) {
      if (m.start < at || m.start + m.len > t.length) return
      out += box._esc(t.substring(at, m.start)) + "<span style=\"color:" + page.accent + "\">" + box._esc(t.substr(m.start, m.len)) + "</span>"
      at = m.start + m.len
    })
    return box._open + out + box._esc(t.substring(at)) + "</p>"
  }
  // Replying to a passage of the agent's (2026-11-18, design A): the box
  // itself says so — a bar inside it, its number and the words, × to let
  // it go — and keeps the accent while it is a reply.
  property string replyQuote: ""
  property int replyN: 0
  signal cancelReply()
  readonly property bool replying: replyQuote !== ""

  readonly property var borderSpec: Border.controlSpec(area.activeFocus || box.replying ? "focus" : area.hovered && page.handOn ? "hover-cursor" : "normal", page.foreground, page.accent)
  FontMetrics { id: lineMetrics; font: area.font }
  readonly property real lineStep: box.leadPct > 0 ? lineMetrics.height * box.leadPct / 100 : lineMetrics.lineSpacing
  implicitHeight: Math.min(area.implicitHeight, Math.ceil(box.lineStep * box.maxLines) + area.topPadding + area.bottomPadding)

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    TextArea.flickable: TextArea {
      id: area
      focus: true
      wrapMode: TextArea.Wrap
      textFormat: TextEdit.RichText
      color: box._drawn ? "transparent" : page.foreground
      placeholderTextColor: page.faint
      selectionColor: page.palette.selection
      selectedTextColor: box._drawn ? "transparent" : page.foreground
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      // The chat's size (2026-11-22): what is written reads as it will
      // once sent, in its bubble.
      font.pixelSize: page.chatSize
      leftPadding: Style.spacing.controlPaddingX + Border.left(box.borderSpec)
      rightPadding: Style.spacing.controlPaddingX + Border.right(box.borderSpec) + (box.busy ? stopArea.width + page.sp(6) : 0)
      topPadding: Style.spacing.inputPaddingY + Border.top(box.borderSpec) + (box.replying ? replyBar.height + page.sp(6) : 0)
      bottomPadding: Style.spacing.inputPaddingY + Border.bottom(box.borderSpec)
      Keys.onPressed: function (event) {
        box.keyPressed(event)
        if (!event.accepted && box._backspace(event)) event.accepted = true
        if (!event.accepted && event.matches(StandardKey.Paste) && !area.readOnly) { box._paste(); event.accepted = true }
      }
      onTextChanged: {
        if (box._syncing) return
        var t = box._plain()
        box._syncing = true
        if (box.text !== t) box.text = t
        box._syncing = false
        box._moved(t)
      }
      Text {
        visible: box._drawn !== ""
        x: area.leftPadding
        y: area.topPadding
        width: area.width - area.leftPadding - area.rightPadding
        textFormat: Text.RichText
        wrapMode: Text.Wrap
        renderType: area.renderType
        text: box._drawn
        color: page.foreground
        font: area.font
      }
      background: BorderSurface {
        color: Style.controlFill(area.activeFocus, area.hovered, page.foreground, page.accent)
        borderSpec: box.borderSpec
        radius: Style.cornerRadius
      }
    }
  }

  // "↩ replying to ① “…”", inside the box, over what is typed.
  Item {
    id: replyBar
    visible: box.replying
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(box.borderSpec) - page.sp(4)
    anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(box.borderSpec)
    anchors.topMargin: Style.spacing.inputPaddingY + Border.top(box.borderSpec)
    height: barText.implicitHeight + page.sp(4)
    Rectangle { width: 2; height: parent.height; color: page.accent }
    Rectangle {
      id: barNumber
      x: page.sp(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, barN.implicitWidth + page.sp(8))
      height: barN.implicitHeight + page.sp(2)
      radius: height / 2
      color: page.accent
      Text {
        id: barN
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(box.replyN)
        color: page.background
        font.family: page.fontFamily
        font.pixelSize: Math.round(page.textSize * 0.68)
      }
    }
    Text {
      id: barText
      anchors.left: barNumber.right
      anchors.leftMargin: page.sp(6)
      anchors.right: barCancel.left
      anchors.rightMargin: page.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: "↩ replying to “" + box.replyQuote + "”"
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
    Text {
      id: barCancel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "× esc"
      color: cancelArea.containsMouse && page.handOn ? page.accent : page.faint
      font.family: page.fontFamily
      font.pixelSize: page.fs(Style.font.caption)
      MouseArea {
        id: cancelArea
        anchors.fill: parent
        anchors.margins: -page.sp(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: box.cancelReply()
      }
    }
  }

  // At the end of the box's last line, where the eye is after sending.
  MouseArea {
    id: stopArea
    visible: box.busy
    width: Math.round(lineMetrics.height * 1.3)
    height: width
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX - Math.round((width - stopSquare.width) / 2) + Border.right(box.borderSpec)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: area.bottomPadding + Math.round((box.lineStep - height) / 2)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: box.stop()
    Rectangle {
      id: stopSquare
      anchors.centerIn: parent
      width: Math.round(lineMetrics.height * 0.55)
      height: width
      radius: Math.min(Style.cornerRadius, Math.round(width / 4))
      color: stopArea.containsMouse && page.handOn ? page.accent : page.dim
    }
    Tip { host: box.page; shown: stopArea.containsMouse; text: box.page.tip("Stop it: what you wrote goes back in the box", "marginBack") }
  }
}
