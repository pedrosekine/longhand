import QtQuick
import qs.Commons

// A key drawn as the hover hints draw it (Tip.qml, 2026-10-30): each part a
// cap on the sheet's paper, a faint edge and a lip along its foot. `key` is
// as Shortcuts.js names it ("Ctrl+R"), read live by the caller
// (page.keyName), so a moved key is the one shown; `parts`, where the
// caller has it split already (Tip.qml).
Row {
  id: caps
  required property Item page
  property string key: ""
  property var parts: caps.key === "" ? [] : caps.key.split(/\+(?=.)/)
  property int size: page.fs(Style.font.bodySmall)
  readonly property color edge: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.16)
  spacing: page.sp(3)

  // The capitals of the cap's face, measured: what is centred on a cap.
  TextMetrics {
    id: capital
    font.family: caps.page.fontFamily
    font.styleName: caps.page.fontStyle
    font.pixelSize: Math.round(caps.size * 0.9)
    text: "H"
  }

  Repeater {
    model: caps.parts
    Rectangle {
      id: cap
      required property string modelData
      width: Math.max(capText.implicitWidth + caps.page.sp(10), height)
      height: capText.implicitHeight + caps.page.sp(3)
      // A key's corners, not a pill's: a shell's radius (Windows 11's is 8)
      // on a cap this short made it a pill, and the lip ran past its ends.
      radius: Math.min(Style.cornerRadius, Math.round(height / 3))
      color: caps.page.sheetColor
      border.width: 1
      border.color: caps.edge
      // The lip: a second edge along the foot, one pixel above it, ending
      // where the rounded corners bend away from that line.
      Rectangle {
        readonly property real bend: cap.radius > 2 ? cap.radius - Math.sqrt(cap.radius * cap.radius - (cap.radius - 2) * (cap.radius - 2)) : 0
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: 1
        anchors.leftMargin: Math.ceil(bend) + 1
        anchors.rightMargin: Math.ceil(bend) + 1
        height: 1
        color: caps.edge
      }
      Text {
        id: capText
        // The capitals centred between the top edge and the lip, not the
        // line they sit on: a face keeps room above its capitals for
        // accents, a third of the size in Segoe UI and almost none in
        // Inter, and centring the line put Segoe's letters on the lip.
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((cap.height - 1) / 2 - capText.baselineOffset
                      - capital.tightBoundingRect.y - capital.tightBoundingRect.height / 2)
        textFormat: Text.PlainText
        text: cap.modelData
        color: caps.page.dim
        font: capital.font
      }
    }
  }
}
