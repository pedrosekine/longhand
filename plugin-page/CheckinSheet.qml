import Quickshell
import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui

// How Longhand feels this week (2026-11-18, the UX evaluation's F7): the
// eight pairs of the short User Experience Questionnaire (agent/checkin.py),
// each answered on seven steps, then the weeks so far beside the agent's
// share of its proposals acted on. Settings' fourth view, drawn in its
// place; the dashboard's quiet line (F) opens it too. Keys: ↑↓ a pair, ←→
// or 1–7 a step, Backspace clears one, Enter keeps the week, Del skips it
// (asking first once anything is answered), Esc goes back.
BorderSurface {
  id: checkinSheet
  required property Item page
  readonly property var content: page.contentItem
  property alias checkinKeysRef: checkinKeys

  visible: page.centerView === "settings" && page.settingsView === "checkin"
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
    id: checkinKeys
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { if (page.checkinKey(event)) event.accepted = true }
  }

  MouseArea { anchors.fill: parent; onClicked: checkinKeys.forceActiveFocus() }

  Item {
    anchors.fill: parent
    anchors.topMargin: checkinSheet.contentTopInset
    anchors.rightMargin: checkinSheet.contentRightInset
    anchors.bottomMargin: checkinSheet.contentBottomInset
    anchors.leftMargin: checkinSheet.contentLeftInset

    Item {
      id: body
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: parent.height
      // The words beside the steps take what the steps leave, in a narrow
      // pane too: sized by the measure alone, they ran off the card.
      readonly property int wordWidth: Math.max(page.sp(40), Math.min(Math.round(page.measure * 0.34),
        Math.floor((width - (7 * Math.round(page.textSize * 1.25) + 6 * page.sp(10)) - 2 * page.sp(18)) / 2)))

      SettingsCrumb {
        id: title
        page: checkinSheet.page
        anchors.top: parent.top
        anchors.left: parent.left
        title: "HOW IT FEELS" + (page.checkinData ? " · " + page.checkinData.week.replace("-W", " WEEK ") : "")
        // Opened from the dashboard, it goes back there, as Esc does.
        backTo: page.checkinFromDash ? "DASHBOARD" : "SETTINGS"
        onBack: page.closeCheckin()
      }

      Text {
        id: intro
        anchors.top: title.bottom
        anchors.topMargin: page.sp(18)
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "This week, Longhand is… One step on each line, nearer the word that fits; there are no right answers, "
          + "and the first feeling is the one asked for. Once a week; kept in your vault, nowhere else."
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      Flickable {
        id: checkinFlick
        acceptedButtons: Qt.NoButton
        QC.ScrollBar.vertical: ScrollMark { page: checkinSheet.page }
        anchors.top: intro.bottom
        anchors.topMargin: page.sp(18)
        anchors.bottom: checkinFoot.top
        anchors.bottomMargin: page.sp(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: -page.sp(10)
        anchors.rightMargin: -page.sp(10)
        clip: true
        contentWidth: width
        contentHeight: checkinBody.implicitHeight + page.sp(8)
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { flickable: checkinFlick }

      Column {
        id: checkinBody
        x: page.sp(10)
        width: checkinFlick.width - page.sp(20)
        spacing: page.sp(18)

      // Not read yet, or not read at all: said.
      Text {
        visible: !page.checkinData
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: page.sayUnread("checkin")
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      // This week kept already: its answers are shown, to change.
      Text {
        visible: !!page.checkinKept() && !page.checkinAsking
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: { var w = page.checkinKept(); return !w ? "" : w.skipped ? "This week was skipped. Answer it now, and Enter keeps it."
                : "This week is kept, as shown. Change a line, and Enter keeps it again." }
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }

      Column {
        id: pairs
        width: parent.width
        spacing: page.sp(4)

        Repeater {
          model: page.checkinData ? page.checkinData.items : []
          Item {
            id: pairRow
            required property var modelData
            required property int index
            readonly property bool picked: page.checkinFocus === index
            readonly property int value: page.checkinAnswers[index] || 0
            readonly property bool lit: picked && page.here === "center" && checkinSheet.visible
            onPickedChanged: if (picked) {
              var top = pairs.y + y
              var bot = top + height
              if (top < checkinFlick.contentY) checkinFlick.contentY = Math.max(0, top)
              else if (bot > checkinFlick.contentY + checkinFlick.height) checkinFlick.contentY = Math.max(0, bot - checkinFlick.height)
            }
            onLitChanged: page.selected(pairRow, "center", lit)
            Component.onCompleted: if (lit) page.selected(pairRow, "center", true)
            width: parent.width
            height: steps.implicitHeight + page.sp(14)

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -page.sp(10)
              anchors.rightMargin: -page.sp(10)
              radius: Style.cornerRadius
              color: pairRow.picked ? Style.selectedFill : pairHover.hovered && page.handOn ? Style.hoverFill : "transparent"
            }
            HoverHandler { id: pairHover }
            // A click on the row's words brings the keys to it, as its
            // hover mark promises; a step's circle picks that step
            // (2026-11-25, the mouse pass: the row lit and did nothing).
            MouseArea {
              anchors.fill: parent
              z: -1
              onClicked: { page.checkinFocus = pairRow.index; checkinKeys.forceActiveFocus() }
            }

            Text {
              anchors.right: steps.left
              anchors.rightMargin: page.sp(18)
              anchors.verticalCenter: parent.verticalCenter
              width: body.wordWidth
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
              textFormat: Text.PlainText
              text: pairRow.modelData[0]
              color: pairRow.value > 0 && pairRow.value < 4 ? page.foreground : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.body)
            }

            Row {
              id: steps
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              spacing: page.sp(10)
              Repeater {
                model: 7
                Item {
                  required property int index
                  readonly property int step: index + 1
                  readonly property bool chosen: pairRow.value === step
                  width: Math.round(page.textSize * 1.25)
                  height: width
                  Rectangle {
                    anchors.centerIn: parent
                    // The middle step a touch smaller: "neither", not a choice to lean on.
                    width: Math.round(parent.width * (parent.step === 4 ? 0.42 : 0.55))
                    height: width
                    radius: width / 2
                    color: parent.chosen ? page.accent : "transparent"
                    border.width: parent.chosen ? 0 : 1
                    border.color: stepArea.containsMouse && page.handOn ? page.accent : pairRow.picked ? page.dim : page.faint
                  }
                  MouseArea {
                    id: stepArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.checkinFocus = pairRow.index; page.setCheckin(pairRow.index, parent.step, true); checkinKeys.forceActiveFocus() }
                  }
                }
              }
            }

            Text {
              anchors.left: steps.right
              anchors.leftMargin: page.sp(18)
              anchors.verticalCenter: parent.verticalCenter
              width: body.wordWidth
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: pairRow.modelData[1]
              color: pairRow.value > 4 ? page.foreground : page.dim
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.body)
            }
          }
        }
      }

      // Keep the week, or skip it: said as the dashboard's keys are, and
      // clickable.
      // While Del asks, the question and its two answers, as removing a
      // calendar asks.
      Row {
        id: actions
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: page.sp(28)
        Text {
          visible: page.checkinAsking
          textFormat: Text.PlainText
          text: page.checkinKept() ? "Skip this week? Its answers are let go." : "Skip this week? What is answered is let go."
          color: page.urgent
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }
        Repeater {
          model: page.checkinAsking
            ? [{ text: "skip it", act: "yes", key: "Enter", tip: "" }, { text: "keep answering", act: "no", key: "Esc", tip: "" }]
            : [{ text: page.checkinLeft === 0 ? "keep this week" : page.checkinLeft + " to go", act: "keep", key: "Enter",
                 tip: page.checkinLeft === 0 ? "Keep these answers for this week" : "Answer every line first: 1–7, or ←→" },
               { text: "skip this week", act: "skip", key: "Del", tip: "Skip this week's check-in (it asks first once anything is answered)" }]
          Text {
            required property var modelData
            textFormat: Text.PlainText
            text: modelData.text + "  " + modelData.key
            color: actArea.containsMouse && page.handOn ? page.accent
              : modelData.act === "keep" && page.checkinLeft === 0 ? page.foreground : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
            MouseArea {
              id: actArea
              anchors.fill: parent
              anchors.margins: -page.sp(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.act === "keep") page.keepCheckin()
                else if (modelData.act === "skip") page.askSkipCheckin()
                else if (modelData.act === "yes") page.skipCheckin()
                else page.checkinAsking = false
                checkinKeys.forceActiveFocus()
              }
              Tip { host: page; shown: parent.containsMouse && modelData.tip !== ""; text: modelData.tip + "   " + modelData.key }
            }
          }
        }
      }

      // The weeks so far: practical and pleasant (each -3..+3), and the
      // agent's share of its proposals acted on, so a change can be told
      // from how it felt.
      Column {
        width: parent.width
        spacing: page.sp(5)
        visible: page.checkinWeeks.length > 0
        Text {
          textFormat: Text.PlainText
          text: "THE WEEKS SO FAR"
          color: page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
        Repeater {
          model: page.checkinWeeks
          Text {
            required property var modelData
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: page.sayCheckinWeek(modelData)
            color: modelData.skipped ? page.faint : page.foreground
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.bodySmall)
          }
        }
      }
      }
      }

      SettingsFoot {
        id: checkinFoot
        page: checkinSheet.page
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        keys: page.checkinAsking ? "Enter skips the week · any other key keeps answering"
          : "↑↓ a line · ←→ or 1–7 a step · Backspace clears it · Enter keeps the week · Del skips it · Esc back"
      }
    }
  }
}
