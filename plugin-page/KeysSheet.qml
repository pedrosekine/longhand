import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "Blocks.js" as Blocks
import "Bound.js" as Bound
import "Dates.js" as Dates
import "Days.js" as Days
import "Task.js" as Task
import "Authorship.js" as Authorship
import "Shortcuts.js" as Sc

// The keys sheet (Ctrl+/, or "keys" at the sidebar's foot): every key the page answers to, and moving one
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: keysSheet
  required property Item page
  readonly property var content: page.contentItem
  readonly property var pal: page.palette
  property alias keysFieldRef: keysField

  visible: page.keysOpen
  x: page.wideX
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sheetPadding

  MouseArea { anchors.fill: parent; onClicked: keysField.forceActiveFocus() }

  Item {
    anchors.fill: parent
    anchors.topMargin: keysSheet.contentTopInset
    anchors.rightMargin: keysSheet.contentRightInset
    anchors.bottomMargin: keysSheet.contentBottomInset
    anchors.leftMargin: keysSheet.contentLeftInset

    // Everything sits in one column, as wide as the dashboard's.
    Item {
      id: keysColumn
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: parent.height

      Text {
        id: keysTitle
        anchors.top: parent.top
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: {
          page.keysVersion
          var n = Object.keys(Sc.save()).length
          return "KEYS" + (n > 0 ? "   ·   " + n + " moved" : "")
        }
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      TextField {
        id: keysField
        anchors.top: keysTitle.bottom
        anchors.topMargin: page.sp(10)
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: "find a key, or what it does"
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.body)
        foreground: page.foreground
        onTextChanged: {
          page.keysFilter = text
          page.keysFocus = page.nextKeyRow(-1, 1)
        }
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) { if (page.keysKey(event)) event.accepted = true }
      }

      Flickable {
        id: keysFlick
        anchors.top: keysField.bottom
        anchors.topMargin: page.sp(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: keysFoot.top
        anchors.bottomMargin: page.sp(10)
        clip: true
        contentWidth: width
        contentHeight: keysList.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        TouchScroll { flickable: keysFlick }

        function revealFocused() {
          var kids = keysList.children
          for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k.index === undefined || k.index !== page.keysFocus) continue
            if (contentY > k.y) contentY = k.y
            else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
            return
          }
        }
        Connections { target: page; function onKeysFocusChanged() { Qt.callLater(keysFlick.revealFocused) } }

        Column {
          id: keysList
          width: parent.width

          Text {
            width: parent.width
            visible: page.keyRows.length === 0
            textFormat: Text.PlainText
            text: "no key does that"
            color: page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.body)
          }

          Repeater {
            model: page.keyRows
            Item {
              id: keyRow
              required property var modelData
              required property int index
              readonly property bool isHead: modelData.kind === "head"
              readonly property bool hot: page.keysFocus === index && !isHead
              readonly property bool listening: hot && !!page.keysListen && page.keysListen.id === modelData.id
              width: keysList.width
              height: keyInner.height + page.sp(14) + (isHead ? (index === 0 ? page.sp(4) : page.sp(26)) : 0)

              Rectangle {
                anchors.fill: keyInner
                anchors.topMargin: -page.sp(6)
                anchors.bottomMargin: -page.sp(6)
                anchors.leftMargin: -page.sp(8)
                anchors.rightMargin: -page.sp(8)
                radius: Style.cornerRadius
                color: keyRow.hot ? Style.selectedFill : keyHover.hovered ? Style.hoverFill : "transparent"
              }
              HoverHandler { id: keyHover; enabled: !keyRow.isHead }

              Item {
                id: keyInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: page.sp(10)
                anchors.rightMargin: page.sp(10)
                anchors.bottomMargin: page.sp(7)
                height: Math.max(doesText.implicitHeight, keyCaps.height)

                // A group: drawn like a band in the dashboard.
                Text {
                  id: doesText
                  anchors.left: parent.left
                  anchors.right: keyCaps.left
                  anchors.rightMargin: page.sp(12)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  text: keyRow.modelData.does
                  color: keyRow.isHead ? (pal.headings.length > 0 ? pal.headings[0] : page.accent)
                    : keyRow.modelData.kind === "offer" ? page.accent
                    : keyRow.modelData.kind === "fixed" ? page.dim : page.foreground
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }

                // Its keys, each a pill like a bound line's date. A
                // moved key is outlined in the accent; while the sheet
                // waits for the new key, the pills give way to that.
                Row {
                  id: keyCaps
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: page.sp(6)
                  Repeater {
                    model: keyRow.listening ? [page.keysTake !== "" ? Sc.show(page.keysTake) + " again to move it" : "press the new key · Esc keeps it"]
                      : keyRow.modelData.keys.length === 0 && (keyRow.modelData.kind === "action" || keyRow.modelData.kind === "hypr") ? ["no key"]
                      : keyRow.modelData.keys
                    Rectangle {
                      required property var modelData
                      readonly property bool strong: keyRow.listening || keyRow.modelData.changed
                      width: capText.implicitWidth + Math.round(page.textSize * 0.9)
                      height: capText.implicitHeight + Math.round(page.textSize * 0.25)
                      radius: height / 2
                      color: "transparent"
                      border.width: 1
                      border.color: strong ? page.accent : page.faint
                      Text {
                        id: capText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: parent.modelData
                        color: parent.strong ? page.accent : keyRow.modelData.kind === "fixed" ? page.dim : page.foreground
                        font.family: page.fontFamily
                        font.styleName: page.fontStyle
                        font.pixelSize: Math.round(page.textSize * 0.78)
                      }
                    }
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: !keyRow.isHead
                z: -1
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  page.keysFocus = keyRow.index
                  page.listenFor(keyRow.modelData, false)
                  keysField.forceActiveFocus()
                }
              }
            }
          }
        }
      }

      Column {
        id: keysFoot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: page.sp(4)

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: page.keysNote !== "" ? page.keysNote
            : (page.keyRows[page.keysFocus] && page.keyRows[page.keysFocus].where !== "" && page.keyRows[page.keysFocus].where !== "Hyprland"
              ? "works " + page.keyRows[page.keysFocus].where : "")
          color: page.keysNote !== "" ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: page.keysListen ? (page.keysListen.hypr ? "press the key, with Super, and Ctrl, Alt or Shift if you want them · Esc keeps the old one"
              : "press the key, with Ctrl, Alt, Shift or Super if you want them · Esc keeps the old one")
            : "↑↓ move · Enter changes the key · Shift+Enter adds one · Del gives back its own · type to find · Esc back"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
    }
  }
}
