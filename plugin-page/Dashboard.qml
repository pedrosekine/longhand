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

// The dashboard (Ctrl+T): every open box and deadline, worked with keys
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: dash
  required property Item page
  readonly property var content: page.contentItem
  readonly property var pal: page.palette
  property alias dashKeysRef: dashKeys
  property alias dashWhenFieldRef: dashWhenField

  visible: page.dashOpen && !page.keysOpen && !page.settingsOpen
  x: page.wideX
  // Making room for the sidebar slides, as the note does (Page.qml, `sheet`).
  Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  y: page.alongside ? 0 : page.sheetMargin
  width: page.dashWidth
  height: page.alongside ? content.height : content.height - page.sheetMargin * 2
  radius: page.alongside ? 0 : Style.cornerRadius
  color: page.background
  borderSpec: page.alongside ? Border.none() : page.borderSpec
  padding: page.sheetPadding

  MouseArea { anchors.fill: parent; onClicked: dashKeys.forceActiveFocus() }

  Item {
    id: dashKeys
    anchors.fill: parent
    anchors.topMargin: dash.contentTopInset
    anchors.rightMargin: dash.contentRightInset
    anchors.bottomMargin: dash.contentBottomInset
    anchors.leftMargin: dash.contentLeftInset
    Keys.onPressed: function (event) {
      if (page.anywhereKey(event)) { event.accepted = true; return }
      if (page.dashKey(event)) event.accepted = true
    }

    Text {
      id: dashTitle
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: "DASHBOARD" + (page.dashCount === "" ? "" : "   ·   " + page.dashCount)
      color: page.dim
      font.family: page.fontFamily
      font.styleName: page.fontStyle
      font.pixelSize: page.fs(Style.font.caption)
    }

    Flickable {
      id: dashFlick
      anchors.top: dashTitle.bottom
      anchors.topMargin: page.sp(12)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: dashFoot.top
      anchors.bottomMargin: page.sp(10)
      clip: true
      contentWidth: width
      contentHeight: dashColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      TouchScroll { flickable: dashFlick }

      // Keep the focused row in view.
      function revealFocused() {
        var kids = dashColumn.children
        for (var i = 0; i < kids.length; i++) {
          var k = kids[i]
          if (k.index === undefined || k.index !== page.taskFocus) continue
          if (contentY > k.y) contentY = k.y
          else if (contentY + height < k.y + k.height) contentY = k.y + k.height - height
          return
        }
      }
      Connections { target: page; function onTaskFocusChanged() { Qt.callLater(dashFlick.revealFocused) } }

      Column {
        id: dashColumn
        // Wider than the note's measure, because a row is a title, a
        // place and a date rather than prose — but still a column, not
        // the whole wall.
        width: Math.min(parent.width, Math.round(page.measure * 1.45))
        x: Math.round((parent.width - width) / 2)
        spacing: 0

        Text {
          width: parent.width
          visible: page.taskRows.length === 0
          textFormat: Text.PlainText
          text: "nothing open"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        Repeater {
          model: page.taskRows
          Rectangle {
            id: dashRow
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind
            readonly property bool isHead: kind === "head" || kind === "month"
            readonly property var task: kind === "task" ? modelData.task : null
            readonly property var deadline: kind === "deadline" ? modelData.deadline : null
            // The line a deadline stands for: its priority is drawn too.
            readonly property var line: task || (deadline ? page.taskOfAnchor(deadline.id) : null)
            readonly property bool boxed: kind === "task" || kind === "deadline" || asks
            // The agent's proposal or question, under the box it is about.
            readonly property bool asks: kind === "proposal" || kind === "question" || kind === "told"
            readonly property bool fresh: asks && page.isNewAsk(modelData.item)
            readonly property string rowKey: page.rowKey(modelData)
            // Who made it (docs/agent.md): drawn in the box, as in the note.
            readonly property string author: page.rowAuthor(modelData)
            readonly property bool done: (deadline ? deadline.status !== "open" : (!!task && task.done)) || !!page.doneNow[rowKey]
            // The tick, felt: the box pops and fills, the check comes in,
            // the words are struck through left to right, the row glows
            // and settles. Only for the row just ticked; a row already
            // done is simply drawn done.
            onDoneChanged: if (done && page.justTicked === rowKey) tickAnim.restart()
            SequentialAnimation {
              id: tickAnim
              ParallelAnimation {
                NumberAnimation { target: box; property: "scale"; from: 1; to: 1.35; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: tickGlow; property: "opacity"; from: 0; to: 0.28; duration: 110 }
                NumberAnimation { target: strike; property: "progress"; from: 0; to: 0.15; duration: 110 }
              }
              ParallelAnimation {
                NumberAnimation { target: box; property: "scale"; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 3 }
                NumberAnimation { target: strike; property: "progress"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: tickGlow; property: "opacity"; to: 0; duration: 650; easing.type: Easing.OutQuad }
              }
            }
            readonly property bool late: !!deadline && deadline.status === "open" && deadline.due * 1000 < Date.now()
            // Lit only while the dashboard has the keys: one place is lit
            // at a time, in the pane the focus frame is around
            // (docs/navigation.md). The pointer follows it (page.selected).
            readonly property bool hot: page.taskFocus === index && !isHead && page.here === "center"
            onHotChanged: page.selected(dashRow, "center", hot)
            Component.onCompleted: if (hot) page.selected(dashRow, "center", true)
            // A click on it does something (activateTask): a hand, and a
            // faint fill while the mouse is over it (2026-10-19).
            readonly property bool acts: ["task", "deadline", "shelf", "grading", "raised", "proposal", "question", "told"].indexOf(kind) >= 0
            // Its chat, in brief: the gutter bar's state and, on the row the
            // keys are on, the last thing said (page.chatState).
            readonly property var chat: page.chatOf(modelData)
            readonly property string chatState: page.chatState(modelData)
            HoverHandler { id: rowHover; enabled: dashRow.acts }
            width: dashColumn.width
            // The space above a row comes from what it is and what came
            // before it, the way the note's own rhythm works (Rows.js).
            height: inner.implicitHeight + page.sp(16)
              + (kind === "head" ? page.sp(30) : kind === "month" ? page.sp(16) : 0)
            color: "transparent"

            Rectangle {
              anchors.fill: inner
              anchors.topMargin: -page.sp(7)
              anchors.bottomMargin: -page.sp(6)
              anchors.leftMargin: -page.sp(8)
              anchors.rightMargin: -page.sp(8)
              radius: Style.cornerRadius
              // The row talked about beside, while the keys are there: still
              // marked, faintly, so the list says which one it is.
              color: dashRow.hot ? Style.selectedFill
                : rowHover.hovered || (page.taskFocus === index && !isHead && page.talkOpen) ? Style.hoverFill : "transparent"
            }

            // The gutter bar, as the note draws one beside a block: the
            // accent while a reply waits unread, dim once read, a light
            // travelling down it while the agent answers; nothing for a
            // box never talked about.
            Item {
              visible: dashRow.chatState !== ""
              x: page.sp(1)
              y: inner.y - page.sp(3)
              width: page.sp(3)
              height: inner.height + page.sp(6)
              clip: true
              Rectangle {
                anchors.fill: parent
                radius: width
                color: dashRow.chatState === "unread" ? page.accent : page.dim
                opacity: dashRow.chatState === "thinking" ? 0.3 : 1
                Behavior on color { ColorAnimation { duration: 240 } }
                Behavior on opacity { NumberAnimation { duration: 240 } }
              }
              Rectangle {
                id: chatSpark
                width: parent.width
                height: Math.max(page.sp(12), parent.height * 0.5)
                radius: width
                visible: dashRow.chatState === "thinking"
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0) }
                  GradientStop { position: 0.5; color: page.accent }
                  GradientStop { position: 1.0; color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0) }
                }
                SequentialAnimation on y {
                  running: chatSpark.visible
                  loops: Animation.Infinite
                  NumberAnimation { from: -chatSpark.height; to: chatSpark.parent.height; duration: 1500; easing.type: Easing.InOutSine }
                }
              }
            }

            // The glow a tick leaves for a moment.
            Rectangle {
              id: tickGlow
              anchors.fill: inner
              anchors.topMargin: -page.sp(7)
              anchors.bottomMargin: -page.sp(6)
              anchors.leftMargin: -page.sp(8)
              anchors.rightMargin: -page.sp(8)
              radius: Style.cornerRadius
              color: pal.green
              opacity: 0
            }

            Item {
              id: inner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: page.sp(10) + (dashRow.asks && !!modelData.task ? Math.round(page.textSize * 0.72) + page.sp(10) : 0)
              anchors.rightMargin: page.sp(10)
              anchors.bottomMargin: page.sp(5)
              implicitHeight: texts.implicitHeight
              readonly property int lineH: Math.round(page.fs(Style.font.body) * 1.35)

              // A band: the course in full, or what the next rows are
              // asking of you. Drawn like a heading in the note, in the
              // theme's own heading colour.
              Text {
                id: bandText
                visible: dashRow.kind === "head"
                anchors.left: parent.left
                y: 0
                textFormat: Text.PlainText
                text: dashRow.kind === "head" ? modelData.text : ""
                color: {
                  if (pal.headings.length === 0) return page.accent
                  // A course is a heading of its own kind: the three
                  // bands that say what a row asks of you take the
                  // first colour, the courses the second.
                  var course = dashRow.kind === "head" && modelData.tag !== undefined && modelData.tag !== ""
                  return pal.headings[course && pal.headings.length > 1 ? 1 : 0]
                }
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.body)
              }

              Text {
                visible: dashRow.kind === "head" && modelData.tag !== undefined && modelData.tag !== ""
                anchors.left: bandText.right
                anchors.leftMargin: page.sp(8)
                anchors.bottom: bandText.bottom
                textFormat: Text.PlainText
                text: dashRow.kind === "head" ? (modelData.tag || "") : ""
                color: page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
              }

              // The month the rows under it fall in — the separation the
              // eye needs in a list that runs on.
              Text {
                visible: dashRow.kind === "month"
                anchors.left: parent.left
                y: 0
                textFormat: Text.PlainText
                text: dashRow.kind === "month" ? modelData.text.toUpperCase() : ""
                color: page.faint
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
                font.letterSpacing: 0.8
              }

              // The box, exactly as the note draws one: open is an
              // outline, closed is filled with a tick.
              Rectangle {
                id: box
                readonly property int size: Math.round(page.textSize * 0.72)
                visible: dashRow.boxed
                x: 0
                y: Math.round((inner.lineH - size) / 2)
                width: size
                height: size
                radius: Math.max(2, Math.round(size * 0.22))
                color: dashRow.done && dashRow.author === "" ? pal.green : "transparent"
                border.width: dashRow.done || dashRow.author !== "" ? 0 : Math.max(1, Math.round(page.textSize * 0.08))
                readonly property color edge: boxArea.containsMouse ? page.accent : dashRow.late ? page.urgent : page.dim
                border.color: edge

                // The agent's: a diamond. Made together: the seal.
                Rectangle {
                  visible: dashRow.author === "agent"
                  anchors.centerIn: parent
                  width: Math.round(box.size * 0.74)
                  height: width
                  rotation: 45
                  radius: Math.max(1, Math.round(width * 0.12))
                  color: dashRow.done ? pal.green : "transparent"
                  border.width: dashRow.done ? 0 : Math.max(1, Math.round(page.textSize * 0.08))
                  border.color: box.edge
                }
                LogoMark {
                  visible: dashRow.author === "together"
                  anchors.centerIn: parent
                  width: Math.round(box.size * 1.12)
                  height: width
                  outline: !dashRow.done
                  strokePx: Math.max(1, Math.round(page.textSize * 0.08))
                  color: dashRow.done ? pal.green : box.edge
                }
                // The outline gives way as the fill comes in, never
                // before: the box is never empty mid-tick.
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.width { NumberAnimation { duration: 140 } }

                Text {
                  anchors.centerIn: parent
                  opacity: dashRow.done ? 1 : 0
                  scale: dashRow.done ? 1 : 0.4
                  Behavior on opacity { NumberAnimation { duration: 160 } }
                  Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                  textFormat: Text.PlainText
                  text: "✓"
                  color: page.background
                  font.family: page.fontFamily
                  font.pixelSize: Math.round(box.size * (dashRow.author === "" ? 0.85 : 0.62))
                  font.bold: true
                }

                MouseArea {
                  id: boxArea
                  anchors.fill: parent
                  anchors.margins: -page.sp(6)
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true
                  onClicked: { page.taskFocus = dashRow.index; page.tickFocused() }
                  PanelToolTip { visible: parent.containsMouse; text: page.tip("Done (again: not done)", "dashDone") }
                }
              }

              // The priority, beside the box rather than in the words.
              Text {
                id: prioMark
                visible: text !== ""
                anchors.left: box.right
                anchors.leftMargin: page.sp(5)
                y: Math.round((inner.lineH - implicitHeight) / 2)
                textFormat: Text.PlainText
                text: page.taskMark(dashRow.line)
                color: dashRow.line && dashRow.line.priority >= 1 ? page.accent : page.faint
                font.family: page.fontFamily
                font.pixelSize: page.fs(Style.font.caption)
              }

              // "chat c": this row's chat, on the row the keys are on and the
              // one under the mouse (docs/keys-proposal.md, 2026-10-27). One
              // word whatever the chat holds; nothing on a private box, which
              // offers nothing of the agent's.
              Item {
                id: chatWord
                readonly property bool can: (dashRow.kind === "task" || dashRow.kind === "deadline" || dashRow.asks)
                  && !(dashRow.line && dashRow.line.private)
                visible: can && (dashRow.hot || rowHover.hovered)
                anchors.right: parent.right
                y: Math.round((inner.lineH - height) / 2)
                width: chatRow.implicitWidth
                height: chatRow.implicitHeight
                Row {
                  id: chatRow
                  spacing: page.sp(4)
                  Text {
                    anchors.baseline: chatKey.baseline
                    textFormat: Text.PlainText
                    text: "chat"
                    color: chatArea.containsMouse ? page.accent : page.dim
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.bodySmall)
                  }
                  Text {
                    id: chatKey
                    textFormat: Text.PlainText
                    text: page.keyName("dashTalk")
                    color: page.faint
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.caption)
                  }
                }
                MouseArea {
                  id: chatArea
                  anchors.fill: parent
                  anchors.margins: -page.sp(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { page.taskFocus = dashRow.index; page.talkFocused() }
                  PanelToolTip { visible: parent.containsMouse; text: page.tip("Chat about it", "dashTalk") }
                }
              }

              Row {
                id: pills
                anchors.right: chatWord.visible ? chatWord.left : parent.right
                anchors.rightMargin: chatWord.visible ? page.sp(10) : 0
                y: Math.round((inner.lineH - height) / 2)
                spacing: page.sp(6)
                Repeater {
                  model: page.pillsFor(dashRow.modelData)
                  Rectangle {
                    required property var modelData
                    readonly property bool filled: modelData.tone === "do"
                    readonly property color tint: modelData.tone === "late" ? page.urgent
                      : modelData.tone === "done" ? page.faint : page.dim
                    width: pillText.implicitWidth + Math.round(page.textSize * 0.9)
                    height: pillText.implicitHeight + Math.round(page.textSize * 0.25)
                    radius: height / 2
                    color: filled ? Style.selectedFill : "transparent"
                    border.width: filled ? 0 : 1
                    border.color: modelData.tone === "late" ? page.urgent : page.faint
                    Text {
                      id: pillText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData.text
                      color: parent.tint
                      font.family: page.fontFamily
                      font.styleName: page.fontStyle
                      font.pixelSize: Math.round(page.textSize * 0.78)
                    }
                  }
                }
              }

              Column {
                id: texts
                anchors.left: parent.left
                anchors.right: pills.left
                anchors.rightMargin: page.sp(12)
                anchors.leftMargin: (dashRow.boxed
                  ? box.size + page.sp(10) + (prioMark.visible ? prioMark.implicitWidth + page.sp(5) : 0)
                  : 0) + (rowLock.visible ? rowLock.width + page.sp(7) : 0)
                anchors.top: parent.top
                spacing: page.sp(3)

                // A private box (in a private block, on a private day, or
                // before the horizon): yours on the dashboard, with a lock,
                // and nothing of the agent's offered on it (2026-10-27).
                LockMark {
                  id: rowLock
                  parent: texts.parent
                  visible: !!(dashRow.task && dashRow.task.private)
                  x: texts.x - width - page.sp(7)
                  y: texts.y + Math.round((titleText.font.pixelSize * 1.3 - height) / 2)
                  width: page.sp(9)
                  color: page.magenta
                }

                Text {
                  id: titleText
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  wrapMode: Text.WordWrap
                  text: dashRow.kind === "proposal" || dashRow.kind === "told" ? page.sayAsk(modelData.item, !!modelData.task)
                    : dashRow.kind === "question" ? modelData.item.question
                    : dashRow.kind === "shelf" ? "+" + modelData.count + " set aside · " + page.keyName("dashOpen") + " to show"
                    : dashRow.kind === "grading" ? "+" + modelData.count + " waiting for a grade · " + page.keyName("dashOpen") + " to show"
                    : dashRow.kind === "raised"
                      ? (modelData.item.kind === "suggestion" ? "◇ " : "· ") + modelData.item.text
                    : dashRow.kind === "deadline" ? modelData.deadline.title
                    : dashRow.kind === "task" ? page.taskTitle(modelData.task)
                    : " "
                  color: dashRow.isHead ? "transparent"
                    : dashRow.kind === "shelf" || dashRow.kind === "grading" ? page.faint
                    : dashRow.task && dashRow.task.away ? page.dim
                    : dashRow.done ? page.dim
                    : dashRow.late ? page.urgent : page.foreground
                  Behavior on color { ColorAnimation { duration: 300 } }
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)

                  // Struck through, drawn rather than the font's, so a
                  // tick can draw it left to right (tickAnim).
                  Rectangle {
                    id: strike
                    // The row just ticked starts unstruck; its tick draws it.
                    property real progress: dashRow.done && page.justTicked !== dashRow.rowKey ? 1 : 0
                    visible: dashRow.boxed && progress > 0
                    x: 0
                    y: Math.round(inner.lineH / 2) - 1
                    height: Math.max(1, Math.round(page.textSize * 0.07))
                    width: Math.min(titleText.implicitWidth, titleText.width) * progress
                    color: page.dim
                  }
                }

                // The reason line; what the agent proposed since the
                // dashboard was last left says so first, in the accent.
                Row {
                  visible: freshMark.visible || caption.text !== ""
                  width: parent.width
                  spacing: page.sp(8)

                  Text {
                    id: freshMark
                    visible: dashRow.fresh
                    textFormat: Text.PlainText
                    text: "new"
                    color: page.accent
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.caption)
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: page.sp(1)
                  }

                  Text {
                    id: caption
                    width: parent.width - (freshMark.visible ? freshMark.implicitWidth + parent.spacing : 0)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: dashRow.kind === "proposal" || dashRow.kind === "told" ? (modelData.item.why || "")
                      : dashRow.kind === "question" ? "recommended: " + modelData.item.recommended
                      : dashRow.kind === "task" ? page.taskWhere(modelData.task, modelData.under)
                      : dashRow.kind === "deadline" ? page.deadlineWhere(modelData.deadline)
                      : dashRow.kind === "raised" ? (modelData.item.evidence || "")
                      : ""
                    color: page.faint
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.caption)
                  }
                }

                // Where its chat left off, on the row the keys are on: the
                // agent's last word (◇, as its marks are), or yours.
                Text {
                  visible: dashRow.hot && !!dashRow.chat
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: dashRow.chat ? (dashRow.chat.role === "agent" ? "◇ " : "you: ") + dashRow.chat.text : ""
                  color: dashRow.chatState === "unread" ? page.foreground : page.dim
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: !dashRow.isHead
              acceptedButtons: Qt.LeftButton
              hoverEnabled: true
              cursorShape: dashRow.acts ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: { page.taskFocus = index; page.activateTask() }
              PanelToolTip {
                readonly property string kind: dashRow.modelData.kind
                visible: parent.containsMouse && (kind === "task" || kind === "deadline" || kind === "shelf" || kind === "grading" || kind === "raised"
                                                  || kind === "proposal" || kind === "question" || kind === "told")
                text: kind === "task" ? page.tips([["Go to the line", "dashOpen"], ["Done", "dashDone"], ["Reschedule", "dashWhen"], ["Take the date off", "dashNoDate"],
                                                   ["Cycle its priority", "dashPriority"], ["Rename", "dashRename"],
                                                   [dashRow.task && dashRow.task.away ? "Back" : "Set aside", "dashShelve"], ["Renew", "dashKeep"], ["Drop it", "dashDrop"]]
                                                  .concat(chatWord.can ? [["Chat about it", "dashTalk"]] : []))
                  : kind === "deadline" ? page.tips([["Go to its line", "dashOpen"], ["Done", "dashDone"], ["The day to work on it", "dashWhen"], ["Take that day off", "dashNoDate"], ["Cycle its priority", "dashPriority"], ["Grade", "dashGrade"]]
                                                   .concat(chatWord.can ? [["Chat about it", "dashTalk"]] : []))
                  : kind === "told" ? page.tips([["Let it stand", "dashDone"], ["Undo it", "dashDrop"], ["Chat about it", "dashOpen"]])
                  : kind === "proposal" && dashRow.modelData.item.kind === "file"
                    ? page.tips([["File it: moved from Downloads into the course's documents", "dashDone"], ["Decline", "dashDrop"], ["Open it first", "dashOpen"]])
                  : kind === "proposal" ? page.tips([["Accept", "dashDone"], ["Decline", "dashDrop"], ["Chat about it", "dashOpen"]])
                  : kind === "question" ? page.tips([["Accept the recommended answer", "dashDone"], ["Chat about it: answer in your words, or ask back", "dashOpen"], ["Decline", "dashDrop"]])
                  : kind === "shelf" ? page.tip("Show what is set aside", "dashOpen")
                  : kind === "grading" ? page.tip("Show what waits for a grade", "dashOpen")
                  : page.tip("Dismiss it", "dashOpen")
              }
              z: -1
            }
          }
        }

      }
    }

    Item {
      id: dashFoot
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(dashWhenRow.implicitHeight, dashHint.implicitHeight)

      Text {
        id: dashHint
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !page.dashWhenFor
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.keyName("dashUp") + page.keyName("dashDown") + " move · " + page.keyName("dashOpen") + " opens the line · "
          + page.keyName("dashTalk") + " chat · "
          + page.keyName("dashDone") + " done · " + page.keyName("dashWhen") + " when · " + page.keyName("dashPriority") + " priority · "
          + page.keyName("dashShelve") + " set aside · " + page.keyName("dashKeep") + " renew · " + page.keyName("dashGrade") + " grade · "
          + page.keyName("dashPlan") + " plan now · "
          + page.keyName("dashRename") + " rename · " + page.keyName("dashDrop") + " cancel · " + page.keyName("dashUndo") + " undo · " + page.keyName("dashBack") + " back · "
          + page.keyName("keysHere") + " all keys"
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }

      Row {
        id: dashWhenRow
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !!page.dashWhenFor
        spacing: page.sp(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: !page.dashWhenFor ? ""
            : page.dashFieldKind === "rename" ? "rename"
            : page.dashFieldKind === "grade" ? "grade · " + page.dashWhenFor.deadline.title
            : "when · " + page.taskTitle(page.dashWhenFor)
          color: page.dim
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        TextField {
          id: dashWhenField
          width: page.dashFieldKind === "rename" ? page.sp(460) : page.sp(220)
          placeholderText: page.dashFieldKind === "rename" ? "its words"
            : page.dashFieldKind === "grade" ? "7.5, A-… · empty clears"
            : "friday, tomorrow, 20 oct…"
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
          foreground: page.foreground
          onTextChanged: page.dashWhenText = text
          // The global keys first, as in every box (it was the one box
          // without them until 2026-10-23).
          Keys.onPressed: function (event) { if (page.anywhereKey(event)) event.accepted = true }
          Keys.onReturnPressed: function (event) { event.accepted = true; page.commitDashWhen() }
          Keys.onEnterPressed: function (event) { event.accepted = true; page.commitDashWhen() }
          Keys.onEscapePressed: function (event) { event.accepted = true; page.dashWhenFor = null; page.dashWhenText = "" }
        }
      }

      Connections {
        target: page
        function onDashWhenForChanged() {
          if (page.dashWhenFor) { dashWhenField.text = page.dashFieldStart; dashWhenField.forceActiveFocus(); dashWhenField.selectAll() }
          else if (page.dashOpen) dashKeys.forceActiveFocus()
        }
      }
    }
  }
}
