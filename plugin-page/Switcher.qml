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
  width: Math.min(page.sp(520), parent.width - page.sp(32))
  x: Math.round((parent.width - width) / 2)
  y: page.sp(56)
  height: col.implicitHeight + page.sp(20)
  radius: page.overlayRadius
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
      placeholderText: "project, note, paper, view… or ? words to search all notes"
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

    Flickable {
      id: listFlick
      width: col.width
      height: Math.min(listCol.implicitHeight, page.sp(360))
      contentWidth: width
      contentHeight: listCol.implicitHeight
      clip: true
      visible: page.switcherMatches.length > 0
      boundsBehavior: Flickable.StopAtBounds
      Connections {
        target: page
        function onSwitcherPickChanged() {
          var it = listRep.itemAt(page.switcherPick)
          if (!it) return
          if (it.y < listFlick.contentY) listFlick.contentY = it.y
          else if (it.y + it.height > listFlick.contentY + listFlick.height)
            listFlick.contentY = Math.max(0, it.y + it.height - listFlick.height)
        }
      }
      Column {
        id: listCol
        width: listFlick.width
        spacing: page.sp(2)
        Repeater {
          id: listRep
          model: page.switcherMatches
          Rectangle {
            id: matchRow
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind || "project"
            readonly property int place: kind === "project" ? page.projectIndex(modelData.tag) : -1
            readonly property string mainText: kind === "project"
              ? ("#" + modelData.tag + "  " + (modelData.name || ""))
              : (modelData.title || "")
            readonly property string subText: kind === "project"
              ? (modelData.next ? page.sessionLabel(modelData.next) : "")
              : (modelData.sub || "")
            readonly property string rightText: kind === "project"
              ? (matchRow.place >= 0 && matchRow.place < 9 ? "Alt+" + (matchRow.place + 1) : "")
              : (modelData.hint || "")
            width: listCol.width
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
                text: matchRow.mainText
                color: matchRow.kind === "search" ? page.accent : page.foreground
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.bodySmall)
              }
              Text {
                visible: matchRow.subText !== ""
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: matchRow.subText
                color: page.dim
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
              }
            }
            // Its shortcut or kind on the right: the shorter way learnt from the longer.
            Text {
              id: keyText
              anchors.right: parent.right
              anchors.rightMargin: page.sp(4)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: matchRow.rightText
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
      }
    }

    Text {
      width: parent.width
      visible: page.switcherMatches.length === 0
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: {
        var raw = page.switcherText.trim()
        if (raw.charAt(0) === "?") {
          var q = raw.slice(1).trim()
          if (q === "") return "type words to search across all your notes (including private)"
          if (page.switcherFinding) return "searching all notes for “" + q + "”…"
          return "no note holds “" + q + "”"
        }
        if (page.projects.length === 0 && raw === "") return "type a note, paper or view, or ? words to search all notes"
        return "no match for “" + raw.replace(/^#/, "") + "”"
      }
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
      text: page.switcherText.trim().charAt(0) === "?"
        ? page.keyName("switchUp") + page.keyName("switchDown") + " pick · " + page.keyName("switchGo") + " jump to line · " + page.keyName("switchClose") + " back"
        : page.keyName("switchUp") + page.keyName("switchDown") + " pick · " + page.keyName("switchGo") + " open · "
          + page.keyName("switchPage") + " project page · ? search all notes · " + page.keyName("switchClose") + " back"
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
