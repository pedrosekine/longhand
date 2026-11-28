import QtQuick
import qs.Commons

// A row of settings ↑↓ can pick (Page.qml, settingsKinds), drawn as a
// picked calendar is: its words side by side, the selection behind them.
// A click picks it too; `chosen` lets the sheet give the keys back to its
// field. Its words flow onto a second line in a narrow window rather than
// past the edge, where the way into the setting could not be clicked.
Item {
  id: row
  required property Item page
  required property string kind
  default property alias content: body.data
  signal chosen()
  signal focused(Item item)

  readonly property bool picked: page.settingsFocus === page.settingsAt(kind)
  // Only while Settings' main sheet is drawn: hidden, its picked row took
  // the pointer's mark from the note or the dashboard.
  readonly property bool lit: picked && page.here === "center" && page.centerView === "settings" && page.settingsView === "main"
  onPickedChanged: if (picked) row.focused(row)
  onLitChanged: page.selected(row, "center", lit)
  Component.onCompleted: if (lit) page.selected(row, "center", true)
  width: parent ? parent.width : 0
  height: visible ? body.implicitHeight + page.sp(12) : 0

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
    cursorShape: Qt.PointingHandCursor
    onClicked: { page.settingsFocus = page.settingsAt(row.kind); row.chosen() }
  }

  Flow {
    id: body
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: page.sp(16)
  }
}
