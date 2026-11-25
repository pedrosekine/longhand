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
Item {
  id: sheet
  required property Item page
  readonly property var pal: page.palette
  property alias keysRef: keys
  property alias titleRef: titleField

  visible: page.exportOpen
  readonly property var info: page.exportData
  readonly property var rows: page.exportRows

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
      color: lookArea.containsMouse && page.handOn ? page.accent : page.foreground
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
      font.underline: lookArea.containsMouse && page.handOn
      MouseArea {
        id: lookArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { page.exportLook = page.exportLook === "omarchy" ? "minimal" : "omarchy"; keys.forceActiveFocus() }
        Tip { host: page; act: "exportLook"; shown: parent.containsMouse; text: page.tip("Switch between minimal (white) and your " + page.themeName, "exportLook") }
      }
    }
  }

  // The title: the section's upmost heading's words, to write over.
  TextField {
    id: titleField
    anchors.top: head.bottom
    anchors.topMargin: page.sp(10)
    anchors.left: parent.left
    anchors.right: parent.right
    text: page.exportTitle
    placeholderText: "a title"
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.title)
    foreground: page.foreground
    onTextEdited: page.exportTitle = text
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      var seq = Sc.fromEvent(event)
      if (seq === "Enter" || seq === "Esc" || seq === "Tab") { keys.forceActiveFocus(); event.accepted = true }
    }
  }

  // Who, which course and which day: the header under the title.
  Text {
    id: byline
    anchors.top: titleField.bottom
    anchors.topMargin: page.sp(6)
    anchors.left: parent.left
    anchors.right: parent.right
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: {
      if (!sheet.info) return ""
      var parts = [sheet.info.author || "no name yet (export.author in config.json)", sheet.info.course, sheet.info.date]
      return parts.filter(function (p) { return p }).join("   ·   ")
    }
    color: sheet.info && sheet.info.author ? page.dim : page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.bodySmall)
  }

  // From a deadline: which day's section it took, of how many (clickable ← →),
  // and whether that day was made into a PDF before — last week's diary, say.
  Column {
    id: fromLine
    anchors.top: byline.bottom
    anchors.topMargin: visible ? page.sp(6) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    visible: !!(sheet.info && sheet.info.from)
    height: visible ? implicitHeight : 0
    spacing: page.sp(2)
    Flow {
      width: parent.width
      spacing: page.sp(8)
      Text {
        textFormat: Text.PlainText
        text: {
          var f = sheet.info && sheet.info.from
          if (!f) return ""
          return "from " + Days.longLabel(f.date, page.noteService.dailyFormat()) + ", " + f.heading
        }
        color: sheet.info && sheet.info.from && sheet.info.from.before.length > 0 ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      Row {
        visible: !!(sheet.info && sheet.info.from && sheet.info.from.of > 1)
        spacing: page.sp(6)
        Text {
          textFormat: Text.PlainText
          text: "·  ←"
          color: prevSecArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
          MouseArea {
            id: prevSecArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.exportSection(-1); keys.forceActiveFocus() }
            Tip { host: page; act: "exportPrevSection"; shown: parent.containsMouse; text: page.tip("Previous matching section", "exportPrevSection") }
          }
        }
        Text {
          textFormat: Text.PlainText
          text: sheet.info && sheet.info.from ? (sheet.info.from.pick + 1) + " of " + sheet.info.from.of : ""
          color: page.dim
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        Text {
          textFormat: Text.PlainText
          text: "→"
          color: nextSecArea.containsMouse && page.handOn ? page.accent : page.dim
          font.family: page.fontFamily
          font.pixelSize: page.fs(Style.font.bodySmall)
          MouseArea {
            id: nextSecArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.exportSection(1); keys.forceActiveFocus() }
            Tip { host: page; act: "exportNextSection"; shown: parent.containsMouse; text: page.tip("Next matching section", "exportNextSection") }
          }
        }
      }
    }
    Text {
      visible: !!(sheet.info && sheet.info.from && sheet.info.from.before.length > 0)
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: sheet.info && sheet.info.from && sheet.info.from.before.length > 0
        ? "already made into a PDF from that day, as “" + sheet.info.from.before.join("”, “") + "”" : ""
      color: page.accent
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.bodySmall)
    }
  }

  Flickable {
    id: flick
    acceptedButtons: Qt.NoButton
    QC.ScrollBar.vertical: ScrollMark { page: sheet.page }
    anchors.top: fromLine.bottom
    anchors.topMargin: page.sp(18)
    anchors.left: parent.left
    anchors.right: parent.right
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
      width: parent.width
      spacing: page.sp(2)

      Repeater {
        model: sheet.rows
        Item {
          id: row
          required property var modelData
          required property int index
          readonly property bool isIn: !!page.exportPicks[modelData.hash]
          readonly property bool hot: page.exportFocus === index
          readonly property bool lit: hot && page.here === "center" && keys.activeFocus
          readonly property bool isHead: modelData.kind === "heading"
          onLitChanged: page.selected(row, "center", lit)
          width: list.width
          height: body.height + page.sp(12)

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -page.sp(8)
            anchors.rightMargin: -page.sp(8)
            radius: Style.cornerRadius
            color: row.hot ? Style.selectedFill : hover.hovered && page.handOn ? Style.hoverFill : "transparent"
          }
          HoverHandler { id: hover }

          // In or out: a filled mark or an empty one, in the gutter.
          Text {
            id: mark
            anchors.left: parent.left
            anchors.top: body.top
            textFormat: Text.PlainText
            text: row.isIn ? "●" : "○"
            color: row.isIn ? page.accent : page.faint
            font.family: page.fontFamily
            font.pixelSize: page.fs(Style.font.bodySmall)
          }

          Text {
            id: body
            anchors.left: parent.left
            anchors.leftMargin: page.sp(22)
            anchors.right: why.left
            anchors.rightMargin: page.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: row.isHead ? 1 : 3
            elide: Text.ElideRight
            text: row.isHead ? row.modelData.text.replace(/^#+\s*/, "") : row.modelData.text
            color: !row.isIn ? page.faint
              : row.isHead ? (sheet.pal.headings.length > 0 ? sheet.pal.headings[0] : page.accent)
              : page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.body)
            font.strikeout: !row.isIn && !row.isHead
          }

          // Why a block starts out, or its words when in.
          Text {
            id: why
            anchors.right: parent.right
            anchors.top: body.top
            textFormat: Text.PlainText
            text: !row.isIn ? (row.modelData.why || "left out")
              : row.modelData.words > 0 ? row.modelData.words + (row.modelData.words === 1 ? " word" : " words") : ""
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.exportFocus = row.index; page.exportToggle(row.index); keys.forceActiveFocus() }
          }
        }
      }

      Text {
        visible: sheet.rows.length === 0
        width: list.width
        textFormat: Text.PlainText
        text: page.exportBusy ? "reading the note…" : "nothing in this section to export"
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

    // Full wrapped error line (up to 3 lines) instead of truncating on one line.
    Text {
      visible: page.exportError !== ""
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
      text: page.exportError
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
        text: page.exportBusy && sheet.rows.length > 0 ? "writing the PDF…"
          : page.exportWords + (page.exportWords === 1 ? " word" : " words")
            + (sheet.info && sheet.info.pdf ? "   ·   to " + page.exportWhere : "")
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
          text: page.exportBusy ? "writing…" : "write the PDF"
          color: page.exportBusy ? page.faint : writeBtnArea.containsMouse && page.handOn ? page.accent : page.foreground
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.weight: Font.Medium
          font.pixelSize: page.fs(Style.font.bodySmall)
          font.underline: !page.exportBusy && writeBtnArea.containsMouse && page.handOn
          MouseArea {
            id: writeBtnArea
            anchors.fill: parent
            enabled: !page.exportBusy
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
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.closeExport()
            Tip { host: page; act: "exportClose"; shown: parent.containsMouse; text: page.tip("Cancel and go back", "exportClose") }
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: titleField.activeFocus ? "Enter or Esc: back to the blocks"
        : "↑↓ move · " + page.keyName("exportPick") + " in or out · " + page.keyName("exportLook") + " look · "
          + page.keyName("exportTitle") + " title · " + page.keyName("exportWrite") + " write · "
          + page.keyName("exportClose") + " cancel"
      color: page.faint
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }
  }
}
