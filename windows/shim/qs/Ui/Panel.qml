import QtQuick
import qs.Commons as Commons

// omarchy-shell's Panel, the base of a bar widget with a popup, where there
// is no bar: the same names (opened, open, close, toggle, switchPanel,
// setting), the open state kept here, and the host told when Tab asks for
// the widget beside this one (Main.qml has two: the timer, the deadlines).
Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false

  property bool opened: false
  readonly property color barForeground: Commons.Color.foreground

  signal switchRequested(int direction)

  function open() { root.opened = true }
  function close() { root.opened = false }
  function closeForPopoutSwitch() { root.close() }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    root.switchRequested(direction)
    return true
  }

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
