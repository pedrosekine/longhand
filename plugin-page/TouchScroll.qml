import QtQuick

// Touchpad scrolling for a Flickable, as the rest of the desktop does it.
//
// Qt's Flickable moves the content exactly as far as the fingers report and
// stops dead when they lift. Browsers, GTK and Electron apps scroll a little
// further per finger movement and keep gliding after the lift, so the page
// felt slow beside them (Omarchy also scales all touchpad scrolling by
// 0.4). This takes over the touchpad's two-finger scroll: `gain` times the
// travel while the fingers move, then a glide that slows down (the
// Flickable's own flick) from the speed they had when they lifted. A mouse
// wheel is left to the Flickable.
//
// Put it inside the Flickable, over the content; it takes no clicks.
MouseArea {
  id: ts
  required property Flickable flickable
  property real gain: 2.0
  // Recent finger travel: [{ t, dy }] from the last `window` ms.
  property var samples: []
  readonly property int window: 90

  width: flickable.contentWidth
  height: flickable.contentHeight
  z: 100
  acceptedButtons: Qt.NoButton

  onWheel: function (wheel) {
    if (wheel.pixelDelta.y === 0 && wheel.phase === Qt.NoScrollPhase) { wheel.accepted = false; return }
    var now = Date.now()
    if (wheel.phase === Qt.ScrollBegin) ts.begin()
    else if (wheel.phase === Qt.ScrollEnd) ts.end(now)
    else ts.move(wheel.pixelDelta.y, now)
  }

  function begin() {
    ts.flickable.cancelFlick()
    ts.samples = []
  }

  function move(dy, now) {
    if (dy === 0) return
    var f = ts.flickable
    if (f.flicking) f.cancelFlick()
    var top = f.originY
    var bottom = Math.max(top, f.originY + f.contentHeight - f.height)
    f.contentY = Math.max(top, Math.min(bottom, f.contentY - dy * ts.gain))
    var keep = ts.samples.filter(function (s) { return now - s.t <= ts.window })
    keep.push({ t: now, dy: dy * ts.gain })
    ts.samples = keep
  }

  // The fingers lifted: glide on at the speed they had, if they were still
  // moving just before (resting them first means stop).
  function end(now) {
    var recent = ts.samples.filter(function (s) { return now - s.t <= ts.window })
    ts.samples = []
    if (recent.length < 2) return
    var span = Math.max(16, now - recent[0].t)
    var travel = 0
    for (var i = 0; i < recent.length; i++) travel += recent[i].dy
    var velocity = travel / span * 1000
    if (Math.abs(velocity) > 120) ts.flickable.flick(0, velocity)
  }
}
