import Quickshell
import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui

// What the agent may do (Settings → The agent, Ctrl+M): each kind of action
// at ask me, do it and tell me, or never, with its record (docs/agent.md,
// slice 5). Settings' third view, drawn in its place; Esc goes back. Only
// the person changes a level; `page` is the page itself.
BorderSurface {
  id: autonomySheet
  required property Item page
  readonly property var content: page.contentItem
  readonly property var pal: page.palette
  property alias autonomyKeysRef: autonomyKeys

  visible: page.centerView === "settings" && page.settingsView === "autonomy"
  x: page.wideX
  // Making room for the sidebar slides, as Settings' main sheet does.
  Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : page.overlayRadius
  color: page.background
  borderSpec: page.cardSpec
  padding: page.sheetPadding

  Item {
    id: autonomyKeys
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { if (page.autonomyKey(event)) event.accepted = true }
  }

  MouseArea { anchors.fill: parent; onClicked: autonomyKeys.forceActiveFocus() }

  Item {
    anchors.fill: parent
    anchors.topMargin: autonomySheet.contentTopInset
    anchors.rightMargin: autonomySheet.contentRightInset
    anchors.bottomMargin: autonomySheet.contentBottomInset
    anchors.leftMargin: autonomySheet.contentLeftInset

    Item {
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: parent.height

      SettingsCrumb {
        id: autonomyTitle
        page: autonomySheet.page
        anchors.top: parent.top
        anchors.left: parent.left
        title: "WHAT THE AGENT MAY DO"
        onBack: page.closeNotebook()
      }

      Text {
        id: autonomyIntro
        anchors.top: autonomyTitle.bottom
        anchors.topMargin: page.sp(18)
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "For each kind of action: ask me (it proposes, you accept or decline in the dashboard), do it and tell me "
          + "(it is done, shown in the dashboard as the agent's, and one key undoes it), or never. Everything starts at ask me; "
          + "only you raise it. Its record is beside each."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      Flickable {
        id: autonomyFlick
        acceptedButtons: Qt.NoButton
        QC.ScrollBar.vertical: ScrollMark { page: autonomySheet.page }
        anchors.top: autonomyIntro.bottom
        anchors.topMargin: page.sp(18)
        anchors.bottom: autonomyFoot.top
        anchors.bottomMargin: page.sp(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: -page.sp(10)
        anchors.rightMargin: -page.sp(10)
        clip: true
        contentWidth: width
        contentHeight: autonomyColumn.implicitHeight + page.sp(8)
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { flickable: autonomyFlick }

      Column {
        id: autonomyColumn
        x: page.sp(10)
        width: autonomyFlick.width - page.sp(20)
        spacing: page.sp(6)

        Text {
          visible: !page.autonomyData
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: page.sayUnread("autonomy")
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Repeater {
          model: page.autonomyData ? page.autonomyData.kinds : []
          Item {
            id: kindRow
            required property var modelData
            required property int index
            readonly property bool picked: page.autonomyFocus === index
            readonly property bool lit: picked && page.here === "center" && autonomySheet.visible
            onPickedChanged: if (picked) {
              if (y < autonomyFlick.contentY) autonomyFlick.contentY = Math.max(0, y)
              else if (y + height > autonomyFlick.contentY + autonomyFlick.height) autonomyFlick.contentY = Math.max(0, y + height - autonomyFlick.height)
            }
            onLitChanged: page.selected(kindRow, "center", lit)
            Component.onCompleted: if (lit) page.selected(kindRow, "center", true)
            width: parent.width
            height: kindCol.implicitHeight + page.sp(12)

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -page.sp(10)
              anchors.rightMargin: -page.sp(10)
              radius: Style.cornerRadius
              color: kindRow.picked ? Style.selectedFill : kindHover.hovered && page.handOn ? Style.hoverFill : "transparent"
            }
            HoverHandler { id: kindHover; enabled: !kindRow.picked }
            MouseArea {
              anchors.fill: parent
              cursorShape: kindRow.picked ? Qt.ArrowCursor : Qt.PointingHandCursor
              onClicked: { page.autonomyFocus = kindRow.index; autonomyKeys.forceActiveFocus() }
            }

            Column {
              id: kindCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: page.sp(3)

              // A Flow: a long kind and its three levels go onto two lines
              // in a narrow window, not past the edge.
              Flow {
                width: parent.width
                spacing: page.sp(16)
                Text {
                  id: kindLabel
                  textFormat: Text.PlainText
                  text: kindRow.modelData.label
                  color: page.foreground
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }
                Repeater {
                  model: kindRow.modelData.ask_only ? ["ask", "never"] : page.autonomyLevels
                  Text {
                    required property var modelData
                    readonly property bool chosen: kindRow.modelData.level === modelData
                    topPadding: Math.max(0, kindLabel.baselineOffset - levelMetrics.ascent)   // on the label's baseline
                    FontMetrics { id: levelMetrics; font: parent.font }
                    textFormat: Text.PlainText
                    text: page.sayLevel(modelData)
                    color: levelArea.containsMouse && page.handOn ? page.accent : chosen ? page.foreground : page.faint
                    font.underline: chosen
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.bodySmall)
                    MouseArea {
                      id: levelArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { page.autonomyFocus = kindRow.index; page.setAutonomy(kindRow.modelData.kind, modelData); autonomyKeys.forceActiveFocus() }
                      Tip {
                        host: page
                        shown: parent.containsMouse
                        text: modelData === "ask" ? "Ask me: it proposes, you accept or decline   ←→"
                          : modelData === "do" ? "Do it and tell me: done, shown as the agent's, one key undoes it   ←→"
                          : "Never: it does not propose this   ←→"
                      }
                    }
                  }
                }
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: page.sayRecord(kindRow.modelData)
                color: kindRow.modelData.suggest && kindRow.modelData.level === "ask" ? page.accent : page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
              }
            }
          }
        }
      }
      }

      SettingsFoot {
        id: autonomyFoot
        page: autonomySheet.page
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        keys: "↑↓ pick a kind · ←→ ask me · do it and tell me · never · Space or Enter the next, round · Esc back to settings"
      }
    }
  }
}
