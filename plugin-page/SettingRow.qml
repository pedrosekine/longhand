import QtQuick
import qs.Commons

// A row of settings ↑↓ can pick (Page.qml, settingsKinds), drawn as a
// picked calendar is: its words side by side, the selection behind them.
// A click picks it too; `chosen` lets the sheet give the keys back to its
// field.
Item {
  id: row
  required property Item page
  required property string kind
  default property alias content: body.data
  signal chosen()

  readonly property bool picked: page.settingsFocus === page.settingsAt(kind)
  readonly property bool lit: picked && page.here === "center"
  onLitChanged: page.selected(row, "center", lit)
  Component.onCompleted: if (lit) page.selected(row, "center", true)
  width: parent ? parent.width : 0
  height: body.implicitHeight + page.sp(12)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -page.sp(10)
    anchors.rightMargin: -page.sp(10)
    radius: Style.cornerRadius
    color: row.picked ? Style.selectedFill : rowHover.hovered && page.handOn ? Style.hoverFill : "transparent"
  }
  HoverHandler { id: rowHover; enabled: !row.picked }
  MouseArea {
    anchors.fill: parent
    onClicked: { page.settingsFocus = page.settingsAt(row.kind); row.chosen() }
  }

  Row {
    id: body
    anchors.verticalCenter: parent.verticalCenter
    spacing: page.sp(16)
  }
}
