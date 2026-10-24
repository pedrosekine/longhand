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

// Settings (Ctrl+, or "settings" at the sidebar's foot): calendars, the agent, sound
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: settingsSheet
  required property Item page
  readonly property var content: page.contentItem
  readonly property var pal: page.palette
  property alias settingsFieldRef: settingsField

  visible: page.settingsOpen && page.settingsView === "main"
  x: page.wideX
  // Making room for the sidebar slides, as the note does (Page.qml, `sheet`).
  Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  y: page.alongside ? 0 : page.sheetMargin
  width: page.wideWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sheetPadding

  MouseArea { anchors.fill: parent; onClicked: settingsField.forceActiveFocus() }

  Item {
    anchors.fill: parent
    anchors.topMargin: settingsSheet.contentTopInset
    anchors.rightMargin: settingsSheet.contentRightInset
    anchors.bottomMargin: settingsSheet.contentBottomInset
    anchors.leftMargin: settingsSheet.contentLeftInset

    Item {
      id: settingsColumn
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: parent.height

      Text {
        id: settingsTitle
        anchors.top: parent.top
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: "SETTINGS"
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      Column {
        anchors.top: settingsTitle.bottom
        anchors.topMargin: page.sp(30)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: page.sp(8)

        // A section: drawn like a band in the dashboard.
        Text {
          textFormat: Text.PlainText
          text: "Calendar"
          color: pal.headings.length > 0 ? pal.headings[0] : page.accent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Your calendars. Classes are matched to your projects by their course code, for the sidebar's next session; "
            + "for each calendar you choose what the agent sees. They are fetched when the page or the sidebar opens, "
            + "at most once an hour, and the addresses stay on this machine."
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Item { width: 1; height: page.sp(4) }

        Text {
          visible: !!page.settingsState && !page.settingsState.configured
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: visible ? page.settingsLines()[0].text : ""
          color: page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        // One block per calendar: its name and where it goes, whether it
        // works, what the agent sees of it, and what can be done to it.
        Repeater {
          model: page.settingsState && page.settingsState.configured ? page.settingsState.calendars : []
          Item {
            id: calRow
            required property var modelData
            required property int index
            readonly property bool picked: page.settingsFocus === index
            readonly property bool lit: picked && page.here === "center"
            onLitChanged: page.selected(calRow, "center", lit)
            Component.onCompleted: if (lit) page.selected(calRow, "center", true)
            width: parent.width
            height: calCol.implicitHeight + page.sp(16)

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -page.sp(10)
              anchors.rightMargin: -page.sp(10)
              radius: Style.cornerRadius
              color: calRow.picked ? Style.selectedFill : calHover.hovered ? Style.hoverFill : "transparent"
            }
            HoverHandler { id: calHover; enabled: !calRow.picked }

            MouseArea {
              anchors.fill: parent
              cursorShape: calRow.picked ? Qt.ArrowCursor : Qt.PointingHandCursor
              onClicked: { page.settingsFocus = calRow.index; settingsField.forceActiveFocus() }
            }

            Column {
              id: calCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: page.sp(4)

              Row {
                spacing: page.sp(10)
                Text {
                  textFormat: Text.PlainText
                  text: calRow.modelData.name
                  color: page.foreground
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }
                Text {
                  // Not when the name is the address already (a calendar
                  // not yet renamed is named for its host).
                  visible: calRow.modelData.address !== calRow.modelData.name + "/…"
                  anchors.baseline: parent.children[0].baseline
                  textFormat: Text.PlainText
                  text: calRow.modelData.address
                  color: page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.bodySmall)
                }
              }

              Text {
                readonly property var st: page.calendarStatus(calRow.modelData)
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: st.text
                color: st.tone === "urgent" ? page.urgent : page.dim
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.bodySmall)
              }

              // What the agent sees of it: the choice, and the way to change it.
              Row {
                spacing: page.sp(12)
                Text {
                  textFormat: Text.PlainText
                  text: page.sayShare(calRow.modelData)
                  color: calRow.modelData.agent === "all" ? page.foreground : page.dim
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.bodySmall)
                }
              }

              Row {
                spacing: page.sp(16)
                Repeater {
                  model: [{ text: calRow.modelData.agent === "all" ? "classes only" : "share everything", act: "settingsShare" },
                          { text: "fetch now", act: "settingsFetch" }, { text: "rename", act: "settingsRename" },
                          { text: "remove", act: "settingsForget" }]
                  Text {
                    required property var modelData
                    textFormat: Text.PlainText
                    text: modelData.text
                    color: actArea.containsMouse ? page.accent : page.faint
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.bodySmall)
                    MouseArea {
                      id: actArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        page.settingsFocus = calRow.index
                        if (modelData.act === "settingsShare") page.toggleShare(calRow.index)
                        else if (modelData.act === "settingsFetch") page.fetchCalendar(calRow.index)
                        else if (modelData.act === "settingsRename") page.startRename(calRow.index)
                        else page.removeCalendar(calRow.index)
                        settingsField.forceActiveFocus()
                      }
                      PanelToolTip { visible: parent.containsMouse; text: page.tip(modelData.text, modelData.act) }
                    }
                  }
                }
              }
            }
          }
        }

        Item { width: 1; height: page.sp(4) }

        TextField {
          id: settingsField
          width: parent.width
          placeholderText: page.settingsFieldKind === "rename" ? "its name"
            : page.settingsState && page.settingsState.configured
              ? "paste another calendar's address to add it" : "https://…  or  webcal://…"
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
          foreground: page.foreground
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) { if (page.settingsKey(event)) event.accepted = true }
        }

        Item { width: 1; height: page.sp(4) }

        Repeater {
          model: page.courseLines()
          Text {
            required property var modelData
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: modelData.text
            color: modelData.tone === "faint" ? page.faint : page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
        }

        Item { width: 1; height: page.sp(22) }

        // The agent: what runs, whether it has passed its evals, and the
        // week's review — the improvement loop, seen.
        Text {
          textFormat: Text.PlainText
          text: "The agent"
          color: pal.headings.length > 0 ? pal.headings[0] : page.accent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Its instructions change only by an edit you make, checked first against its eval cases "
            + "(longhand-agent eval run). Rate its replies in the margin; the weekly review collects what missed."
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        Repeater {
          model: ["margin", "plan"]
          Text {
            required property var modelData
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: page.sayEvalState(modelData)
            color: text.indexOf("passed") >= 0 ? page.dim : page.urgent
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
        }
        // What it knows: a count here, the notebook itself one key away.
        Row {
          spacing: page.sp(16)
          Text {
            textFormat: Text.PlainText
            text: page.sayNotebook()
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            textFormat: Text.PlainText
            text: "what it knows"
            color: knowsArea.containsMouse ? page.accent : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
            MouseArea {
              id: knowsArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.openNotebook()
              PanelToolTip { visible: parent.containsMouse; text: page.tip("what it knows", "settingsNotebook") }
            }
          }
        }
        Row {
          spacing: page.sp(16)
          Text {
            textFormat: Text.PlainText
            text: page.sayAutonomy()
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            textFormat: Text.PlainText
            text: "what it may do"
            color: mayArea.containsMouse ? page.accent : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
            MouseArea {
              id: mayArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.openAutonomy()
              PanelToolTip { visible: parent.containsMouse; text: page.tip("what it may do", "settingsAutonomy") }
            }
          }
        }
        Row {
          spacing: page.sp(16)
          Text {
            textFormat: Text.PlainText
            text: page.saySearchFolders()
            color: page.dim
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Text {
            textFormat: Text.PlainText
            text: "what it may search"
            color: searchArea.containsMouse ? page.accent : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
            MouseArea {
              id: searchArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: page.openSearchFolders()
              PanelToolTip { visible: parent.containsMouse; text: page.tip("what it may search", "settingsSearch") }
            }
          }
        }
        Text {
          visible: !!page.agentChecks && page.agentChecks.latest_review !== ""
          textFormat: Text.PlainText
          text: "open the latest review"
          color: reviewArea.containsMouse ? page.accent : page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
          MouseArea {
            id: reviewArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally("file://" + page.agentChecks.latest_review)
          }
        }

        Item { width: 1; height: page.sp(22) }

        Text {
          textFormat: Text.PlainText
          text: "Sound"
          color: pal.headings.length > 0 ? pal.headings[0] : page.accent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "A short, soft sound when you tick something. Never when you untick, never for what Longhand changes "
            + "itself, and never while notifications are silenced (Do Not Disturb)."
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Row {
          spacing: page.sp(16)
          Text {
            textFormat: Text.PlainText
            text: page.settingsData.tickSound === false ? "Off" : "On"
            color: page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
          Repeater {
            model: [{ text: page.settingsData.tickSound === false ? "turn on" : "turn off", act: "settingsSound" },
                    { text: "hear it", act: "" }]
            Text {
              required property var modelData
              textFormat: Text.PlainText
              text: modelData.text
              color: soundArea.containsMouse ? page.accent : page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.bodySmall)
              MouseArea {
                id: soundArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (modelData.act === "settingsSound") page.toggleTickSound(); else page.playTick(true); settingsField.forceActiveFocus() }
                PanelToolTip { visible: parent.containsMouse && modelData.act !== ""; text: page.tip(modelData.text, modelData.act) }
              }
            }
          }
        }

        Item { width: 1; height: page.sp(22) }

        // The pointer follows the keys (docs/navigation.md), as Hyprland's
        // follows the window.
        Text {
          textFormat: Text.PlainText
          text: "The pointer"
          color: pal.headings.length > 0 ? pal.headings[0] : page.accent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "The mouse pointer goes where the keys go, as Hyprland's goes to the window you move to: into the pane that has "
            + "the keys, onto the row selected in it, beside the note's cursor. Never while your hand is on the mouse."
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Row {
          spacing: page.sp(16)
          Repeater {
            model: [{ mode: "every", text: "every selection" }, { mode: "panes", text: "pane changes only" }, { mode: "off", text: "off" }]
            Text {
              required property var modelData
              textFormat: Text.PlainText
              text: modelData.text
              color: page.pointerMode === modelData.mode ? page.foreground : pointerArea.containsMouse ? page.accent : page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.bodySmall)
              MouseArea {
                id: pointerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  page.setPointer(modelData.mode)
                  settingsField.forceActiveFocus()
                }
                PanelToolTip { visible: parent.containsMouse; text: page.tip("The pointer: " + modelData.text, "settingsPointer") }
              }
            }
          }
        }

        Text {
          visible: page.settingsNote !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: page.settingsNote
          color: page.accent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.settingsFieldKind === "rename" ? "Enter renames it · Esc keeps the old name"
          : "Enter adds a calendar · ↑↓ pick one · " + page.keyName("settingsShare") + " what the agent sees · "
          + page.keyName("settingsFetch") + " fetches it · " + page.keyName("settingsRename") + " renames · "
          + page.keyName("settingsForget") + " removes it · " + page.keyName("settingsSound") + " tick sound · " + page.keyName("settingsPointer") + " the pointer · "
          + page.keyName("settingsNotebook") + " what the agent knows · " + page.keyName("settingsAutonomy") + " what it may do · " + page.keyName("settingsSearch") + " what it may search · Esc back"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
  }
}
