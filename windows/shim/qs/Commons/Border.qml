pragma Singleton
import QtQuick
import qs.Commons as Commons

// Border specs under omarchy-shell's names, without its theme file behind
// them: a colour, four widths, and a gradient when a caller hands one in.
QtObject {
  id: root

  function widths(w) {
    var n = Math.max(0, Number(w) || 0)
    return { top: n, right: n, bottom: n, left: n }
  }

  function none() { return flat("transparent", 0) }

  function flat(color, width) {
    return { color: color || "transparent", widths: widths(width), gradient: { colors: [], angle: 0, enabled: false } }
  }

  function cssColor(color, opacity) {
    var a = opacity === undefined || opacity === null ? 1 : Commons.Util.clampAlpha(opacity)
    if (color && typeof color === "object" && color.r !== undefined)
      return Qt.rgba(color.r, color.g, color.b, (color.a === undefined ? 1 : color.a) * a)
    var s = String(color || "").trim()
    if (s === "" || s === "transparent") return "transparent"
    var c = Qt.color(s)
    return Qt.rgba(c.r, c.g, c.b, c.a * a)
  }

  // "#D6C24A #EC9E3E 45deg": colours and an angle, as a theme writes them.
  function resolvedGradient(raw, fallbackColor, opacity) {
    var s = String(raw || "").trim()
    if (s.length === 0) return { colors: [], angle: 0, enabled: false }
    var parts = s.split(/\s+/), colors = [], angle = 0
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) angle = Number(parts[i].replace(/deg$/, ""))
      else colors.push(cssColor(parts[i], opacity))
    }
    if (colors.length === 0) colors.push(cssColor(fallbackColor, opacity))
    return { colors: colors, angle: angle, enabled: colors.length > 1 }
  }

  function surfaceSpec(section, token, fallbackColor, fallbackWidth, alphaKey) {
    return flat(fallbackColor, fallbackWidth)
  }

  function localOrSurfaceSpec(section, token, localColor, defaultColor, fallbackWidth, alphaKey) {
    return flat(localColor, fallbackWidth)
  }

  function controlSpec(state, foreground, accent, urgent) {
    var fg = foreground || Commons.Color.foreground
    if (state === "focus") return flat(Commons.Util.alpha(accent || Commons.Color.accent, 0.9), Commons.Style.focusBorderWidth)
    if (state === "hover" || state === "hot") return flat(Commons.Util.alpha(fg, 0.25), Commons.Style.hoverBorderWidth)
    if (state === "selected") return flat(fg, 0)
    return flat(Commons.Util.alpha(fg, 0.2), Commons.Style.normalBorderWidth)
  }

  function withWidth(spec, width) {
    if (!spec) return flat("transparent", 0)
    return { color: spec.color, gradient: spec.gradient, widths: widths(width) }
  }

  function maxWidth(spec) {
    if (!spec || !spec.widths) return 0
    return Math.max(spec.widths.top, spec.widths.right, spec.widths.bottom, spec.widths.left)
  }
  function isNone(spec) { return maxWidth(spec) <= 0 }
  function uniform(spec) {
    var w = spec && spec.widths
    return !!w && w.top === w.right && w.top === w.bottom && w.top === w.left
  }
  // The spike draws every border with Rectangle's own: a gradient shows as
  // its first colour.
  function needsOverlay(spec) { return false }
  function canUseNative(spec) { return !isNone(spec) }
  function top(spec) { return spec && spec.widths ? spec.widths.top : 0 }
  function right(spec) { return spec && spec.widths ? spec.widths.right : 0 }
  function bottom(spec) { return spec && spec.widths ? spec.widths.bottom : 0 }
  function left(spec) { return spec && spec.widths ? spec.widths.left : 0 }
  function uniformWidth(spec) { return spec && spec.widths ? spec.widths.top : 0 }
  function color(spec) { return spec ? spec.color : "transparent" }
}
