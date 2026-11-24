import QtQuick

// omarchy-shell's PanelKeyCatcher: what wraps a popup's content and turns
// keys into what they ask for, so each popup keeps only its own cursor.
// The same signals and the same keys as the shell's, since the popups'
// own hint lines name them:
//
//   Esc                     closeRequested
//   Tab, Shift+Tab          tabRequested(1 | -1)
//   arrows, h j k l         moveRequested(dx, dy)
//   Enter                   returnRequested, then activateRequested(modifiers)
//   Space                   activateRequested(modifiers)
//   Delete, x               deleteRequested
//   any other one character textKey(text, modifiers)
//
// It hears a key before what is inside it does. `blocked` lets every key
// through untouched: a popup sets it while a field of its own is typed in.
Item {
  id: root

  property bool blocked: false
  property bool reorderable: false
  property bool reorderableSideways: false
  property bool shiftHeld: false

  signal moveRequested(int dx, int dy)
  signal reorderRequested(int dy)
  signal reorderSidewaysRequested(int dx)
  signal activateRequested(int modifiers)
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text, int modifiers)

  onActiveFocusChanged: if (!activeFocus) shiftHeld = false

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onReleased: function (event) { if (event.key === Qt.Key_Shift) root.shiftHeld = false }
  Keys.onPressed: function (event) {
    root.shiftHeld = event.key === Qt.Key_Shift || (event.modifiers & Qt.ShiftModifier) !== 0
    if (root.blocked) return
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var dx = 0, dy = 0
    if (event.key === Qt.Key_Down || event.text === "j") dy = 1
    else if (event.key === Qt.Key_Up || event.text === "k") dy = -1
    else if (event.key === Qt.Key_Right || event.text === "l") dx = 1
    else if (event.key === Qt.Key_Left || event.text === "h") dx = -1
    // Ctrl with a direction also reads K, J, L, H by their keys: with Ctrl
    // held they carry no text.
    if (ctrl && dy === 0 && dx === 0) {
      if (event.key === Qt.Key_J) dy = 1
      else if (event.key === Qt.Key_K) dy = -1
      else if (event.key === Qt.Key_L) dx = 1
      else if (event.key === Qt.Key_H) dx = -1
      if (!(dy !== 0 && root.reorderable) && !(dx !== 0 && root.reorderableSideways)) { dx = 0; dy = 0 }
    }

    if (event.key === Qt.Key_Escape) root.closeRequested()
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
      root.tabRequested(event.key === Qt.Key_Backtab || root.shiftHeld ? -1 : 1)
    else if (ctrl && dy !== 0 && root.reorderable) root.reorderRequested(dy)
    else if (ctrl && dx !== 0 && root.reorderableSideways) root.reorderSidewaysRequested(dx)
    else if (dx !== 0 || dy !== 0) root.moveRequested(dx, dy)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.returnRequested()
      root.activateRequested(event.modifiers)
    }
    else if (event.key === Qt.Key_Space) root.activateRequested(event.modifiers)
    else if (event.key === Qt.Key_Delete || event.text === "x" || event.text === "X") root.deleteRequested()
    else {
      // Not a key of this one's: a popup may still read it by its text,
      // and its own Keys handler sees it after this.
      if (event.text && event.text.length === 1) root.textKey(event.text, event.modifiers)
      return
    }
    event.accepted = true
  }
}
