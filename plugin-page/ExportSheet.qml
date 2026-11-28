import Quickshell
import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc
import "Days.js" as Days

// Export as a PDF (docs/plan.md item 13, slice 2, 2026-11-04): a section
// of the note, block by block, in the note's place — as a PDF is. Each
// block is in or out; what starts out says why (Longhand's agent link, a
// checkbox, private, outside the selection). The title is the section's
// upmost heading until it is written over; the look is minimal or the
// Omarchy theme's. The words are counted as blocks go in and out. The
// runner (`longhand-agent export`) lists the blocks and writes the PDF;
// nothing here changes the note. `page` is the page itself.
//
// The export pass (2026-11-28): a row shows the words that go, not the
// marks the PDF drops; one whose picture or embedded note will be missing
// says so; while the PDF is written nothing here changes what is written;
// the footer names the file and says when it replaces one; the name in
// the byline is typed here, not in config.json.
Item {
  id: sheet
  required property Item page
  readonly property var pal: page.palette
  property alias keysRef: keys
  property alias titleRef: titleField
  property alias authorRef: authorField

  visible: page.exportOpen
  readonly property var info: page.exportData
  readonly property var rows: page.exportRows
  readonly property var from: info && info.from ? info.from : null
  readonly property bool locked: page.exportWriting
  // The highest heading among the rows: the others step in under it.
  readonly property int topLevel: {
    var m = 0
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "heading" && rows[i].level > 0 && (m === 0 || rows[i].level < m)) m = rows[i].level
    return m
  }

  function toTop() { flick.contentY = 0 }
  // A screenful of rows, for PgUp/PgDn.
  function pageRows() {
    var n = rows.length
    return n === 0 ? 1 : Math.max(1, Math.floor(flick.height / Math.max(1, list.implicitHeight / n)) - 1)
  }

  Item {
    id: keys
    anchors.fill: parent
    Keys.onPressed: function (event) { if (page.exportKey(event)) event.accepted = true }
  }
  MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }

  Row {
    id: head
    anchors.top: parent.top
    anchors.left: parent.left
    spacing: page.sp(10)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "EXPORT AS A PDF"
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "·"
      color: page.faint
      font.family: page.fontFamily
      font.pixelSize: page.fs(Style.font.caption)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: page.exportLook === "omarchy" ? "look: your " + page.themeName : "look: minimal"
      color: sheet.locked ? page.faint : lookArea.containsMouse && page.handOn ? page.accent : page.foreground
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
      font.underline: !sheet.locked && lookArea.containsMouse && page.handOn
      MouseArea {
        id: lookArea
        anchors.fill: parent
        anchors.margins: -page.sp(4)
        enabled: !sheet.locked
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.exportSetLook(page.exportLook === "omarchy" ? "minimal" : "omarchy"); keys.forceActiveFocus() }
        Tip { host: page; act: "exportLook"; shown: parent.containsMouse; text: page.tip("Switch between minimal (white) and your " + page.themeName, "exportLook") }
      }
    }
  }

  // The title: the section's upmost heading's words, to write over. Esc
  // puts back what it was; Tab goes on to the name.
  property string titleWas: ""
  TextField {
    FieldMenu { page: sheet.page; field: parent }
    id: titleField
    anchors.top: head.bottom
    anchors.topMargin: page.sp(10)
    anchors.left: parent.left
    anchors.right: parent.right
    text: page.exportTitle
    readOnly: sheet.locked
    placeholderText: sheet.info ? "a title" : ""
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.title)
    foreground: page.foreground
    onTextEdited: page.exportTitle = text
    onActiveFocusChanged: if (activeFocus) sheet.titleWas = page.exportTitle
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      var seq = Sc.fromEvent(event)
      if (seq === "Esc") { page.exportTitle = sheet.titleWas; titleField.text = sheet.titleWas; keys.forceActiveFocus(); event.accepted = true }
      else if (seq === "Tab") { authorField.forceActiveFocus(); authorField.selectAll(); event.accepted = true }
      else if (seq === "Enter" || seq === "Shift+Tab") { keys.forceActiveFocus(); event.accepted = true }
    }
  }

  // Who, which course and which day: the header under the title. The name
  // is the person's to type, kept for every export after.
  property string authorWas: ""
  Row {
    id: byline
    anchors.top: titleField.bottom
    anchors.topMargin: page.sp(6)
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: page.sp(10)
    visible: !!sheet.info
    height: visible ? Math.max(authorField.implicitHeight, bylineRest.implicitHeight) : 0
    TextMetrics { id: authorMetrics; font: authorField.font; text: authorField.text || authorField.placeholderText }
    TextField {
      FieldMenu { page: sheet.page; field: parent }
      id: authorField
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(byline.width * 0.5, authorMetrics.advanceWidth + leftPadding + rightPadding + page.sp(6))
      text: sheet.info ? sheet.info.author || "" : ""
      readOnly: sheet.locked
      placeholderText: "your name"
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
      foreground: page.dim
      onActiveFocusChanged: {
        if (activeFocus) sheet.authorWas = text
        else if (text !== sheet.authorWas && sheet.info) page.setExportAuthor(text)
      }
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (page.anywhereKey(event)) { event.accepted = true; return }
        var seq = Sc.fromEvent(event)
        if (seq === "Esc") { authorField.text = sheet.authorWas; keys.forceActiveFocus(); event.accepted = true }
        else if (seq === "Shift+Tab") { page.exportEditTitle(); event.accepted = true }
        else if (seq === "Enter" || seq === "Tab") { keys.forceActiveFocus(); event.accepted = true }
      }
      Tip { host: page; shown: authorField.hovered && !authorField.activeFocus; text: "Your name on every export: kept for the next" }
    }
    Text {
      id: bylineRest
      anchors.verticalCenter: parent.verticalCenter
      width: byline.width - authorField.width - byline.spacing
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: {
        if (!sheet.info) return ""
        var parts = [sheet.info.course, sheet.info.date].filter(function (p) { return p })
        return parts.length > 0 ? "·   " + parts.join("   ·   ") : ""
      }
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
    }
  }

  // From a deadline: which day's section it took, of how many (clickable ← →),
  // and whether that section was made into a PDF before — last week's diary, say.
  Column {
    id: fromLine
    anchors.top: byline.bottom
    anchors.topMargin: visible ? page.sp(6) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    visible: !!sheet.from
    height: visible ? implicitHeight : 0
    spacing: page.sp(2)
    Item {
      width: parent.width
      height: Math.max(fromText.implicitHeight, steps.implicitHeight)
      Text {
        id: fromText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - (steps.visible ? steps.width + page.sp(10) : 0))
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: {
          var f = sheet.from
          if (!f) return ""
          return "from " + Days.longLabel(f.date, page.noteService.dailyFormat()) + ", " + f.heading
            + (f.late ? " — written after it was due" : "")
        }
        color: sheet.from && sheet.from.before.length > 0 ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      Row {
        id: steps
        anchors.left: fromText.right
        anchors.leftMargin: page.sp(10)
        anchors.verticalCenter: parent.verticalCenter
        visible: !!(sheet.from && sheet.from.of > 1)
        spacing: page.sp(8)
        readonly property bool first: !!sheet.from && sheet.from.pick <= 0
        readonly property bool last: !!sheet.from && sheet.from.pick >= sheet.from.of - 1
        readonly property bool still: page.exportBusy
        Text {
          textFormat: Text.PlainText
          text: "·"
          color: page.faint
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        Text {
          textFormat: Text.PlainText
          text: "←"
          color: steps.first || steps.still ? page.faint : prevSecArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
          MouseArea {
            id: prevSecArea
            anchors.fill: parent
            anchors.margins: -page.sp(6)
            enabled: !steps.first && !steps.still
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.exportSection(-1); keys.forceActiveFocus() }
            Tip { host: page; act: "exportPrevSection"; shown: parent.containsMouse; text: page.tip("The section found before (a likelier one)", "exportPrevSection") }
          }
        }
        Text {
          textFormat: Text.PlainText
          text: sheet.from ? (sheet.from.pick + 1) + " of " + sheet.from.of : ""
          color: page.dim
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        Text {
          textFormat: Text.PlainText
          text: "→"
          color: steps.last || steps.still ? page.faint : nextSecArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
          MouseArea {
            id: nextSecArea
            anchors.fill: parent
            anchors.margins: -page.sp(6)
            enabled: !steps.last && !steps.still
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.exportSection(1); keys.forceActiveFocus() }
            Tip { host: page; act: "exportNextSection"; shown: parent.containsMouse; text: page.tip("The next section found", "exportNextSection") }
          }
        }
      }
    }
    Text {
      visible: !!(sheet.from && sheet.from.before.length > 0)
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: sheet.from && sheet.from.before.length > 0
        ? "this section was made into a PDF before, as “" + sheet.from.before.join("”, “") + "”" : ""
      color: page.accent
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
    }
  }

  // The list runs a little past the sheet's sides, so a row's fill has
  // room for its rounded ends inside the clip, and keeps a lane on the
  // right for the scroll bar (a row's word count sat under it).
  Flickable {
    id: flick
    acceptedButtons: Qt.NoButton
    QC.ScrollBar.vertical: ScrollMark { page: sheet.page }
    anchors.top: fromLine.bottom
    anchors.topMargin: page.sp(18)
    anchors.left: parent.left
    anchors.leftMargin: -page.sp(8)
    anchors.right: parent.right
    anchors.rightMargin: -page.sp(8)
    anchors.bottom: foot.top
    anchors.bottomMargin: page.sp(12)
    clip: true
    contentWidth: width
    contentHeight: list.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    TouchScroll { flickable: flick }

    function reveal() {
      var kids = list.children
      for (var i = 0; i < kids.length; i++) {
        var k = kids[i]
        if (k.index === undefined || k.index !== page.exportFocus) continue
        if (contentY > k.y) contentY = k.y
        else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
        return
      }
    }
    Connections { target: page; function onExportFocusChanged() { Qt.callLater(flick.reveal) } }

    Column {
      id: list
      x: page.sp(8)
      width: flick.width - page.sp(16) - page.barLane
      spacing: page.sp(2)

      Repeater {
        model: sheet.rows
        Item {
          id: row
          required property var modelData
          required property int index
          readonly property bool isIn: page.exportPicked(modelData)
          readonly property bool hot: page.exportFocus === index
          readonly property bool lit: hot && page.here === "center" && keys.activeFocus
          readonly property bool isHead: modelData.kind === "heading"
          readonly property bool isCode: modelData.kind === "code"
          readonly property int level: modelData.level || 0
          readonly property var lost: modelData.lost || []
          onLitChanged: page.selected(row, "center", lit)
          width: list.width
          height: body.height + page.sp(12)

          // Lit where the keys are; the place kept, fainter, while they
          // are in the title or another pane (as in Files).
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -page.sp(8)
            anchors.rightMargin: -page.sp(8)
            radius: Style.cornerRadius
            color: row.lit ? Style.selectedFill
              : row.hot ? Qt.rgba(Style.selectedFill.r, Style.selectedFill.g, Style.selectedFill.b, 0.4)
              : hover.hovered && page.handOn ? Style.hoverFill : "transparent"
          }
          HoverHandler { id: hover }

          // In or out: a filled mark or an empty one, in the gutter, on
          // the first line's baseline.
          Text {
            id: mark
            anchors.left: parent.left
            anchors.baseline: body.baseline
            textFormat: Text.PlainText
            text: row.isIn ? "●" : "○"
            color: row.isIn ? page.accent : page.faint
            font.family: page.fontFamily
            font.pixelSize: page.fs(Style.font.bodySmall)
          }

          // The words that go (the runner's `show`: no tags, dates or
          // markdown marks), a heading stepped in under the one above it.
          Text {
            id: body
            anchors.left: parent.left
            anchors.leftMargin: page.sp(22) + (row.isHead && sheet.topLevel > 0 ? Math.max(0, row.level - sheet.topLevel) * page.sp(14) : 0)
            anchors.right: why.left
            anchors.rightMargin: page.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            wrapMode: row.isCode ? Text.NoWrap : Text.WordWrap
            maximumLineCount: row.isHead ? 1 : 3
            elide: Text.ElideRight
            text: {
              var t = row.modelData.show !== undefined ? row.modelData.show : row.modelData.text
              return row.isHead && row.modelData.show === undefined ? t.replace(/^#+\s*/, "") : t
            }
            color: !row.isIn ? page.faint
              : row.isHead ? (sheet.pal.headings.length > 0 ? sheet.pal.headings[Math.min(Math.max(row.level - 1, 0), sheet.pal.headings.length - 1)] : page.accent)
              : page.foreground
            font.family: row.isCode ? page.codeFamily : page.fontFamily
            font.styleName: row.isCode ? "" : page.fontStyle
            font.weight: row.isHead ? Font.DemiBold : Font.Normal
            font.pixelSize: page.fs(row.isCode ? Style.font.bodySmall : Style.font.body)
            font.strikeout: !row.isIn && !row.isHead
          }

          // Why a block starts out; what it will miss; or its words.
          Text {
            id: why
            anchors.right: parent.right
            anchors.baseline: body.baseline
            width: Math.min(implicitWidth, row.width * 0.4)
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            text: !row.isIn ? (row.modelData.why || "left out")
              : row.lost.length > 0 ? "not in the PDF: " + row.lost.join(", ")
              : row.modelData.words > 0 ? row.modelData.words + (row.modelData.words === 1 ? " word" : " words") : ""
            color: row.isIn && row.lost.length > 0 ? page.urgent : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }

          MouseArea {
            anchors.fill: parent
            enabled: !sheet.locked
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.exportFocus = row.index; page.exportToggle(row.index); keys.forceActiveFocus() }
          }
          Tip {
            host: page
            act: "exportPick"
            shown: hover.hovered && !sheet.locked
            text: page.tip(row.lost.length > 0 ? (row.lost.some(function (n) { return !/\.(png|jpe?g|gif|webp|svg|pdf)$/i.test(n) })
                                                  ? "An embedded note is not drawn in the PDF" : "The picture was not found")
                           : row.isIn ? "Leave it out" : "Put it in", "exportPick")
          }
        }
      }

      Text {
        visible: sheet.rows.length === 0
        width: list.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.exportListing ? "reading the note…" : page.exportError !== "" && !sheet.info ? "" : "nothing in this section to export"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.body)
      }
    }
  }

  Column {
    id: foot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: page.sp(6)

    // What went wrong, wrapped (up to 3 lines); what is missing on PATH
    // stays said until it is there, whatever else is done.
    Text {
      readonly property string said: page.exportError !== "" ? page.exportError : page.exportMissing
      visible: said !== ""
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
      text: said
      color: page.urgent
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
    }

    Item {
      width: parent.width
      height: Math.max(wordSummary.implicitHeight, exportActions.implicitHeight)
      Text {
        id: wordSummary
        anchors.left: parent.left
        anchors.right: exportActions.left
        anchors.rightMargin: page.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        text: page.exportWriting ? "writing the PDF…"
          : !sheet.info ? ""
          : page.exportWords + (page.exportWords === 1 ? " word" : " words")
            + (page.exportTarget !== "" ? "   ·   to " + page.exportTarget + (page.exportReplaces ? ", replacing the one made before" : "") : "")
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      Row {
        id: exportActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: page.sp(14)
        Text {
          textFormat: Text.PlainText
          text: page.exportWriting ? "writing…" : "write the PDF"
          color: !page.exportCanWrite ? page.faint : writeBtnArea.containsMouse && page.handOn ? page.accent : page.foreground
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.weight: Font.Medium
          font.pixelSize: page.fs(Style.font.bodySmall)
          font.underline: page.exportCanWrite && writeBtnArea.containsMouse && page.handOn
          MouseArea {
            id: writeBtnArea
            anchors.fill: parent
            anchors.margins: -page.sp(6)
            enabled: page.exportCanWrite
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: page.writeExport()
            Tip { host: page; act: "exportWrite"; shown: parent.containsMouse; text: page.tip("Write the PDF and open it", "exportWrite") }
          }
        }
        Text {
          textFormat: Text.PlainText
          text: "cancel"
          color: cancelBtnArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
          font.underline: cancelBtnArea.containsMouse && page.handOn
          MouseArea {
            id: cancelBtnArea
            anchors.fill: parent
            anchors.margins: -page.sp(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.closeExport()
            Tip { host: page; act: "exportClose"; shown: parent.containsMouse; text: page.tip(page.exportFromDash ? "Cancel, back to the dashboard" : "Cancel, back to the note", "exportClose") }
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: titleField.activeFocus ? "Enter: back to the blocks · Tab: your name · Esc: as it was"
        : authorField.activeFocus ? "Enter: keep the name, for every export · Esc: as it was"
        : "↑↓ move · " + page.keyName("exportPick") + " in or out · "
          + (sheet.from && sheet.from.of > 1 ? "← → section · " : "")
          + page.keyName("exportLook") + " look · "
          + page.keyName("exportTitle") + " title · " + page.keyName("exportWrite") + " write · "
          + page.keyName("exportClose") + " cancel"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
