import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui
import "Switch.js" as Switch

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
  // Nearer the top in a short window, and never past its foot (a high zoom
  // or a short tile cut the list off).
  y: Math.max(page.sp(8), Math.min(page.sp(56), Math.round(parent.height * 0.08)))
  height: col.implicitHeight + page.sp(20)
  radius: page.overlayRadius
  color: page.background
  border.width: 1
  border.color: page.faint

  // A click outside the box is no click into it; inside, the keys stay in the field.
  // The wheel over the box stays in it: at the list's end, or with no list
  // to scroll, it scrolled the note underneath (2026-11-25, the mouse pass).
  MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus(); onWheel: function (wheel) { wheel.accepted = true } }

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: page.sp(10)
    spacing: page.sp(6)

    TextField {
      FieldMenu { page: sw.page; field: parent }
      id: field
      width: parent.width
      placeholderText: "project, note, paper, view… or ? words to search all notes"
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.body)
      foreground: page.foreground
      onTextChanged: page.switcherText = text
      Keys.onPressed: function (event) {
        if (page.switcherFirst(event)) { event.accepted = true; return }
        if (page.anywhereKey(event)) { event.accepted = true; return }
        if (page.switcherKey(event)) event.accepted = true
      }
      // The keys gone elsewhere (a click in a pane) close it, as a menu does.
      onActiveFocusChanged: if (!activeFocus && page.switcherOpen && !sw.clicking) Qt.callLater(sw.letGo)
    }

    Flickable {
      id: listFlick
      acceptedButtons: Qt.NoButton
      QC.ScrollBar.vertical: ScrollMark { page: sw.page }
      TouchScroll { flickable: listFlick }
      width: col.width
      height: Math.max(0, Math.min(listCol.implicitHeight, page.sp(360), sw.room))
      contentWidth: width
      contentHeight: listCol.implicitHeight
      clip: true
      visible: page.switcherMatches.length > 0
      boundsBehavior: Flickable.StopAtBounds
      Connections {
        target: page
        function onSwitcherPickChanged() { sw.reveal() }
        // Other words, other rows: from the top (a wheel or an earlier
        // pick left the list scrolled down over the new ones).
        function onSwitcherTextChanged() { listFlick.contentY = 0 }
        function onSwitcherMatchesChanged() { Qt.callLater(sw.reveal) }
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
            // A key on the right is a key; a file's kind (note, day, pdf) is not one.
            readonly property bool rightIsKind: kind === "file" || kind === "hit"
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
              // What was matched, in bold.
              Text {
                width: parent.width
                textFormat: matchRow.kind === "search" ? Text.PlainText : Text.StyledText
                elide: Text.ElideRight
                text: matchRow.kind === "search" ? matchRow.mainText : Switch.marked(matchRow.mainText, sw.words)
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
              font.italic: matchRow.rightIsKind
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
              onCanceled: sw.clicking = false   // dragged off the row: no click, and the field's focus counts again
              // Shift+click is Shift+Enter: a project's page.
              onClicked: function (mouse) { page.switcherPick = matchRow.index; page.switcherGo(!!(mouse.modifiers & Qt.ShiftModifier)) }
            }
          }
        }
      }
    }

    // How the search stands: looking, failed, nothing, or the best of how
    // many; the names still being read.
    Text {
      id: status
      width: parent.width
      text: sw.statusText
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }

    // The keys for what is picked: Shift+Enter only over a project, the one
    // row it does something else for.
    Text {
      id: foot
      width: parent.width
      topPadding: page.sp(2)
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: page.switcherAsking
        ? page.keyName("switchUp") + page.keyName("switchDown") + " pick · " + page.keyName("switchGo") + " jump to line · " + page.keyName("switchClose") + " back"
        : page.keyName("switchUp") + page.keyName("switchDown") + " pick · " + page.keyName("switchGo") + " open · "
          + (sw.pickedProject ? page.keyName("switchPage") + " project page · " : "") + "? search all notes · " + page.keyName("switchClose") + " back"
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
    page.switcherDone()
  }

  readonly property var picked: page.switcherMatches[page.switcherPick]
  readonly property bool pickedProject: !!sw.picked && (sw.picked.kind || "project") === "project"
  // The words to mark in the rows: `? words`, else what is typed (a `#` is the key, not a letter).
  readonly property string words: page.switcherAsking ? page.switcherWords : page.switcherText.trim().replace(/^#/, "")
  readonly property string statusText: {
    var raw = page.switcherText.trim()
    var n = page.switcherMatches.length
    if (page.switcherAsking) {
      var q = page.switcherWords
      if (q === "") return "type words to search across all your notes (including private)"
      if (page.switcherFindError !== "") return "the search did not run: " + page.switcherFindError
      if (page.switcherFinding) return "searching all notes for “" + q + "”…"
      if (n === 0) return "no note holds “" + q + "”"
      if (page.switcherFindTotal > n) return "the best " + n + " of " + page.switcherFindTotal + " lines · more words narrow it"
      return ""
    }
    if (n === 0) {
      if (page.projects.length === 0 && raw === "") return "type a note, paper or view, or ? words to search all notes"
      return "no match for “" + raw.replace(/^#/, "") + "”"
    }
    if (raw !== "" && raw.charAt(0) !== "#" && page.vaultIndex === null && page.vaultIndexReading) return "reading the names of your notes…"
    return ""
  }
  // What the list may take of the window, below the field and above the keys.
  readonly property real room: (parent ? parent.height : 0) - sw.y - page.sp(8) - page.sp(20) - field.height - foot.implicitHeight
    - (status.visible ? status.implicitHeight + col.spacing : 0) - col.spacing * 2
  function reveal() {
    var it = listRep.itemAt(page.switcherPick)
    if (!it) return
    if (it.y < listFlick.contentY) listFlick.contentY = it.y
    else if (it.y + it.height > listFlick.contentY + listFlick.height)
      listFlick.contentY = Math.max(0, it.y + it.height - listFlick.height)
  }
  // PgUp / PgDn: a screenful of rows, one kept in sight from the last.
  function screenRows() {
    var it = listRep.itemAt(0)
    return it ? Math.max(1, Math.floor(listFlick.height / (it.height + listCol.spacing)) - 1) : 5
  }
}
