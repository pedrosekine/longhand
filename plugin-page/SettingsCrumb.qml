import QtQuick
import qs.Commons
import qs.Ui

// The top line of Settings' four other sheets: "SETTINGS · WHAT IT KNOWS",
// its first word the way back for the mouse, as Esc is for the keys
// (2026-11-28, the settings pass: a mouse had no way back but to close
// Settings).
Row {
  id: crumb
  required property Item page
  required property string title
  property string backTo: "SETTINGS"          // where its first word goes back to
  signal back()                               // each sheet says where: Settings, or the dashboard
  spacing: 0

  Text {
    textFormat: Text.PlainText
    text: "‹ " + crumb.backTo
    color: backArea.containsMouse && crumb.page.handOn ? crumb.page.accent : crumb.page.dim
    font.family: crumb.page.fontFamily
    font.styleName: crumb.page.fontStyle
    font.pixelSize: crumb.page.fs(Style.font.caption)
    MouseArea {
      id: backArea
      anchors.fill: parent
      anchors.margins: -crumb.page.sp(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: crumb.back()
      Tip { host: crumb.page; shown: parent.containsMouse; text: "Back to " + (crumb.backTo === "SETTINGS" ? "Settings" : "the dashboard") + "   Esc" }
    }
  }
  Text {
    textFormat: Text.PlainText
    text: crumb.title === "" ? "" : " · " + crumb.title
    color: crumb.page.dim
    font.family: crumb.page.fontFamily
    font.styleName: crumb.page.fontStyle
    font.pixelSize: crumb.page.fs(Style.font.caption)
  }
}
