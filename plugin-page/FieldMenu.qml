import QtQuick
import QtQuick.Controls

// The page's menu on a box typed in (2026-11-25, the second mouse pass): a
// right click gives cut, copy, paste and select all, drawn as the note's
// and the chats' are (EditMenu.qml), with their keys. Qt's own menu on its
// text fields (since 6.9) is put aside: it looked like no other part of
// the page. Put it inside the field: `FieldMenu { page: …; field: parent }`.
MouseArea {
  id: fm
  required property Item page
  required property Item field   // a TextField, a TextArea
  property var pasteFn: null     // the box's own paste, if it has one (ChatField's: words only)
  anchors.fill: parent
  acceptedButtons: Qt.RightButton
  // Qt makes its menu when it is first asked for: asked for, then put
  // aside, it stays aside (set before that, Qt's came back). Again on each
  // right press, before Qt's own context-menu event.
  function shutQts() {
    if (!fm.field) return
    var qts = fm.field.ContextMenu.menu
    if (qts !== null) fm.field.ContextMenu.menu = null
  }
  Component.onCompleted: Qt.callLater(fm.shutQts)

  onPressed: function (mouse) {
    fm.shutQts()
    var f = fm.field
    var p = fm.mapToItem(f, mouse.x, mouse.y)
    f.forceActiveFocus()
    // A click outside the words selected puts the cursor there, as a left
    // click would; inside, the selection stays for the menu.
    var at = f.positionAt(p.x, p.y)
    var a = Math.min(f.selectionStart, f.selectionEnd), b = Math.max(f.selectionStart, f.selectionEnd)
    if (a === b || at < a || at > b) { f.deselect(); f.cursorPosition = at }
    var has = f.selectedText !== ""
    var ro = !!f.readOnly
    fm.page.used("edit-menu", "box")
    fm.page.editMenuAt(f, p.x, p.y, [
      { text: "Cut", key: "Ctrl+X", enabled: has && !ro, run: function () { f.cut() } },
      { text: "Copy", key: "Ctrl+C", enabled: has, run: function () { f.copy() } },
      { text: "Paste", key: "Ctrl+V", enabled: !ro && f.canPaste, run: function () { if (fm.pasteFn) fm.pasteFn(); else f.paste() } },
      { text: "Select all", key: "Ctrl+A", enabled: f.length > 0, run: function () { f.selectAll() } }
    ])
  }
}
