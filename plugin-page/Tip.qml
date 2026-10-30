import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A hover's hint (docs/hints.md). Shown only while the hand is on the
// mouse (the page's `handOn`, 2026-10-30), and warm: the first waits, and
// while one is open, or just after, the next opens at once, so a row of
// words read with the mouse is one strip, not a wait at each.
//
// Drawn as keycaps (2026-10-30, the canvas's direction 1): on the darker
// paper with a faint edge, what it does on the left and its key on the
// right, each part of the key a cap. The text is the page's `tip()` /
// `tips()`, read back: a line is "words   key" (three spaces), words
// after ": " go under the first in the faint ink, and a line "—" is a rule.
PanelToolTip {
  id: tip
  required property Item host   // the page
  property bool shown: false    // the mouse is on its thing
  property string act: ""       // what a click on it does, as a key would (C)
  visible: shown && host.handOn
  delay: host.tipWarm ? 0 : 500
  onOpened: host.tipOpened()
  onClosed: host.tipClosed()
  Component.onDestruction: if (tip.opened) host.tipClosed()

  readonly property color edge: Qt.rgba(host.foreground.r, host.foreground.g, host.foreground.b, 0.16)
  readonly property int size: host.fs(Style.font.bodySmall)
  // Each line as cells for the grid: the words, then the key's caps.
  readonly property var cells: {
    var out = []
    tip.text.split("\n").forEach(function (line) {
      if (line === "—") { out.push({ kind: "rule" }); return }
      var parts = line.split(/ {3,}/)
      var words = parts[0], c = words.indexOf(": ")
      var key = parts.length > 1 ? parts.slice(1).join(" ") : ""
      out.push({ kind: "words", words: c > 0 ? words.substring(0, c) : words, more: c > 0 ? words.substring(c + 2) : "" })
      // "no key (… gives it one)" is words, not a key.
      out.push(key.indexOf("no key") === 0 ? { kind: "words", words: "", more: key }
               : { kind: "key", caps: key === "" ? [] : key.split(/\+(?=.)/) })
    })
    return out
  }

  padding: host.sp(9)
  background: Rectangle {
    color: tip.host.sunk
    border.width: 1
    border.color: tip.edge
  }
  contentItem: GridLayout {
    columns: 2
    columnSpacing: tip.host.sp(18)
    rowSpacing: tip.host.sp(6)
    Repeater {
      model: tip.cells
      Loader {
        required property var modelData
        Layout.alignment: modelData.kind === "key" ? Qt.AlignRight | Qt.AlignTop : Qt.AlignLeft | Qt.AlignTop
        Layout.columnSpan: modelData.kind === "rule" ? 2 : 1
        Layout.fillWidth: modelData.kind === "rule"
        sourceComponent: modelData.kind === "rule" ? rule : modelData.kind === "key" ? caps : words
        property var cell: modelData
      }
    }
  }

  Component {
    id: words
    Column {
      spacing: tip.host.sp(1)
      Text {
        visible: text !== ""
        textFormat: Text.PlainText
        text: parent.parent.cell.words
        color: tip.host.foreground
        font.family: tip.host.fontFamily
        font.styleName: tip.host.fontStyle
        font.pixelSize: tip.size
      }
      Text {
        visible: text !== ""
        textFormat: Text.PlainText
        text: parent.parent.cell.more
        color: tip.host.faint
        font.family: tip.host.fontFamily
        font.styleName: tip.host.fontStyle
        font.pixelSize: tip.size
      }
    }
  }

  Component {
    id: caps
    Row {
      spacing: tip.host.sp(3)
      Repeater {
        model: parent.parent.cell.caps
        Rectangle {
          required property string modelData
          width: Math.max(capText.implicitWidth + tip.host.sp(10), height)
          height: capText.implicitHeight + tip.host.sp(3)
          radius: tip.host.sp(3)
          color: tip.host.sheetColor
          border.width: 1
          border.color: tip.edge
          // The cap's lip: a second edge along its foot.
          Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 1; height: 1; color: tip.edge }
          Text {
            id: capText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: parent.modelData
            color: tip.host.dim
            font.family: tip.host.fontFamily
            font.styleName: tip.host.fontStyle
            font.pixelSize: Math.round(tip.size * 0.9)
          }
        }
      }
    }
  }

  Component {
    id: rule
    Rectangle { implicitHeight: 1; color: tip.edge }
  }

  // A plain click on its thing: the page may name the key that does the
  // same (docs/hints.md, C). A Ctrl- or Shift-click is another action.
  Connections {
    target: tip.act !== "" ? tip.parent : null
    ignoreUnknownSignals: true
    function onClicked(mouse) {
      if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) tip.host.mouseDid(tip.act)
    }
  }
}
