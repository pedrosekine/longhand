import QtQuick
import qs.Ui

// A hover's hint (docs/hints.md). Shown only while the hand is on the
// mouse (the page's `handOn`, 2026-10-30), and warm: the first waits, and
// while one is open, or just after, the next opens at once, so a row of
// words read with the mouse is one strip, not a wait at each.
PanelToolTip {
  id: tip
  required property Item host   // the page
  property bool shown: false    // the mouse is on its thing
  property string act: ""       // what a click on it does, as a key would (C)
  visible: shown && host.handOn
  delay: host.tipWarm ? 0 : 500
  onOpened: host.tipOpened()
  onClosed: host.tipClosed()
  Component.onDestruction: if (tip.opened) host.tipClosed()

  // A plain click on its thing: the page may name the key that does the
  // same (docs/hints.md, C). A Ctrl- or Shift-click is another action.
  Connections {
    target: tip.act !== "" ? tip.parent : null
    ignoreUnknownSignals: true
    function onClicked(mouse) {
      if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) tip.host.mouseDid(tip.act)
    }
  }
}
