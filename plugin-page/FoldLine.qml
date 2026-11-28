import QtQuick
import qs.Commons

// A folded line of the pane's "everything" (docs/agent.md, "One
// conversation", slice 2, 2026-11-18): an earlier day, or a place that was
// talked in (a task's chat, a paper's), with how much was said there and
// its last words. A click, or Enter with the keys on it, unfolds a day or
// opens what the line is about.
Rectangle {
  id: fold
  required property Item page
  property string rowKey: ""
  property string head: ""
  property string tail: ""
  property bool day: false
  property bool unfolded: false
  property int indent: 0
  property Flickable flick: null       // the pane's, scrolled to show it when the keys come to it
  readonly property bool lit: rowKey !== "" && page.dayFoldKey === rowKey
  onLitChanged: { page.selected(fold, "right", lit); if (lit) Qt.callLater(function () { page.revealIn(fold.flick, fold) }) }
  signal act()

  height: headText.implicitHeight + page.sp(6)
  radius: Style.cornerRadius
  color: lit ? Style.selectedFill : area.containsMouse && page.handOn ? Style.hoverFill : "transparent"

  Text {
    id: headText
    anchors.left: parent.left
    anchors.leftMargin: page.sp(4) + fold.indent
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width - anchors.leftMargin - page.sp(4))
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: (fold.day && fold.unfolded ? "▾ " : "▸ ") + fold.head
    color: fold.lit || (area.containsMouse && page.handOn) ? page.foreground : page.dim
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
  Text {
    anchors.left: headText.right
    anchors.leftMargin: page.sp(10)
    anchors.right: parent.right
    anchors.rightMargin: page.sp(4)
    anchors.verticalCenter: parent.verticalCenter
    visible: fold.tail !== "" && width > page.sp(40)
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: fold.tail
    color: page.faint
    font.family: page.fontFamily
    font.styleName: page.fontStyle
    font.pixelSize: page.fs(Style.font.caption)
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: fold.act()
  }
}
