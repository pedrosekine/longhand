import QtQuick
import qs.Commons
import qs.Ui

// The switcher (Ctrl+O; docs/keys-proposal.md's "find anything", built for
// projects first on 2026-11-17, plan.md item 19): "#th" Enter reaches
// #thesis from anywhere, not only the sidebar. A box over the middle, the
// projects matching what is typed under it (Tags.reach), each with its
// Alt+digit so the shorter way is learnt from the longer. `page` is the page.
Rectangle {
  id: sw
  required property Item page
  property alias fieldRef: field

  visible: page.switcherOpen
  z: 90
  width: Math.min(page.sp(440), parent.width - page.sp(32))
  x: Math.round((parent.width - width) / 2)
  y: page.sp(56)
  height: col.implicitHeight + page.sp(20)
  radius: Style.cornerRadius
  color: page.background
  border.width: 1
  border.color: page.faint

  // A click outside the box is no click into it; inside, the keys stay in the field.
  MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: page.sp(10)
    spacing: page.sp(6)

    TextField {
      id: field
      width: parent.width
      placeholderText: "#tag or the project's name"
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.body)
      foreground: page.foreground
      onTextChanged: page.switcherText = text
      Keys.onPressed: function (event) {
        if (page.anywhereKey(event)) { event.accepted = true; return }
        if (page.switcherKey(event)) event.accepted = true
      }
      // The keys gone elsewhere (a click in a pane) close it, as a menu does.
      onActiveFocusChanged: if (!activeFocus && page.switcherOpen && !sw.clicking) Qt.callLater(sw.letGo)
    }

    Repeater {
      model: page.switcherMatches
      Rectangle {
        id: matchRow
        required property var modelData
        required property int index
        readonly property int place: page.projectIndex(modelData.tag)
        width: col.width
        height: matchCol.implicitHeight + page.sp(6)
        radius: Style.cornerRadius
        color: page.switcherPick === index ? Style.selectedFill : matchArea.containsMouse && page.handOn ? Style.hoverFill : "transparent"
        Column {
          id: matchCol
          anchors.left: parent.left
          anchors.right: keyText.left
          anchors.leftMargin: page.sp(4)
          anchors.rightMargin: page.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "#" + modelData.tag + "  " + (modelData.name || "")
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            visible: !!modelData.next
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: page.sessionLabel(modelData.next)
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }
        }
        // Its own key, from anywhere: the next time, one chord.
        Text {
          id: keyText
          anchors.right: parent.right
          anchors.rightMargin: page.sp(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: matchRow.place >= 0 && matchRow.place < 9 ? "Alt+" + (matchRow.place + 1) : ""
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
        MouseArea {
          id: matchArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPressed: sw.clicking = true
          onReleased: sw.clicking = false
          onClicked: { page.switcherPick = matchRow.index; page.switcherGo(false) }
        }
      }
    }

    Text {
      width: parent.width
      visible: page.switcherMatches.length === 0
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.projects.length === 0 ? "no projects yet: “+ new project” in the sidebar makes one"
        : "no project has “" + page.switcherText.replace(/^#/, "") + "” in its tag or name"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }

    Text {
      width: parent.width
      topPadding: page.sp(2)
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.keyName("switchUp") + page.keyName("switchDown") + " pick · " + page.keyName("switchGo") + " its notes · "
        + page.keyName("switchPage") + " its page · " + page.keyName("switchClose") + " back"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }

  // A press on a row takes the keys from the field for a moment; that is
  // the row being chosen, not the switcher being left.
  property bool clicking: false
  function letGo() {
    if (!page.switcherOpen || field.activeFocus) return
    page.switcherOpen = false
  }
}
