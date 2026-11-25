import QtQuick
import qs.Commons
import qs.Commons as Commons

// omarchy-shell's WidgetButton is a widget's label in the bar. Windows has
// no bar: the tray's icon, its tip and its menu say what the label says
// (Main.qml reads the same service), so this one keeps the names a widget
// sets and draws nothing.
Item {
  id: root

  property var bar: null
  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property color foreground: Commons.Color.foreground
  property color activeColor: Commons.Color.urgent
  property bool active: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: true
  property string tooltipText: ""
  readonly property real labelWidth: 0

  signal pressed(int button)
  signal wheelMoved(int delta)

  function triggerPress(button) { root.pressed(button) }

  visible: false
  implicitWidth: 0
  implicitHeight: 0
}
