import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
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
import "Say.js" as Say

// The dashboard (Ctrl+2, Ctrl+Alt+2): every open box and deadline, worked with keys
// Moved out of Page.qml on 2026-10-18 (tools/extract_sheet.py); `page` is
// the page itself.
BorderSurface {
  id: dash
  required property Item page
  readonly property var content: page.contentItem
  readonly property var pal: page.palette
  property alias dashKeysRef: dashKeys
  property alias searchFieldRef: searchChip.field
  // The dashboard has the keys: its list and strip, or ⌕'s line of text.
  readonly property bool keysHere: dashKeys.activeFocus || searchChip.field.activeFocus
  // ⌕ has the keys whenever the strip's cursor is on it, folded.
  function syncSearchFocus() {
    var want = page.stripAt === 0 && !page.stripOpen && page.dashOpen
    if (want && dashKeys.activeFocus) searchChip.field.forceActiveFocus()
    else if (!want && searchChip.field.activeFocus) dashKeys.forceActiveFocus()
  }
  Connections {
    target: page
    function onStripAtChanged() { dash.syncSearchFocus() }
    function onStripOpenChanged() { dash.syncSearchFocus() }
    function onDashQueryChanged() { if (searchChip.field.text !== page.dashQuery && !page.dashSearchPending) searchChip.field.text = page.dashQuery }
  }
  property alias dashWhenFieldRef: dashWhenField
  property alias dashColumnRef: dashColumn    // the drawn rows, for the tests

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

  // A chip on the course strip: lit where the strip's cursor is,
  // underlined when the list shows its course (2026-11-14: outlined, it
  // read as a warning, the one orange box on the page). The ⌕ chip holds a line of text of its
  // own (2026-11-13), with every key a line of text has — Ctrl+A, paste,
  // the arrows, Shift to select, Ctrl+Backspace, undo — and its own caret,
  // right after the last letter. It was drawn words and a drawn caret
  // beside them, a space away, and took only letters and Backspace.
  component Chip: Rectangle {
    id: chip
    required property Item page
    property bool keys: false            // the dashboard has the keys
    property int at: -1
    property string label: ""
    property string count: ""
    property bool on: false
    property bool search: false
    property bool alert: false           // its words in the accent: something waits there
    property string tip: ""
    property var action: null            // a click does this, not what a chip picks
    readonly property bool cur: page.stripAt === at && !page.stripOpen && keys
    property alias field: searchField
    onCurChanged: page.selected(chip, "center", cur)
    width: chipRow.implicitWidth + page.sp(16)
    height: chipRow.implicitHeight + Math.round(page.textSize * 0.3)
    radius: Style.cornerRadius
    color: cur ? Style.selectedFill : chipHover.hovered && page.handOn ? Style.hoverFill : "transparent"
    HoverHandler { id: chipHover }
    Tip { host: chip.page; shown: chip.tip !== "" && chipHover.hovered; text: chip.tip }
    Rectangle {
      visible: chip.on
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: chipRow.implicitWidth
      height: Math.max(2, page.sp(2))
      color: page.accent
    }
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: page.sp(5)
      // A key the line of text left alone stops here: passed on to the
      // dashboard, ⌕'s old keys would type it a second time.
      Keys.onPressed: function (event) { event.accepted = chip.search }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.label
        color: chip.on || chip.alert ? page.accent : chip.cur ? page.foreground : page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
      }
      // What is typed into ⌕: its own words at once, the list narrowed a
      // moment after (page.dashSearchEdited), so a letter is never waiting on
      // the list to show.
      TextInput {
        id: searchField
        visible: chip.search && (chip.cur || activeFocus || text !== "")
        enabled: chip.search
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1, contentWidth + (activeFocus ? cursorRectangle.width : 0))
        clip: false
        color: chip.on ? page.accent : page.foreground
        selectionColor: page.palette.selection
        selectedTextColor: page.foreground
        selectByMouse: true
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.bodySmall)
        onTextChanged: if (text !== page.dashQuery || page.dashSearchPending) page.dashSearchEdited(text)
        onActiveFocusChanged: if (activeFocus && page.stripAt !== chip.at) page.stripAt = chip.at
        // The strip's own keys first (Esc, ↓, Enter, → past the last
        // letter, the page's global keys); the rest are the line's.
        Keys.onPressed: function (event) { if (page.dashSearchKey(event, searchField)) event.accepted = true }
      }
      Text {
        visible: chip.count !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.count
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
    MouseArea {
      anchors.fill: parent
      // On ⌕ the pointer reaches the words, to place the caret and select.
      enabled: !(chip.search && searchField.activeFocus)
      cursorShape: chip.search ? Qt.IBeamCursor : Qt.PointingHandCursor
      onClicked: chip.action ? chip.action() : page.clickChip(chip.at)
    }
  }

  // A row of the strip unfolded: a course with what it holds, or an order.
  component Unfolded: Rectangle {
    id: urow
    required property Item page
    property bool keys: false
    property int pick: -1
    property string digit: ""
    property bool on: false
    property string name: ""
    property string tag: ""
    property string holds: ""
    property string next: ""
    signal clicked()
    readonly property bool cur: page.stripOpen && page.stripPick === pick && keys
    onCurChanged: page.selected(urow, "center", cur)
    width: parent ? parent.width : 0
    height: ucol.implicitHeight + page.sp(8)
    color: cur ? Style.selectedFill : uHover.hovered && page.handOn ? Style.hoverFill : "transparent"
    HoverHandler { id: uHover }
    Column {
      id: ucol
      x: page.sp(12)
      width: parent.width - page.sp(24)
      anchors.verticalCenter: parent.verticalCenter
      spacing: page.sp(1)
      Item {
        width: parent.width
        height: uname.implicitHeight
        Text {
          id: udigit
          width: page.sp(18)
          textFormat: Text.PlainText
          text: urow.digit
          color: page.faint
          font.family: page.codeFamily
          font.pixelSize: page.fs(Style.font.caption)
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          id: udot
          anchors.left: udigit.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: urow.on ? "●" : "○"
          color: urow.on ? page.accent : page.faint
          font.pixelSize: page.fs(Style.font.caption)
        }
        Text {
          id: uname
          anchors.left: udot.right
          anchors.leftMargin: page.sp(8)
          textFormat: Text.PlainText
          text: urow.name
          color: page.foreground
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.body)
        }
        Text {
          anchors.left: uname.right
          anchors.leftMargin: page.sp(8)
          anchors.baseline: uname.baseline
          visible: urow.tag !== ""
          textFormat: Text.PlainText
          text: urow.tag
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
        Text {
          anchors.right: parent.right
          anchors.baseline: uname.baseline
          textFormat: Text.PlainText
          text: urow.holds
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }
      }
      Text {
        visible: urow.next !== ""
        x: udigit.width + udot.implicitWidth + page.sp(8)
        width: parent.width - x
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: urow.next
        color: page.faint
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { page.stripPick = urow.pick; urow.clicked() } }
  }

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
    // The keys given back to the dashboard while the strip's cursor is on
    // ⌕ (the pane keys, a sheet closed): on to its line of text.
    onActiveFocusChanged: if (activeFocus) Qt.callLater(dash.syncSearchFocus)

    // The name, and how the list is laid out: the bands folded or not, the
    // order (2026-11-14). In the strip's column, so the page has one left
    // edge; what narrows the list is the strip's row alone, under it.
    Item {
      id: dashTitle
      anchors.top: parent.top
      x: strip.x
      width: strip.width
      height: orderChip.height
      Text {
        x: page.sp(8)
        width: Math.max(0, (foldAllRow.visible ? foldAllRow.x : orderChip.x) - x - page.sp(16))
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: "DASHBOARD" + (page.dashStatus === "" ? "" : "   ·   " + page.dashStatus)
        color: page.dim
        font.family: page.fontFamily
        font.styleName: page.fontStyle
        font.pixelSize: page.fs(Style.font.caption)
        font.letterSpacing: 0.8
      }
      // By date: every band at once (2026-11-03). The word that would
      // change nothing is faint.
      Row {
        id: foldAllRow
        visible: page.dashOrder === "date" && page.taskRows.some(function (r) { return r.kind === "band" && r.count > 0 && !r.fixed })
        readonly property bool anyShut: page.taskRows.some(function (r) { return r.kind === "band" && r.count > 0 && !r.fixed && !r.open })
        readonly property bool anyOpen: page.taskRows.some(function (r) { return r.kind === "band" && r.count > 0 && !r.fixed && r.open })
        anchors.right: orderChip.left
        anchors.rightMargin: page.sp(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: page.sp(6)
        Repeater {
          model: [{ word: "expand all", open: true, key: "dashUnfoldAll" }, { word: "collapse all", open: false, key: "dashFoldAll" }]
          Text {
            required property var modelData
            required property int index
            readonly property bool live: modelData.open ? foldAllRow.anyShut : foldAllRow.anyOpen
            textFormat: Text.PlainText
            text: (index > 0 ? "·  " : "") + modelData.word
            color: foldHover.containsMouse && live && page.handOn ? page.accent : live ? page.dim : page.faint
            font.family: page.fontFamily
            font.styleName: page.fontStyle
            font.pixelSize: page.fs(Style.font.caption)
            MouseArea {
              id: foldHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: parent.live ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: { dashKeys.forceActiveFocus(); page.foldAll(modelData.open) }
              Tip { host: page; shown: parent.containsMouse; text: page.tip(modelData.open ? "Expand every band" : "Collapse every band", modelData.key) }
            }
          }
        }
      }
      // The strip's last stop, though drawn up here: ← → and Enter reach
      // it as before.
      Chip {
        id: orderChip
        page: dash.page
        keys: dash.keysHere
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        at: page.stripEnd
        label: "by " + strip.orderWords[page.dashOrder] + (page.stripOpen ? "  ▴" : "  ▾")
      }
    }

    // The course strip (2026-11-03): ⌕ to type into, All, a chip for each
    // course with something open, then the agent's chip; the order, its
    // last stop, is drawn on the title row. Under it, what the list shows
    // when it is narrowed; unfolded, every course with what it holds and
    // the orders. ↑ from the first row climbs onto it.
    Item {
      id: strip
      readonly property var orderWords: ({ ask: "what it asks", course: "course", date: "date" })
      anchors.top: dashTitle.bottom
      anchors.topMargin: page.sp(10)
      width: Math.min(parent.width, Math.round(page.measure * 1.45))
      x: Math.round((parent.width - width) / 2)
      height: stripCol.implicitHeight

      Column {
        id: stripCol
        width: parent.width
        spacing: page.sp(4)

        Item {
          width: parent.width
          height: chipFlow.implicitHeight
          Flow {
            id: chipFlow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: page.sp(4)
            Chip {
              id: searchChip
              page: dash.page
              keys: dash.keysHere
              at: 0
              search: true
              label: "⌕"
              // Lit by what is in the line, with the letter itself: by the
              // query it lit a frame later, when the list was narrowed.
              on: searchChip.field.text !== "" || page.dashQuery !== ""
            }
            Chip {
              page: dash.page
              keys: dash.keysHere
              at: 1
              label: "All"
              count: String(page.dashCourses.total)
              on: page.dashLens.length === 0
            }
            Repeater {
              // By the courses' tags, which typing does not change: the
              // chips stay, only their counts move (2026-11-13). Drawn
              // from stripChips itself, every letter drew them anew.
              model: page.stripChipTags
              Chip {
                required property int index
                readonly property var modelData: page.stripChips[index] || ({ tag: "", label: "", count: 0 })
                page: dash.page
                keys: dash.keysHere
                at: index + 2
                label: modelData.label
                count: String(modelData.count)
                on: page.dashLens.indexOf(modelData.tag) >= 0
              }
            }
            // The agent's: what it asks of the courses shown, and what is
            // new since the last visit. Not a filter and not a stop of the
            // strip: a click goes to the next thing it asks, as N does.
            Item { width: page.sp(10); height: 1; visible: agentChip.visible }
            Chip {
              id: agentChip
              page: dash.page
              at: -2
              visible: page.dashAgent.asks > 0
              alert: page.dashAgent.fresh > 0
              label: "◇ from the agent"
              count: page.dashAgent.asks + (page.dashAgent.fresh > 0 ? " · " + page.dashAgent.fresh + " new" : "")
              tip: page.tip("Go to the next thing the agent asks", "dashNextAsk")
              action: page.clickAgentChip
            }
          }
        }

        // What the list shows, when it is narrowed: never a filter you
        // cannot see.
        Text {
          visible: page.dashNarrowed
          x: page.sp(8)
          width: parent.width - page.sp(8)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: !page.dashNarrowed ? ""
            : "showing " + page.dashCourses.shown + " of " + page.dashCourses.total
              + (page.dashLens.length > 0 ? "  ·  " + page.dashLens.map(function (t) { return t === "" ? "no project" : "#" + t }).join(" + ") : "")
              + (page.dashQuery.trim() !== "" ? "  ·  “" + page.dashQuery.trim() + "”" : "")
              + (page.dashCourses.outside > 0 ? "  ·  " + page.dashCourses.outside + " from the agent outside it" : "")
              + "  ·  " + page.keyName("dashAll") + " shows all"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.caption)
        }

        Rectangle {
          visible: page.stripOpen
          width: parent.width
          height: visible ? unfoldCol.implicitHeight + page.sp(12) : 0
          radius: Style.cornerRadius
          color: page.sunk
          border.width: 1
          border.color: page.faint
          Column {
            id: unfoldCol
            y: page.sp(6)
            width: parent.width
            spacing: 0
            Unfolded {
              page: dash.page
              keys: dash.keysHere
              pick: 0
              name: "⌕ " + (page.dashQuery !== "" ? page.dashQuery : "")
              holds: page.dashQuery === "" ? "type words, or a #tag" : ""
              onClicked: dashKeys.forceActiveFocus()
            }
            Text {
              x: page.sp(12)
              topPadding: page.sp(8)
              textFormat: Text.PlainText
              text: "COURSES"
              color: page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
              font.letterSpacing: 0.8
            }
            Repeater {
              model: page.stripChipTags
              Unfolded {
                required property int index
                readonly property var modelData: page.stripChips[index] || ({ tag: "", name: "", due: 0, doing: 0, later: 0, next: null })
                page: dash.page
                keys: dash.keysHere
                pick: index + 1
                digit: index < 9 ? String(index + 1) : ""
                on: page.dashLens.indexOf(modelData.tag) >= 0
                name: modelData.name
                tag: modelData.tag === "" ? "" : "#" + modelData.tag
                holds: [modelData.due > 0 ? modelData.due + " due" : "", modelData.doing > 0 ? modelData.doing + " doing" : "",
                        modelData.later > 0 ? modelData.later + " no day" : ""].filter(function (x) { return x !== "" }).join(" · ")
                next: modelData.next ? "next: " + Qt.formatDate(new Date(modelData.next.due * 1000), "ddd d MMM") + " · " + modelData.next.title : ""
                onClicked: { dashKeys.forceActiveFocus(); page.toggleLens(modelData.tag) }
              }
            }
            Text {
              x: page.sp(12)
              topPadding: page.sp(8)
              textFormat: Text.PlainText
              text: "ORDER"
              color: page.faint
              font.family: page.fontFamily
              font.styleName: page.fontStyle
              font.pixelSize: page.fs(Style.font.caption)
              font.letterSpacing: 0.8
            }
            Repeater {
              model: page.dashOrders
              Unfolded {
                required property var modelData
                required property int index
                page: dash.page
                keys: dash.keysHere
                pick: page.stripChips.length + 1 + index
                digit: page.keyName("dashOrder")
                on: page.dashOrder === modelData
                name: "by " + strip.orderWords[modelData]
                onClicked: { dashKeys.forceActiveFocus(); page.dashOrder = modelData; page.savePageState() }
              }
            }
          }
        }
      }
    }

    Flickable {
      id: dashFlick
      anchors.top: strip.bottom
      anchors.topMargin: page.sp(10)
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
        // A gutter is kept on each side even in a narrow window, for the
        // chat key that stands left of the selected row (chatKey).
        width: Math.min(parent.width - 2 * page.sp(28), Math.round(page.measure * 1.45))
        x: Math.round((parent.width - width) / 2)
        spacing: 0

        Text {
          width: parent.width
          visible: page.taskRows.length === 0
          textFormat: Text.PlainText
          text: page.dashNarrowed ? "nothing matches  ·  " + page.keyName("dashAll") + " shows all" : "nothing open"
          color: page.faint
          font.family: page.fontFamily
          font.styleName: page.fontStyle
          font.pixelSize: page.fs(Style.font.bodySmall)
        }

        // Drawn from the page's keyed model (Page.syncDash, 2026-11-13): a
        // row the words leave out is hidden, not thrown away, so typing
        // into ⌕ never draws the list anew. `index` is the row's place in
        // page.taskRows, -1 while hidden.
        Repeater {
          model: page.dashModel
          Rectangle {
            id: dashRow
            required property string rowId
            readonly property var entry: page.dashEntries[rowId] || null
            readonly property int index: entry ? entry.i : -1
            property var lastRow: null
            readonly property var modelData: entry ? entry.row : (lastRow || ({ kind: "" }))
            onEntryChanged: if (entry) lastRow = entry.row
            visible: entry !== null
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
            // Which row has the cursor goes by its key, not its place: a
            // row moved up by the words is not worked out again for it.
            readonly property bool focusHere: page.dashFocusId === rowId
            readonly property bool hot: focusHere && !isHead && page.here === "center" && page.stripAt < 0
            onHotChanged: page.selected(dashRow, "center", hot)
            Component.onCompleted: if (hot) page.selected(dashRow, "center", true)
            // A click on it does something (activateTask): a hand, and a
            // faint fill while the mouse is over it (2026-10-19).
            readonly property bool acts: ["task", "deadline", "shelf", "grading", "raised", "proposal", "question", "told"].indexOf(kind) >= 0
                                         || (kind === "band" && modelData.count > 0 && !modelData.fixed)
            // Its chat, in brief: the gutter bar's state and the last thing
            // said, on every row that has one (page.chatState).
            readonly property var chat: page.chatOf(modelData)
            readonly property string chatState: page.chatState(modelData)
            // A chat can be opened on it: nothing on a private box, which
            // offers nothing of the agent's.
            readonly property bool chatCan: (kind === "task" || kind === "deadline" || asks)
              && !(line && line.private)
            // The bar's colour, which its key shares: the accent while a
            // reply waits, dim once read, and for a row not talked about yet
            // a faint one, opaque so the bar and the key that grows from it
            // never show where they overlap.
            readonly property color chatTone: chatState === "unread" ? page.accent : chatState !== "" ? page.dim
              : Qt.tint(page.background, Qt.rgba(page.dim.r, page.dim.g, page.dim.b, 0.55))
            HoverHandler { id: rowHover; enabled: dashRow.acts }
            width: dashColumn.width
            // The space above a row comes from what it is and what came
            // before it, the way the note's own rhythm works (Rows.js).
            height: inner.implicitHeight + page.sp(16)
              + (kind === "head" ? page.sp(30) : kind === "month" ? page.sp(16)
                 // A run of folded bands reads as one list of headings.
                 : kind === "band" ? (entry && entry.afterBand ? page.sp(10) : page.sp(30)) : 0)
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
                : rowHover.hovered && page.handOn || (dashRow.focusHere && !isHead && page.talkOpen) ? Style.hoverFill : "transparent"
            }

            // The gutter bar, as the note draws one beside a block: the
            // accent while a reply waits unread, dim once read, a light
            // travelling down it while the agent answers; for a box never
            // talked about, only a faint one while its chat key shows, so
            // the key always grows from a bar. As tall as the row's fill,
            // and cornered as the shell is (Style.cornerRadius, Hyprland's
            // rounding; square by default). At the fill's left edge, so on
            // a row set in under the box it is about (the agent's) it moves
            // in with the fill, leaving no gap between them.
            Item {
              id: chatBar
              visible: dashRow.chatState !== "" || chatKey.visible
              x: inner.x - page.sp(9)
              y: inner.y - page.sp(7)
              width: page.sp(3)
              height: inner.height + page.sp(13)
              clip: true
              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: dashRow.chatTone
                opacity: dashRow.chatState === "thinking" ? 0.3 : 1
                Behavior on color { ColorAnimation { duration: 240 } }
                Behavior on opacity { NumberAnimation { duration: 240 } }
              }
              Rectangle {
                id: chatSpark
                width: parent.width
                height: Math.max(page.sp(12), parent.height * 0.5)
                radius: Style.cornerRadius
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

            // The chat key, grown from the gutter bar as a tab (2026-11-13,
            // A of the bar-grows studies): on the row the keys are on and the
            // one under the mouse, beside the box, in the bar's colour, its
            // letter centred by its ink rather than its line. Outside the
            // row, so selecting a row moves nothing in it or around it: no
            // row's size or place ever depends on which row is selected
            // (docs/navigation.md).
            Rectangle {
              id: chatKey
              visible: dashRow.chatCan && (dashRow.hot || rowHover.hovered && page.handOn || chatKeyArea.containsMouse)
              x: chatBar.x + chatBar.width - width   // its right edge is the bar's
              y: inner.y + box.y + Math.round((box.size - height) / 2)
              height: box.size + page.sp(6)
              width: Math.max(height, Math.ceil(chatKeyInk.tightBoundingRect.width) + page.sp(10)) + page.sp(3)
              radius: Style.cornerRadius
              color: dashRow.chatTone
              TextMetrics {
                id: chatKeyInk
                font: chatKeyText.font
                text: chatKeyText.text
              }
              Text {
                id: chatKeyText
                // Centred in the part of the tab left of the bar it grows from.
                x: Math.round((parent.width - page.sp(3)) / 2 - chatKeyInk.tightBoundingRect.x - chatKeyInk.tightBoundingRect.width / 2)
                y: Math.round(parent.height / 2 - baselineOffset - chatKeyInk.tightBoundingRect.y - chatKeyInk.tightBoundingRect.height / 2)
                textFormat: Text.PlainText
                text: page.keyName("dashTalk")
                color: page.background
                font.family: page.fontFamily
                font.styleName: page.fontStyle
                font.pixelSize: page.fs(Style.font.caption)
                font.bold: true
              }
              MouseArea {
                id: chatKeyArea
                anchors.fill: parent
                anchors.margins: -page.sp(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { page.taskFocus = dashRow.index; page.talkFocused() }
                Tip { host: page; shown: parent.containsMouse; text: page.tip("Chat about it", "dashTalk") }
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

              // A band of the timeline (by date): ▾ open, ▸ folded, then
              // how much it holds; folded, what comes first in it.
              Row {
                id: bandRow
                visible: dashRow.kind === "band"
                anchors.left: parent.left
                anchors.right: parent.right
                y: 0
                spacing: page.sp(8)
                readonly property bool empty: dashRow.kind === "band" && modelData.count === 0
                // Drawn, not typed: the font's ▸ and ▾ came out a few
                // pixels wide, too small to read as arrows (2026-11-14).
                // As tall as the band's capitals, standing on its baseline;
                // ▸ folded, turned a quarter to ▾ open.
                Item {
                  id: bandMark
                  width: Math.round(page.fs(Style.font.body) * 0.72)
                  height: width
                  baselineOffset: height
                  anchors.baseline: bandName.baseline
                  Shape {
                    id: bandArrow
                    anchors.fill: parent
                    visible: dashRow.kind === "band" && !modelData.fixed && !bandRow.empty
                    rotation: dashRow.kind === "band" && modelData.open ? 90 : 0
                    layer.enabled: true
                    layer.samples: 8
                    readonly property real s: width
                    ShapePath {
                      strokeColor: "transparent"
                      fillColor: page.faint
                      startX: bandArrow.s * 0.2; startY: bandArrow.s * 0.08
                      PathLine { x: bandArrow.s * 0.88; y: bandArrow.s * 0.5 }
                      PathLine { x: bandArrow.s * 0.2; y: bandArrow.s * 0.92 }
                      PathLine { x: bandArrow.s * 0.2; y: bandArrow.s * 0.08 }
                    }
                  }
                }
                Text {
                  id: bandName
                  textFormat: Text.PlainText
                  text: dashRow.kind === "band" ? modelData.text : ""
                  color: bandRow.empty ? page.faint
                    : dashRow.kind === "band" && modelData.fixed ? page.urgent
                    : pal.headings.length > 0 ? pal.headings[0] : page.accent
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.body)
                }
                Text {
                  id: bandCount
                  anchors.baseline: bandName.baseline
                  textFormat: Text.PlainText
                  text: dashRow.kind !== "band" ? "" : bandRow.empty ? "nothing due" : String(modelData.count)
                  color: page.faint
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                }
                Text {
                  anchors.baseline: bandName.baseline
                  width: Math.max(0, bandRow.width - bandMark.width - bandName.implicitWidth - bandCount.implicitWidth - 3 * bandRow.spacing)
                  visible: dashRow.kind === "band" && !modelData.open && !!modelData.next
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: !visible ? "" : "next: " + modelData.next.title + ",  " + Qt.formatDate(new Date(modelData.next.ms), "ddd d MMM")
                  color: page.dim
                  font.family: page.fontFamily
                  font.styleName: page.fontStyle
                  font.pixelSize: page.fs(Style.font.caption)
                }
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
                radius: Math.max(2, Math.round(Style.cornerRadius / 2))
                color: dashRow.done && dashRow.author === "" ? pal.green : "transparent"
                border.width: dashRow.done || dashRow.author !== "" ? 0 : Math.max(1, Math.round(page.textSize * 0.08))
                readonly property color edge: boxArea.containsMouse && page.handOn ? page.accent : dashRow.late ? page.urgent : page.dim
                border.color: edge

                // The agent's: a diamond. Made together: the seal.
                Rectangle {
                  visible: dashRow.author === "agent"
                  anchors.centerIn: parent
                  width: Math.round(box.size * 0.74)
                  height: width
                  rotation: 45
                  radius: Math.max(1, Math.round(Style.cornerRadius / 2))
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
                  Tip { host: page; shown: parent.containsMouse; text: page.tip("Done (again: not done)", "dashDone") }
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
                text: Say.taskMark(dashRow.line)
                color: dashRow.line && dashRow.line.priority >= 1 ? page.accent : page.faint
                font.family: page.fontFamily
                font.pixelSize: page.fs(Style.font.caption)
              }

              Row {
                id: pills
                anchors.right: parent.right
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
                    radius: Style.cornerRadius
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

              // Ctrl held on the row the keys are on (docs/hints.md, F):
              // done on its box, rename by its words, when by its day.
              KeyBadge {
                host: page
                act: "dashDone"
                place: dashRow.hot && dashRow.boxed
                anchors.bottom: box.top
                anchors.bottomMargin: page.sp(3)
                anchors.horizontalCenter: box.horizontalCenter
              }
              KeyBadge {
                host: page
                act: "dashRename"
                words: "rename"
                place: dashRow.hot && dashRow.kind === "task"
                x: Math.min(texts.x + titleText.contentWidth + page.sp(10), pills.x - width - page.sp(10))
                y: texts.y + Math.round((titleText.font.pixelSize * 1.3 - height) / 2)
              }
              KeyBadge {
                host: page
                act: "dashWhen"
                words: "when"
                place: dashRow.hot && (dashRow.kind === "task" || dashRow.kind === "deadline")
                anchors.top: pills.bottom
                anchors.topMargin: page.sp(4)
                anchors.right: pills.right
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
                  text: dashRow.kind === "proposal" || dashRow.kind === "told" ? Say.sayAsk(modelData.item, !!modelData.task)
                    : dashRow.kind === "question" ? modelData.item.question
                    : dashRow.kind === "shelf" ? "+" + modelData.count + " set aside · " + page.keyName("dashOpen") + " to show"
                    : dashRow.kind === "grading" ? "+" + modelData.count + " waiting for a grade · " + page.keyName("dashOpen") + " to show"
                    : dashRow.kind === "raised"
                      ? (modelData.item.kind === "suggestion" ? "◇ " : "· ") + modelData.item.text
                    : dashRow.kind === "deadline" ? modelData.deadline.title
                    : dashRow.kind === "task" ? Say.taskTitle(modelData.task)
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
                  visible: freshMark.visible || cardMark.visible || caption.text !== ""
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

                  // A card its chat made that waits for the person
                  // (2026-11-03): said on the row, so a proposal is never
                  // only in a conversation nobody opens.
                  Text {
                    id: cardMark
                    visible: !!dashRow.chat && dashRow.chat.cards > 0
                    textFormat: Text.PlainText
                    text: visible ? "◇ " + (dashRow.chat.cards === 1 ? "a card" : dashRow.chat.cards + " cards")
                      + " in its chat · " + page.keyName("dashTalk") : ""
                    color: page.accent
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.caption)
                  }

                  Text {
                    id: caption
                    width: parent.width - (freshMark.visible ? freshMark.implicitWidth + parent.spacing : 0)
                      - (cardMark.visible ? cardMark.implicitWidth + parent.spacing : 0)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: dashRow.kind === "proposal" || dashRow.kind === "told" ? (modelData.item.why || "")
                      : dashRow.kind === "question" ? "recommended: " + modelData.item.recommended
                      : dashRow.kind === "task" ? Say.taskWhere(modelData.task, modelData.under, page.projects)
                      : dashRow.kind === "deadline" ? page.deadlineWhere(modelData.deadline)
                      : dashRow.kind === "raised" ? (modelData.item.evidence || "")
                      : ""
                    color: page.faint
                    font.family: page.fontFamily
                    font.styleName: page.fontStyle
                    font.pixelSize: page.fs(Style.font.caption)
                  }
                }

                // Where its chat left off, on every row that has one, never
                // only the selected one (2026-11-13): the agent's last word
                // (◇, as its marks are), or yours. One line, so a long or
                // many-lined turn never makes the row taller.
                Text {
                  visible: !!dashRow.chat
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  maximumLineCount: 1
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
              Tip {
                host: page
                readonly property string kind: dashRow.modelData.kind
                shown: parent.containsMouse && (kind === "task" || kind === "deadline" || kind === "shelf" || kind === "grading" || kind === "raised"
                                                  || kind === "proposal" || kind === "question" || kind === "told" || (kind === "band" && dashRow.acts))
                // The four a row is most used for, then the sheet for the rest
                // (2026-10-30, the canvas's keycaps: ten lines hid the list).
                text: kind === "task" ? page.tips([["Go to the line", "dashOpen"], ["Done", "dashDone"], ["Reschedule", "dashWhen"]]
                                                  .concat(dashRow.chatCan ? [["Chat about it", "dashTalk"]] : []).concat([["—"], ["Every key here", "keysHere"]]))
                  : kind === "deadline" ? page.tips([["Go to its line", "dashOpen"], ["Done", "dashDone"], ["The day to work on it", "dashWhen"]]
                                                   .concat(dashRow.chatCan ? [["Chat about it", "dashTalk"]] : []).concat([["—"], ["Every key here", "keysHere"]]))
                  : kind === "told" ? page.tips([["Let it stand", "dashDone"], ["Undo it", "dashDrop"], ["Chat about it", "dashOpen"]])
                  : kind === "proposal" && dashRow.modelData.item.kind === "file"
                    ? page.tips([["File it: moved from Downloads into the course's documents", "dashDone"], ["Decline", "dashDrop"], ["Open it first", "dashOpen"]])
                  : kind === "proposal" ? page.tips([["Accept", "dashDone"], ["Decline", "dashDrop"], ["Chat about it", "dashOpen"]])
                  : kind === "question" ? page.tips([["Accept the recommended answer", "dashDone"], ["Chat about it: answer in your words, or ask back", "dashOpen"], ["Decline", "dashDrop"]])
                  : kind === "shelf" ? page.tip("Show what is set aside", "dashOpen")
                  : kind === "grading" ? page.tip("Show what waits for a grade", "dashOpen")
                  : kind === "band" ? page.tips([[dashRow.modelData.open ? "Fold it" : "Open it", "dashOpen"], ["Collapse every band", "dashFoldAll"],
                                                 ["Expand every band", "dashUnfoldAll"]])
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
        visible: !page.dashWhenFor && !page.ctrlShown   // Ctrl held: its strip says it
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: page.stripOpen
          ? page.keyName("stripUp") + page.keyName("stripDown") + " move · " + page.keyName("stripAdd") + " add a course · "
            + page.keyName("stripUnfold") + " only this one · " + page.keyName("dashCourse") + "… a course · typing searches · "
            + page.keyName("stripClear") + " fold"
          : page.stripAt === 0
          ? "type words, or a #tag · " + page.keyName("stripNext") + " the courses · " + page.keyName("stripDown") + " the list · "
            + page.keyName("stripClear") + " clear"
          : page.stripAt > 0
          ? page.keyName("stripPrev") + page.keyName("stripNext") + (page.stripPinned ? " move · " + page.keyName("stripAdd") + " adds or takes out · "
                                                                                    : " pick (shown at once) · " + page.keyName("stripAdd") + " keep it, to add another · ")
            + page.keyName("stripUnfold") + " unfold · " + page.keyName("stripDown") + " the list · " + page.keyName("dashOrder") + " order · "
            + page.keyName("stripClear") + " clear"
          : page.keyName("dashUp") + page.keyName("dashDown") + " move · "
          + (page.dashOrder === "date" ? page.keyName("dashFold") + page.keyName("dashUnfold") + " fold · " : "")
          + page.keyName("dashOpen") + " opens the line · "
          + page.keyName("dashTalk") + " chat · "
          + page.keyName("dashDone") + " done · " + page.keyName("dashWhen") + " when · " + page.keyName("dashPriority") + " priority · "
          + page.keyName("dashShelve") + " set aside · " + page.keyName("dashKeep") + " renew · " + page.keyName("dashGrade") + " grade · "
          + page.keyName("dashPlan") + " plan now · "
          + page.keyName("dashSearch") + " search · " + page.keyName("dashCourse") + "… a course · " + page.keyName("dashOrder") + " order · "
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
            : "when · " + Say.taskTitle(page.dashWhenFor)
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
