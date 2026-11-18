import QtQuick
import qs.Commons
import "Shortcuts.js" as Sc

// Answers being written to passages of the agent's (2026-11-18): each the
// words picked, quoted, with a field of its own under it. Over the box, in
// the order picked; another passage adds another. Enter in any sends them
// all with the box (Page.composed); Backspace in an empty one, or its ×,
// lets it go; Esc goes back to the box.
Column {
  id: drafts
  required property Item page
  property string pane: "day"
  property Item box: null              // the pane's own box, where Esc goes back to
  signal send()
  readonly property var list: pane === "margin" ? page.marginReplies : page.dayReplies
  visible: list.length > 0
  spacing: page.sp(6)

  Repeater {
    model: drafts.list
    Column {
      id: draft
      required property var modelData
      required property int index
      width: drafts.width
      spacing: page.sp(3)
      Item {
        width: parent.width
        height: quoteText.implicitHeight
        Text {
          id: quoteText
          anchors.left: parent.left
          anchors.right: drop.left
          anchors.rightMargin: page.sp(8)
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          text: "“" + draft.modelData.quote + "”"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.italic: true
          font.pixelSize: page.fs(Style.font.caption)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.showPassage(drafts.pane, draft.modelData.quote)
          }
        }
        Text {
          id: drop
          anchors.right: parent.right
          anchors.top: parent.top
          textFormat: Text.PlainText
          text: "×"
          color: dropArea.containsMouse ? page.accent : page.faint
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.caption)
          MouseArea {
            id: dropArea
            anchors.fill: parent
            anchors.margins: -page.sp(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.dropReply(drafts.pane, draft.index); if (drafts.box) drafts.box.forceActiveFocus() }
          }
        }
      }
      ChatField {
        id: field
        page: drafts.page
        width: parent.width
        height: implicitHeight
        placeholderText: "your answer to this…"
        text: draft.modelData.text || ""
        onTextChanged: draft.modelData.text = text            // kept on the draft, the list not replaced
        Component.onCompleted: if (page.replyFocus === draft.index) { page.replyFocus = -1; field.forceActiveFocus() }
        onKeyPressed: function (event) {
          if (Sc.hit(event, "chatSend")) { drafts.send(); event.accepted = true; return }
          if (Sc.hit(event, "marginBack")) { if (drafts.box) drafts.box.forceActiveFocus(); event.accepted = true; return }
          if (event.key === Qt.Key_Backspace && field.text === "") {
            page.dropReply(drafts.pane, draft.index)
            if (drafts.box) drafts.box.forceActiveFocus()
            event.accepted = true
          }
        }
      }
    }
  }
}
