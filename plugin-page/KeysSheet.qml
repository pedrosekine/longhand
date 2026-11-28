import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as QC
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
  // Making room for the sidebar slides, as the note does (Page.qml, `sheet`).
  Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : page.overlayRadius
  color: page.background
  borderSpec: page.cardSpec
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
          var n = Sc.countChanged(page.hyprKeys)
          return "KEYS" + (n > 0 ? "   ·   " + n + " moved" : "")
        }
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      Text {
        id: keysBack
        anchors.top: parent.top
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: "‹ back"
        color: backArea.containsMouse && page.handOn ? page.accent : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
        MouseArea {
          id: backArea
          anchors.fill: parent
          anchors.margins: -page.sp(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: page.toggleKeys()
          Tip { host: page; shown: parent.containsMouse; text: "Close   Esc" }
        }
      }

      TextField {
        FieldMenu { page: keysSheet.page; field: parent }
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
          if (page.keysListen) page.stopListening()
          page.keysAdopt = false
          page.keysNote = text === "" ? page.keysLoadError : ""
          page.keysFilter = text
          page.keysFocus = page.nextKeyRow(-1, 1)
        }
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) { if (page.keysKey(event)) event.accepted = true }
      }

      Flickable {
        id: keysFlick
        acceptedButtons: Qt.NoButton
        QC.ScrollBar.vertical: ScrollMark { page: keysSheet.page }
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

        function revealFocused(atTop) {
          if (page.keysFocus < 0) { contentY = 0; return }
          var kids = keysList.children
          var prev = null
          for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k.index === undefined) continue
            if (k.index === page.keysFocus) {
              // Include the group heading just above when landing on its first item.
              var top = (prev && prev.isHead) ? prev.y : k.y
              if (atTop) contentY = Math.max(0, Math.min(top, contentHeight - height))
              else if (contentY > top) contentY = top
              else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
              return
            }
            prev = k
          }
        }
        Connections {
          target: page
          function onKeysFocusChanged() { Qt.callLater(function () { keysFlick.revealFocused(false) }) }
          function onKeysOpenChanged() { if (page.keysOpen) Qt.callLater(function () { keysFlick.revealFocused(true) }) }
        }

        Column {
          id: keysList
          width: parent.width

          Text {
            width: parent.width
            visible: page.keyRows.length === 0
            textFormat: Text.PlainText
            text: page.keysHyprLoading ? "reading " + Sc.systemName + "'s keys…" : "no key does that"
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
              readonly property bool movable: modelData.kind === "action" || modelData.kind === "hypr"
              readonly property bool hot: page.keysFocus === index && !isHead
              // The pointer follows the keys (page.selected).
              readonly property bool lit: hot && page.here === "center"
              onLitChanged: page.selected(keyRow, "center", lit)
              Component.onCompleted: if (lit) page.selected(keyRow, "center", true)
              readonly property bool listening: hot && !!page.keysListen && page.keysListen.id === modelData.id
              readonly property bool showReset: movable && modelData.changed && !listening && (hot || keyHover.hovered)
              readonly property var pills: listening
                ? [page.keysTake !== "" ? Sc.show(page.keysTake) + " again to move it"
                   : page.keysListen.add ? "press a key to add · Esc keeps it"
                   : "press the new key · Esc keeps it"]
                : modelData.keys.length === 0 && movable ? ["no key"]
                : modelData.keys
              readonly property bool stackCaps: !isHead && (
                keyInner.width < page.sp(420)
                || (listening && keyInner.width < page.sp(560))
                || (pills.length > 2 && keyInner.width < page.sp(560))
              )
              readonly property real pillMaxW: stackCaps ? keyInner.width : Math.floor(keyInner.width * 0.58)
              width: keysList.width
              height: keyInner.height + page.sp(14) + (isHead ? (index === 0 ? page.sp(4) : page.sp(26)) : 0)

              Rectangle {
                anchors.fill: keyInner
                anchors.topMargin: -page.sp(6)
                anchors.bottomMargin: -page.sp(6)
                anchors.leftMargin: -page.sp(8)
                anchors.rightMargin: -page.sp(8)
                radius: Style.cornerRadius
                color: keyRow.hot ? Style.selectedFill : keyHover.hovered && page.handOn ? Style.hoverFill : "transparent"
              }
              // A key that cannot be moved looks it: no hand, no hover mark; a
              // click on it still says why (2026-11-25, the mouse pass).
              HoverHandler { id: keyHover; enabled: !keyRow.isHead && keyRow.modelData.kind !== "fixed" }

              Item {
                id: keyInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: page.sp(10)
                anchors.rightMargin: page.sp(10)
                anchors.bottomMargin: page.sp(7)
                height: keyRow.stackCaps
                  ? (doesText.implicitHeight + page.sp(5) + keyCaps.implicitHeight)
                  : Math.max(doesText.implicitHeight, keyCaps.implicitHeight)

                // A group: drawn like a band in the dashboard.
                Text {
                  id: doesText
                  x: 0
                  y: keyRow.stackCaps ? 0 : Math.round((parent.height - height) / 2)
                  width: keyRow.stackCaps || keyRow.isHead ? parent.width
                    : Math.max(page.sp(80), parent.width - keyCaps.width - (keyCaps.width > 0 ? page.sp(12) : 0))
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
                Flow {
                  id: keyCaps
                  x: keyRow.stackCaps ? 0 : parent.width - width
                  y: keyRow.stackCaps ? doesText.implicitHeight + page.sp(5) : Math.round((parent.height - height) / 2)
                  width: keyRow.stackCaps ? parent.width : undefined
                  spacing: page.sp(6)

                  Item {
                    visible: keyRow.showReset
                    width: visible ? resetText.implicitWidth + page.sp(4) : 0
                    height: visible ? resetText.implicitHeight + Math.round(page.textSize * 0.35) : 0
                    Text {
                      id: resetText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "reset"
                      color: resetArea.containsMouse && page.handOn ? page.accent : page.dim
                      font.family: page.fontFamily
                      font.styleName: page.fontStyle
                      font.pixelSize: page.fs(Style.font.caption)
                    }
                    MouseArea {
                      id: resetArea
                      anchors.fill: parent
                      anchors.margins: -page.sp(4)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        page.keysFocus = keyRow.index
                        page.resetKey(keyRow.modelData)
                        keysField.forceActiveFocus()
                      }
                      Tip { host: page; shown: parent.containsMouse; text: "Give back its own key   Del" }
                    }
                  }

                  Repeater {
                    model: keyRow.pills
                    Rectangle {
                      required property var modelData
                      readonly property bool strong: keyRow.listening || keyRow.modelData.changed
                      width: Math.min(capText.implicitWidth + Math.round(page.textSize * 0.9), Math.max(page.sp(40), keyRow.pillMaxW))
                      height: capText.implicitHeight + Math.round(page.textSize * 0.25)
                      radius: Style.cornerRadius
                      color: "transparent"
                      border.width: 1
                      border.color: strong ? page.accent : page.faint
                      Text {
                        id: capText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - Math.round(page.textSize * 0.4))
                        elide: Text.ElideRight
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
                id: rowArea
                anchors.fill: parent
                enabled: !keyRow.isHead
                z: -1
                hoverEnabled: true
                cursorShape: keyRow.modelData.kind === "fixed" ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: function (mouse) {
                  page.selectKeyRow(keyRow.index, keyRow.modelData, !!(mouse.modifiers & Qt.ShiftModifier))
                  keysField.forceActiveFocus()
                }
                onDoubleClicked: function (mouse) {
                  if (keyRow.movable) page.listenFor(keyRow.modelData, !!(mouse.modifiers & Qt.ShiftModifier))
                  keysField.forceActiveFocus()
                }
                Tip {
                  host: page
                  shown: rowArea.containsMouse && keyRow.movable && !keyRow.listening
                  text: keyRow.hot
                    ? "Click or Enter to change · Shift+click to add · Del to reset"
                    : "Click to select · double-click to change · Shift+click to add"
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
        readonly property var focusedRow: page.keyRows[page.keysFocus] || null
        readonly property string focusedOwn: {
          if (!focusedRow || !focusedRow.changed) return ""
          var o = focusedRow.ownShown || focusedRow.own || []
          return o.length > 0 ? o.join(" / ") : ""
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: {
            if (page.keysNote !== "") return page.keysNote
            var r = keysFoot.focusedRow
            if (!r) return ""
            var parts = []
            if (r.where !== "")
              // The six from outside work anywhere in the system, the page
              // closed too (2026-11-25: on Windows the footer said nothing).
              parts.push(r.where === Sc.systemName
                ? "works anywhere in " + Sc.systemName + ", the page closed too"
                : "works " + r.where)
            if (keysFoot.focusedOwn !== "") parts.push("its own: " + keysFoot.focusedOwn)
            return parts.join(" · ")
          }
          color: page.keysNote !== "" ? page.accent : page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: page.keysListen
            ? (page.keysListen.hypr
                ? "press the key" + (page.keysListen.add ? " to add" : "") + ", with " + (page.onWindows ? "Win" : "Super") + ", and Ctrl, Alt or Shift if you want them · Esc keeps the old one"
                : "press the key" + (page.keysListen.add ? " to add" : "") + ", with Ctrl, Alt, Shift or " + (page.onWindows ? "Win" : "Super") + " if you want them · Esc keeps the old one")
            : "↑↓ PgUp/PgDn move · Enter changes · Shift+Enter adds · Del resets · Shift+Del clears"
              + (page.keysUndo.length > 0 ? " · Ctrl+Z undoes" : "")
              + " · type to find · Esc back"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
    }
  }
}
