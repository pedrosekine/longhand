import QtQuick

// A small lock, drawn (docs/files.md, "How private looks", B · Paper,
// 2026-10-27): what stands in the gutter beside a private block and in the
// header of a private day. The gutter is the agent's lane — its marks for
// answers are there — so a lock there reads as "the agent stops here".
Item {
  id: lock
  property color color: "white"
  property real stroke: Math.max(1, Math.round(width * 0.13))
  width: 10
  height: Math.round(width * 1.2)

  // The shackle: the top half of a ring.
  Item {
    x: Math.round(lock.width * 0.2)
    width: lock.width - 2 * x
    height: Math.round(lock.height * 0.5)
    clip: true
    Rectangle {
      width: parent.width
      height: parent.width * 1.4
      radius: width / 2
      color: "transparent"
      border.width: lock.stroke
      border.color: lock.color
    }
  }
  // The body.
  Rectangle {
    y: Math.round(lock.height * 0.45)
    width: lock.width
    height: lock.height - y
    radius: Math.max(1, Math.round(lock.width * 0.15))
    color: "transparent"
    border.width: lock.stroke
    border.color: lock.color
  }
}
