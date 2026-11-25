import QtQuick
import QtQuick.Controls
import qs.Commons

// The mouse's menu on words (2026-11-25, the mouse pass): a right click in
// the note or on a chat's words offers what its keys do there — cut, copy,
// paste, select all, reply — each with its key beside it, so the menu
// teaches the keys as the hints do. Drawn as a hint is (Tip.qml): the
// darker paper, a faint edge. It never takes the keys, so the words keep
// their selection and the keys stay where they were. While it is open the
// page hands it its keys first (`key`): ↑↓ pick, Enter does, Esc closes it
// and nothing else; any other key closes it and goes on (2026-11-25, the
// second pass: Esc also cleared the selection under it).
Popup {
  id: menu
  required property Item page
  // [{ text, key, enabled, run }]
  property var entries: []
  property int current: -1          // the entry the keys are on, or none
  readonly property color edge: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
  readonly property int size: page.fs(Style.font.bodySmall)

  padding: page.sp(4)
  focus: false
  // Not on a release outside: it opens on the press, at the pointer, and a
  // release a pixel up or left of it closed it at once.
  closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
  // As wide as its widest entry, words and keycaps (the third pass: a long
  // label from a dashboard row ran under its key at a fixed 210).
  property real widest: 0
  width: Math.max(page.sp(210), menu.widest + menu.padding * 2)

  // At (x, y) in `over`'s coordinates, kept inside the window.
  function openAt(over, x, y, list) {
    menu.widest = 0
    menu.entries = list.filter(function (e) { return e })
    menu.current = -1
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

  // A key while it is open: true when it was the menu's.
  function key(event) {
    var k = event.key
    if (k === Qt.Key_Escape) { menu.close(); return true }
    if (k === Qt.Key_Up || k === Qt.Key_Down) {
      var n = menu.entries.length, i = menu.current
      for (var step = 0; step < n; step++) {
        i = k === Qt.Key_Down ? (i + 1 + n) % n : (i - 1 + n) % n
        if (menu.entries[i].enabled !== false) { menu.current = i; break }
      }
      return true
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      var e = menu.entries[menu.current]
      if (!e || e.enabled === false) return true
      menu.close()
      if (e.run) e.run()
      return true
    }
    return false
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
        required property int index
        readonly property bool on: modelData.enabled !== false
        readonly property real natural: label.implicitWidth + caps.implicitWidth + menu.page.sp(8) * 2 + menu.page.sp(24)
        onNaturalChanged: menu.widest = Math.max(menu.widest, natural)
        Component.onCompleted: menu.widest = Math.max(menu.widest, natural)
        width: menu.width - menu.padding * 2
        height: menu.size + menu.page.sp(14)
        radius: Style.cornerRadius
        color: on && index === menu.current ? Style.selectedFill
          : on && entryArea.containsMouse && menu.page.handOn ? Style.hoverFill : "transparent"
        Text {
          id: label
          anchors.left: parent.left
          anchors.leftMargin: menu.page.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, caps.x - x - menu.page.sp(12))
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: entry.modelData.text
          color: entry.on ? menu.page.foreground : menu.page.faint
          font.family: menu.page.fontFamily
          font.styleName: menu.page.fontStyle
          font.pixelSize: menu.size
        }
        // Its key as keycaps, as a hint draws it (Tip.qml).
        KeyCaps {
          id: caps
          anchors.right: parent.right
          anchors.rightMargin: menu.page.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          page: menu.page
          size: menu.size
          key: entry.modelData.key || ""
          opacity: entry.on ? 1 : 0.5
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
