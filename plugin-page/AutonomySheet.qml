import Quickshell
import QtQuick
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

  visible: page.settingsOpen && page.settingsView === "autonomy"
  x: page.wideX
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
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

      Text {
        id: autonomyTitle
        anchors.top: parent.top
        textFormat: Text.PlainText
        text: "SETTINGS · WHAT THE AGENT MAY DO"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
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

      Column {
        anchors.top: autonomyIntro.bottom
        anchors.topMargin: page.sp(18)
        width: parent.width
        spacing: page.sp(6)

        Repeater {
          model: page.autonomyData ? page.autonomyData.kinds : []
          Item {
            id: kindRow
            required property var modelData
            required property int index
            readonly property bool picked: page.autonomyFocus === index
            width: parent.width
            height: kindCol.implicitHeight + page.sp(12)

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -page.sp(10)
              anchors.rightMargin: -page.sp(10)
              radius: Style.cornerRadius
              color: kindRow.picked ? Style.selectedFill : "transparent"
            }
            MouseArea {
              anchors.fill: parent
              onClicked: { page.autonomyFocus = kindRow.index; autonomyKeys.forceActiveFocus() }
            }

            Column {
              id: kindCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: page.sp(3)

              Row {
                spacing: page.sp(16)
                Text {
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
                    anchors.baseline: parent.children[0].baseline
                    textFormat: Text.PlainText
                    text: page.sayLevel(modelData)
                    color: levelArea.containsMouse ? page.accent : chosen ? page.foreground : page.faint
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

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "↑↓ pick a kind · ←→ ask me · do it and tell me · never · Esc back to settings"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
  }
}
