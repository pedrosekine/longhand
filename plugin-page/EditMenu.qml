import QtQuick
import QtQuick.Controls
import qs.Commons

// The mouse's menu on words (2026-11-25, the mouse pass): a right click in
// the note or on a chat's words offers what its keys do there — cut, copy,
// paste, select all, reply — each with its key beside it, so the menu
// teaches the keys as the hints do. Drawn as a hint is (Tip.qml): the
// darker paper, a faint edge. It never takes the keys, so the words keep
// their selection and the keys stay where they were.
Popup {
  id: menu
  required property Item page
  // [{ text, key, enabled, run }]
  property var entries: []
  readonly property color edge: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
  readonly property int size: page.fs(Style.font.bodySmall)

  padding: page.sp(4)
  focus: false
  closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent | Popup.CloseOnReleaseOutside
  width: page.sp(210)

  // At (x, y) in `over`'s coordinates, kept inside the window.
  function openAt(over, x, y, list) {
    menu.entries = list.filter(function (e) { return e })
    if (menu.entries.length === 0) return
    menu.parent = over
    var win = over.Window.window
    var p = over.mapToItem(null, x, y)
    var h = menu.entries.length * (menu.size + page.sp(14)) + menu.padding * 2
    var maxX = (win ? win.width : p.x + menu.width) - menu.width - page.sp(4)
    var maxY = (win ? win.height : p.y + h) - h - page.sp(4)
    menu.x = x + Math.min(0, maxX - p.x)
    menu.y = y + Math.min(0, maxY - p.y)
    menu.open()
  }

  background: Rectangle {
    radius: menu.page.overlayRadius
    color: menu.page.sunk
    border.width: 1
    border.color: menu.edge
  }

  contentItem: Column {
    Repeater {
      model: menu.entries
      Rectangle {
        id: entry
        required property var modelData
        readonly property bool on: modelData.enabled !== false
        width: menu.width - menu.padding * 2
        height: menu.size + menu.page.sp(14)
        radius: Style.cornerRadius
        color: on && entryArea.containsMouse ? Style.hoverFill : "transparent"
        Text {
          anchors.left: parent.left
          anchors.leftMargin: menu.page.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: entry.modelData.text
          color: entry.on ? menu.page.foreground : menu.page.faint
          font.family: menu.page.fontFamily
          font.styleName: menu.page.fontStyle
          font.pixelSize: menu.size
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: menu.page.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: entry.modelData.key || ""
          color: menu.page.faint
          font.family: menu.page.fontFamily
          font.styleName: menu.page.fontStyle
          font.pixelSize: menu.size
        }
        MouseArea {
          id: entryArea
          anchors.fill: parent
          enabled: entry.on
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var run = entry.modelData.run
            menu.close()
            if (run) run()
          }
        }
      }
    }
  }
}
