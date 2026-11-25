pragma Singleton
import QtQuick
import qs.Commons as Commons

// omarchy-shell's Style, as far as the page reads it, with Windows 11's own
// answers: its corner radius, its monospace as the shell's face, and Qt's
// device-pixel scaling in place of the shell's spacing scale.
QtObject {
  id: root

  // Windows 11's two radii (Fluent's ControlCornerRadius and
  // OverlayCornerRadius): 4 for what sits in a surface — buttons, fields,
  // chips, key caps, a row's fill, the gutter bar — and 8 for what floats
  // over the others, as its windows and flyouts do. On Omarchy one radius,
  // Hyprland's rounding, does both; 8 for both here made a 20 px tab a
  // circle and a checkbox a ring.
  readonly property int cornerRadius: 4
  readonly property int overlayRadius: 8
  readonly property real effectiveSpacingScale: 1.0
  readonly property bool reduceMotion: false

  readonly property var families: Qt.fontFamilies()
  // The shell's face is a monospace on Omarchy, and the page keeps it for
  // code: Windows 11 ships Cascadia Mono, every Windows has Consolas.
  readonly property string fontFamily: families.indexOf("Cascadia Mono") >= 0 ? "Cascadia Mono" : "Consolas"
  readonly property int fontBaseSize: 12

  readonly property int normalBorderWidth: 1
  readonly property int hoverBorderWidth: 1
  readonly property int selectedBorderWidth: 0
  readonly property int focusBorderWidth: 1

  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.08
  readonly property real selectedFillAlpha: 0.18
  readonly property real pressedFillAlpha: 0.22
  readonly property real focusFillAlpha: 0.08

  function normalFillFor(foreground, accent, urgent) { return Commons.Util.alpha(foreground || Commons.Color.foreground, normalFillAlpha) }
  function hoverFillFor(foreground, accent, urgent) { return Commons.Util.alpha(foreground || Commons.Color.foreground, hoverFillAlpha) }
  function selectedFillFor(foreground, accent, urgent) { return Commons.Util.alpha(foreground || Commons.Color.foreground, selectedFillAlpha) }
  function pressedFillFor(foreground, accent, urgent) { return Commons.Util.alpha(foreground || Commons.Color.foreground, pressedFillAlpha) }
  function focusFillFor(foreground, accent, urgent) { return Commons.Util.alpha(foreground || Commons.Color.foreground, focusFillAlpha) }

  function selectionFillFor(foreground, accent, urgent) { return Commons.Util.alpha(foreground || Commons.Color.foreground, 0.35) }

  // `a` taken a fraction `t` of the way to `b`: quiet text is the foreground
  // moved toward its ground, which quiets it on a dark ground and a light one
  // alike (Qt.darker only quiets it on a dark one).
  function mix(a, b, t) {
    if (typeof a === "string") a = Qt.color(a)
    if (typeof b === "string") b = Qt.color(b)
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  function controlFill(focused, hot, foreground, accent) {
    if (focused) return focusFillFor(foreground, accent)
    if (hot) return hoverFillFor(foreground, accent)
    return normalFillFor(foreground, accent)
  }

  readonly property color hoverFill: hoverFillFor(Commons.Color.foreground)
  readonly property color selectedFill: selectedFillFor(Commons.Color.foreground)
  readonly property color pressedFill: pressedFillFor(Commons.Color.foreground)

  function spaceReal(px) {
    var n = Number(px)
    if (!isFinite(n) || n <= 0) return 0
    return n * effectiveSpacingScale
  }

  function space(px) {
    var n = spaceReal(px)
    if (n <= 0) return 0
    return Math.max(1, Math.round(n))
  }

  function duration(ms) { return reduceMotion ? 0 : ms }

  function fontPx(mult) { return Math.max(1, Math.round(fontBaseSize * mult)) }

  readonly property QtObject spacing: QtObject {
    readonly property real scale: root.effectiveSpacingScale
    readonly property int hairline: root.space(1)
    readonly property int xxs: root.space(2)
    readonly property int xs: root.space(4)
    readonly property int sm: root.space(6)
    readonly property int md: root.space(8)
    readonly property int lg: root.space(12)
    readonly property int xl: root.space(16)
    readonly property int controlPaddingX: root.space(10)
    readonly property int controlPaddingY: root.space(6)
    readonly property int inputPaddingY: root.space(7)
    readonly property int controlHeight: root.space(28)
    readonly property int popupPadding: root.space(14)
  }

  // Hyprland's gap around a window, as the shell keeps it: here only the
  // room a popup leaves to the screen's edge.
  readonly property int gapsOut: 5

  readonly property QtObject font: QtObject {
    readonly property string family: root.fontFamily
    readonly property string resolvedFamily: root.fontFamily
    readonly property string menuFamily: root.fontFamily
    readonly property int baseSize: root.fontBaseSize
    readonly property int caption: root.fontPx(0.833)
    readonly property int bodySmall: root.fontPx(0.917)
    readonly property int body: root.fontPx(1.0)
    readonly property int subtitle: root.fontPx(1.083)
    readonly property int title: root.fontPx(1.167)
    readonly property int heading: root.fontPx(1.333)
    readonly property int display: root.fontPx(2.0)
    readonly property int displayLarge: root.fontPx(2.333)
    readonly property int icon: root.fontPx(1.167)
  }

  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: 26
    readonly property int sizeVertical: 28
    readonly property int iconSlot: 27
  }
}
