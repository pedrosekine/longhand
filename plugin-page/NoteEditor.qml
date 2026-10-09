import QtQuick
import "Rows.js" as Rows

// The sheet's editor: the note drawn, not shown as markdown.
//
// One text field per line, each holding only the words. A heading is set
// large, a checkbox is a box you can click (or Ctrl+L), a bullet is a dot, a
// number is a number, a quote or callout carries a bar, and a private callout
// says so. Blank lines are drawn as space between blocks — more than between
// the lines of one block — so the block the agent answers is the block you
// see. Typing the markdown (`# `, `- [ ] `, `> `) turns the line into that
// kind on the spot; Backspace at the start of a line takes the kind off.
//
// Underneath it is still one plain text: `text` is the note body exactly as
// it goes to disk, `cursorPosition` an offset into it, and `insert`/`remove`
// edit it like the TextEdit this replaced. Every edit goes through that text
// and the rows are re-derived from it, so nothing is ever written that the
// student did not type.
//
// Keys the page owns (Esc, the send prompt, block jumps, the margin) reach
// `keyFilter` first; whatever it does not take is editing.
Item {
  id: ed

  property string text: ""
  property int cursorPosition: 0
  readonly property int length: text.length

  // function (event) -> bool; true when the page consumed the key.
  property var keyFilter: null

  property string fontFamily: "sans-serif"
  property int textSize: 16
  property color foreground: "black"
  property color background: "white"
  property color dim: "gray"
  property color faint: "lightgray"
  property color selectionColor: "lightblue"
  property real tabStop: textSize * 2

  // Space: within a block nothing, between blocks without a blank line a
  // little, across a blank line clearly more.
  readonly property int blockGap: Math.round(textSize * 0.85)
  readonly property int smallGap: Math.round(textSize * 0.3)
  readonly property int markerWidth: Math.round(textSize * 1.5)
  readonly property int quoteWidth: Math.round(textSize * 0.9)

  // Which row holds the keyboard focus (-1: none), and the cursor in
  // editor coordinates, for the page to keep in view and to hang the send
  // prompt under.
  property int focusedRow: -1
  readonly property bool hasFocus: focusedRow >= 0
  property rect cursorRect: Qt.rect(0, 0, 0, 0)

  // Enter finished a line (the line as it was before the break), and Enter
  // on an empty item left a list. The page decides what they mean.
  signal returnFinished(int lineIndex, string lineText)
  signal listLeft(int lineIndex)

  implicitHeight: column.height

  property var rows: []          // Rows.derive(text), kept in step with the model
  property bool syncing: false
  property var undoStack: []
  property var redoStack: []
  property double lastSnapshot: 0

  // ------------------------------------------------------------ the text

  // Replace everything (a load from disk). The cursor goes to the end and
  // the undo history starts over.
  function load(t) {
    ed.undoStack = []
    ed.redoStack = []
    ed.commit(t, t.length)
    ed.placeCursor(false)
  }

  // Programmatic edits, with the cursor carried along the way TextEdit
  // carries it: text inserted at or before the cursor pushes it forward.
  function replace(a, b, s) {
    var cur = ed.cursorPosition
    if (cur >= b) cur += s.length - (b - a)
    else if (cur > a) cur = a + s.length
    ed.commit(ed.text.slice(0, a) + s + ed.text.slice(b), cur)
    ed.placeCursor(false)
  }
  function insert(pos, s) { ed.replace(pos, pos, s) }
  function remove(a, b) { ed.replace(a, b, "") }

  // Move the cursor. With `focus`, the note takes the keyboard too;
  // otherwise the field only follows when the note already has it.
  function setCursor(pos, focus) {
    ed.cursorPosition = Math.max(0, Math.min(ed.text.length, pos))
    ed.placeCursor(focus === true)
  }

  function focusNote() { ed.placeCursor(true) }

  function commit(t, cur) {
    ed.cursorPosition = Math.max(0, Math.min(t.length, cur))
    if (t !== ed.text) {
      ed.text = t
      ed.syncRows()
    } else if (ed.rows.length === 0) {
      ed.syncRows()
    }
  }

  // ------------------------------------------------------------ undo

  // Typing within a moment of the last edit joins its undo step; anything
  // structural (Enter, merging lines, ticking) is a step of its own.
  function snapshot(force) {
    var now = Date.now()
    var join = !force && now - ed.lastSnapshot < 900
    ed.lastSnapshot = force ? 0 : now
    if (join && ed.undoStack.length > 0) return
    var s = ed.undoStack.slice(Math.max(0, ed.undoStack.length - 299))
    s.push({ text: ed.text, cursor: ed.cursorPosition })
    ed.undoStack = s
    ed.redoStack = []
  }

  function undo() {
    if (ed.undoStack.length === 0) return
    var s = ed.undoStack[ed.undoStack.length - 1]
    ed.undoStack = ed.undoStack.slice(0, -1)
    ed.redoStack = ed.redoStack.concat([{ text: ed.text, cursor: ed.cursorPosition }])
    ed.lastSnapshot = 0
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  function redo() {
    if (ed.redoStack.length === 0) return
    var s = ed.redoStack[ed.redoStack.length - 1]
    ed.redoStack = ed.redoStack.slice(0, -1)
    ed.undoStack = ed.undoStack.concat([{ text: ed.text, cursor: ed.cursorPosition }])
    ed.lastSnapshot = 0
    ed.commit(s.text, s.cursor)
    ed.placeCursor(true)
  }

  // ------------------------------------------------------------ rows

  readonly property var roles: ["kind", "body", "level", "checked", "ordinal", "headingLevel", "callout", "priv", "blank", "lead", "gapAbove"]

  function roleValues(r) {
    var o = {}
    for (var k = 0; k < ed.roles.length; k++) o[ed.roles[k]] = r[ed.roles[k]]
    return o
  }

  // Bring the model in line with the text, touching only the rows that
  // changed, so the field being typed in is never rebuilt under the cursor.
  function syncRows() {
    var next = Rows.derive(ed.text)
    var prev = ed.rows
    var a = 0
    while (a < prev.length && a < next.length && prev[a].raw === next[a].raw) a++
    var b = 0
    while (b < prev.length - a && b < next.length - a
           && prev[prev.length - 1 - b].raw === next[next.length - 1 - b].raw) b++
    var oldMid = prev.length - a - b
    var newMid = next.length - a - b
    ed.syncing = true
    ed.rows = next
    if (oldMid > newMid) rowModel.remove(a + newMid, oldMid - newMid)
    for (var k = oldMid; k < newMid; k++) rowModel.insert(a + k, ed.roleValues(next[a + k]))
    for (var i = 0; i < next.length; i++) {
      var cur = rowModel.get(i)
      for (var r = 0; r < ed.roles.length; r++) {
        var role = ed.roles[r]
        if (cur[role] !== next[i][role]) rowModel.setProperty(i, role, next[i][role])
      }
      // Typing `>` into an empty line leaves the body empty, as it was:
      // the role does not change, but the field still shows the `>`.
      var item = rep.itemAt(i)
      if (item && item.field.text !== next[i].body) item.field.text = next[i].body
    }
    ed.syncing = false
  }

  function rowItem(i) { return i >= 0 ? rep.itemAt(i) : null }

  // The field follows `cursorPosition`.
  function placeCursor(focus) {
    if (ed.rows.length === 0) return
    var i = Rows.rowAt(ed.rows, ed.cursorPosition)
    var r = ed.rows[i]
    var col = Rows.columnIn(r, ed.cursorPosition)
    ed.cursorPosition = r.start + r.prefixLen + col
    var item = ed.rowItem(i)
    if (!item) return
    if (focus || ed.hasFocus) item.field.forceActiveFocus()
    if (item.field.cursorPosition !== col) item.field.cursorPosition = col
    ed.updateCursorRect()
  }

  function placeAt(i, col) {
    var r = ed.rows[i]
    ed.setCursor(r.start + r.prefixLen + Math.max(0, Math.min(r.body.length, col)), true)
  }

  // Rows just inserted have no place in the column until it lays out, so
  // lay out first; and whenever the column moves, the cursor moved too.
  function updateCursorRect() {
    var item = ed.rowItem(ed.focusedRow)
    if (!item) return
    column.forceLayout()
    var c = item.field.cursorRectangle
    var p = item.field.mapToItem(ed, c.x, c.y)
    ed.cursorRect = Qt.rect(p.x, p.y, c.width, c.height)
  }

  // A run of lines in editor coordinates — what the page veils and marks.
  function blockRect(startLine, endLine) {
    column.forceLayout()
    var a = ed.rowItem(startLine)
    var b = ed.rowItem(endLine - 1)
    if (!a || !b) return null
    var y = a.y + a.gapTop
    return { y: y, h: b.y + b.height - y }
  }

  // ------------------------------------------------------------ editing

  // A field changed under the student's fingers.
  function typed(i, body, col) {
    var r = ed.rows[i]
    if (!r) return
    body = body.replace(/\r/g, "")
    var line = r.raw.substring(0, r.prefixLen) + body
    ed.snapshot(/\n/.test(body))
    var lineEnd = r.start + r.raw.length
    var before = ed.rows.length
    ed.commit(ed.text.slice(0, r.start) + line + ed.text.slice(lineEnd), r.start + r.prefixLen + col)
    // The line changed kind (markdown typed or broken) or a paste brought
    // new lines: the field's text moved, so put the cursor back.
    var now = ed.rows[i]
    if (ed.rows.length !== before || !now || now.body !== body) ed.placeCursor(true)
    else ed.updateCursorRect()
  }

  function fieldCursor(i, col) {
    var r = ed.rows[i]
    if (!r) return
    ed.cursorPosition = r.start + r.prefixLen + col
    ed.updateCursorRect()
  }

  function selectionRange(item) {
    var r = ed.rows[item.index]
    var f = item.field
    return { a: r.start + r.prefixLen + f.selectionStart, b: r.start + r.prefixLen + f.selectionEnd }
  }

  function returnKey(item, soft) {
    var i = item.index
    ed.snapshot(true)
    if (item.field.selectedText !== "") {
      var sel = ed.selectionRange(item)
      ed.remove(sel.a, sel.b)
    }
    var r = ed.rows[i]
    var pos = ed.cursorPosition
    var lineText = r.raw
    var lineEnd = r.start + r.raw.length
    var carry = (r.kind === "code" || r.kind === "front") ? "" : Rows.continuation(r)
    if (soft) {
      // A new line in the same block: under a list item, indented to stay
      // part of it; in a quote, still quoted.
      var under = (r.kind === "task" || r.kind === "bullet" || r.kind === "ordered") ? r.indent + "  "
        : (carry === "> " ? "> " : r.indent)
      ed.insert(pos, "\n" + under)
      return
    }
    if (carry !== "" && r.body === "" && pos >= lineEnd && r.kind !== "calloutHead") {
      // Enter on an empty item leaves the list (or the quote).
      ed.remove(r.start, lineEnd)
      if (r.kind !== "quote") ed.listLeft(i)
      return
    }
    ed.insert(pos, "\n" + carry)
    ed.returnFinished(i, lineText)
  }

  // Backspace at the start of a line: first the kind goes, then the
  // indentation, then the line joins the one above.
  function backspaceAtStart(i) {
    var r = ed.rows[i]
    ed.snapshot(true)
    if (r.marker !== "") ed.remove(r.start + r.indent.length, r.start + r.prefixLen)
    else if (r.indent !== "") ed.remove(r.start, r.start + r.indent.length)
    else if (i > 0) ed.remove(r.start - 1, r.start)
    ed.placeCursor(true)
  }

  // Delete at the end of a line pulls the next line's words up, without
  // its markdown.
  function deleteAtEnd(i) {
    if (i + 1 >= ed.rows.length) return
    var r = ed.rows[i]
    var n = ed.rows[i + 1]
    ed.snapshot(true)
    ed.remove(r.start + r.raw.length, n.start + n.prefixLen)
    ed.placeCursor(true)
  }

  function indent(i, out) {
    var r = ed.rows[i]
    var listy = r.kind === "task" || r.kind === "bullet" || r.kind === "ordered"
    ed.snapshot(true)
    if (out) {
      if (r.indent.charAt(0) === "\t") ed.remove(r.start, r.start + 1)
      else if (r.indent !== "") ed.remove(r.start, r.start + Math.min(2, r.indent.length))
    } else if (listy || r.indent !== "") {
      ed.insert(r.start, "\t")
    } else {
      ed.insert(ed.cursorPosition, "\t")
    }
    ed.placeCursor(true)
  }

  // Ctrl+L or a click: tick or untick a checkbox; on a bullet or a plain
  // line, make it a checkbox.
  function toggleCheckbox(i) {
    var r = ed.rows[i]
    if (!r) return
    ed.snapshot(true)
    if (r.kind === "task") {
      var at = r.start + r.indent.length + 3
      ed.replace(at, at + 1, r.checked ? " " : "x")
    } else if (r.kind === "bullet") {
      ed.insert(r.start + r.prefixLen, "[ ] ")
    } else if (r.kind === "plain" || r.kind === "blank") {
      ed.insert(r.start + r.indent.length, "- [ ] ")
    }
    ed.placeCursor(false)
  }

  function clickCheckbox(i) {
    ed.placeAt(i, ed.rows[i].body.length)
    ed.toggleCheckbox(i)
  }

  function atFirstLine(f) { return f.cursorRectangle.y <= f.positionToRectangle(0).y + 1 }
  function atLastLine(f) { return f.cursorRectangle.y >= f.positionToRectangle(f.length).y - 1 }

  // Up / Down past the edge of a field: the neighbouring line, at the same
  // horizontal place.
  function moveVertical(item, dir) {
    var j = Rows.nextTextRow(ed.rows, item.index, dir)
    if (j < 0) {
      ed.placeAt(item.index, dir < 0 ? 0 : ed.rows[item.index].body.length)
      return
    }
    var x = item.field.x + item.field.cursorRectangle.x
    var target = ed.rowItem(j)
    var f = target.field
    var col = f.positionAt(x - f.x, dir > 0 ? 1 : f.contentHeight - 1)
    ed.placeAt(j, col)
  }

  function key(event, item) {
    var f = item.field
    var i = item.index
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier
    var alt = event.modifiers & Qt.AltModifier
    var k = event.key
    var noSel = f.selectedText === ""

    if (ed.keyFilter && ed.keyFilter(event)) { event.accepted = true; return }

    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !ctrl && !alt) {
      ed.returnKey(item, shift)
    } else if (k === Qt.Key_Backspace && noSel && f.cursorPosition === 0) {
      ed.backspaceAtStart(i)
    } else if (k === Qt.Key_Delete && noSel && f.cursorPosition === f.length && !ctrl) {
      ed.deleteAtEnd(i)
    } else if (k === Qt.Key_Up && !ctrl && !alt && !shift && ed.atFirstLine(f)) {
      ed.moveVertical(item, -1)
    } else if (k === Qt.Key_Down && !ctrl && !alt && !shift && ed.atLastLine(f)) {
      ed.moveVertical(item, 1)
    } else if (k === Qt.Key_Left && !ctrl && !alt && !shift && noSel && f.cursorPosition === 0) {
      var p = Rows.nextTextRow(ed.rows, i, -1)
      if (p >= 0) ed.placeAt(p, ed.rows[p].body.length)
    } else if (k === Qt.Key_Right && !ctrl && !alt && !shift && noSel && f.cursorPosition === f.length) {
      var n = Rows.nextTextRow(ed.rows, i, 1)
      if (n >= 0) ed.placeAt(n, 0)
    } else if (k === Qt.Key_Tab && !ctrl && !alt) {
      ed.indent(i, false)
    } else if (k === Qt.Key_Backtab) {
      ed.indent(i, true)
    } else if (k === Qt.Key_Z && ctrl) {
      if (shift) ed.redo()
      else ed.undo()
    } else if (k === Qt.Key_Y && ctrl) {
      ed.redo()
    } else if (k === Qt.Key_L && ctrl) {
      ed.toggleCheckbox(i)
    } else if (k === Qt.Key_Home && ctrl) {
      ed.setCursor(0, true)
    } else if (k === Qt.Key_End && ctrl) {
      ed.setCursor(ed.text.length, true)
    } else if (event.text === " " && noSel && f.length === 0 && /\s$/.test(ed.rows[i].marker)) {
      // The marker already ends in a space; "- [] " should not leave two.
    } else if (event.text === "]" && noSel) {
      // "- []" or a bare "[]" at the start of a line is what fingers
      // type; "- [ ] " is what markdown wants.
      var r = ed.rows[i]
      var before = r.raw.substring(0, ed.cursorPosition - r.start)
      if (/^\s*[-*+] \[$/.test(before)) {
        ed.snapshot(true)
        ed.insert(ed.cursorPosition, " ] ")
      } else if (/^\s*\[$/.test(before)) {
        ed.snapshot(true)
        ed.replace(r.start, ed.cursorPosition, before.replace("[", "- [ ] "))
      } else {
        return
      }
    } else {
      return
    }
    event.accepted = true
  }

  // ------------------------------------------------------------ drawing

  ListModel { id: rowModel }

  Column {
    id: column
    width: ed.width
    onHeightChanged: Qt.callLater(ed.updateCursorRect)

    Repeater {
      id: rep
      model: rowModel

      Item {
        id: row
        required property int index
        required property string kind
        required property string body
        required property int level
        required property bool checked
        required property string ordinal
        required property int headingLevel
        required property string callout
        required property bool priv
        required property bool blank
        required property bool lead
        required property bool gapAbove

        property alias field: field
        readonly property bool listy: kind === "task" || kind === "bullet" || kind === "ordered"
        readonly property bool quoted: kind === "quote" || kind === "calloutHead"
        readonly property int gapTop: gapAbove ? ed.smallGap : 0
        readonly property real indentX: level * ed.markerWidth
        readonly property real labelWidth: kind === "calloutHead" ? label.implicitWidth + Math.round(ed.textSize * 0.4) : 0
        readonly property real fieldX: indentX + (listy ? ed.markerWidth : (quoted ? ed.quoteWidth : 0)) + labelWidth
        readonly property real firstLine: fm.height

        width: column.width
        height: blank && !field.activeFocus ? (lead ? 0 : ed.blockGap) : gapTop + field.height

        onBodyChanged: if (field.text !== body) field.text = body
        Component.onCompleted: field.text = body

        FontMetrics { id: fm; font: field.font }

        // A click beside the words (the indent, the space of a blank line)
        // lands on this line; on a blank line it opens a line to write on.
        MouseArea {
          anchors.fill: parent
          onClicked: function (mouse) {
            ed.placeAt(row.index, row.blank ? 0 : field.positionAt(mouse.x - field.x, mouse.y - field.y))
          }
        }

        Rectangle {
          visible: row.quoted
          x: row.indentX + Math.round(ed.textSize * 0.15)
          width: Math.max(2, Math.round(ed.textSize * 0.12))
          height: row.height
          radius: width / 2
          color: row.priv ? ed.dim : ed.faint
        }

        Text {
          id: label
          visible: row.kind === "calloutHead"
          x: row.indentX + ed.quoteWidth
          y: row.gapTop + (row.firstLine - height) / 2
          textFormat: Text.PlainText
          text: row.callout === "private" ? "private · never sent" : row.callout
          color: ed.dim
          font.family: ed.fontFamily
          font.pixelSize: Math.round(ed.textSize * 0.72)
          font.letterSpacing: 0.4
        }

        Rectangle {
          id: box
          readonly property int size: Math.round(ed.textSize * 0.72)
          visible: row.kind === "task"
          x: row.indentX + Math.round((ed.markerWidth - size) / 2) - Math.round(ed.textSize * 0.15)
          y: row.gapTop + Math.round((row.firstLine - size) / 2)
          width: size
          height: size
          radius: Math.max(2, Math.round(size * 0.22))
          color: row.checked ? ed.dim : "transparent"
          border.width: row.checked ? 0 : Math.max(1, Math.round(ed.textSize * 0.08))
          border.color: ed.dim

          Text {
            anchors.centerIn: parent
            visible: row.checked
            textFormat: Text.PlainText
            text: "✓"
            color: ed.background
            font.family: ed.fontFamily
            font.pixelSize: Math.round(box.size * 0.85)
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Math.round(ed.textSize * 0.25)
            cursorShape: Qt.PointingHandCursor
            onClicked: ed.clickCheckbox(row.index)
          }
        }

        Rectangle {
          readonly property int size: Math.max(4, Math.round(ed.textSize * 0.26))
          visible: row.kind === "bullet"
          x: row.indentX + Math.round((ed.markerWidth - size) / 2) - Math.round(ed.textSize * 0.15)
          y: row.gapTop + Math.round((row.firstLine - size) / 2)
          width: size
          height: size
          radius: size / 2
          color: ed.dim
        }

        Text {
          visible: row.kind === "ordered"
          x: row.indentX
          width: ed.markerWidth - Math.round(ed.textSize * 0.35)
          y: row.gapTop
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: row.ordinal
          color: ed.dim
          font: field.font
        }

        TextEdit {
          id: field
          x: row.fieldX
          y: row.gapTop
          width: Math.max(0, row.width - row.fieldX)
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          selectByKeyboard: true
          persistentSelection: false
          color: row.checked || row.kind === "front" ? ed.dim : ed.foreground
          selectionColor: ed.selectionColor
          selectedTextColor: ed.foreground
          font.family: row.kind === "code" || row.kind === "front" ? "monospace" : ed.fontFamily
          font.pixelSize: row.kind === "heading"
            ? Math.round(ed.textSize * (row.headingLevel === 1 ? 1.5 : row.headingLevel === 2 ? 1.3 : row.headingLevel === 3 ? 1.15 : 1))
            : (row.kind === "code" || row.kind === "front" ? Math.round(ed.textSize * 0.85) : ed.textSize)
          font.weight: row.kind === "heading" ? Font.DemiBold : Font.Normal
          cursorVisible: activeFocus
          tabStopDistance: ed.tabStop

          onTextChanged: if (!ed.syncing && text !== row.body) ed.typed(row.index, text, cursorPosition)
          onCursorPositionChanged: if (activeFocus && !ed.syncing) ed.fieldCursor(row.index, cursorPosition)
          onCursorRectangleChanged: if (activeFocus) ed.updateCursorRect()
          onActiveFocusChanged: {
            if (activeFocus) {
              ed.focusedRow = row.index
              ed.fieldCursor(row.index, cursorPosition)
            } else if (ed.focusedRow === row.index) {
              ed.focusedRow = -1
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) { ed.key(event, row) }
        }
      }
    }
  }
}
