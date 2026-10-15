import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The current Omarchy theme's palette, read from its colors.toml (watched,
// so `omarchy theme set` repaints the page at once), turned into the roles
// the page draws with. Every Omarchy theme names the same keys — accent,
// selection, muted, dark_foreground, red, yellow, orange, green, cyan, blue,
// magenta — so roles map to names, never to fixed colours. A key a theme
// lacks falls back to the shell's own palette; a grey too faint to read
// gives way to one that is (see `readable`).
Item {
  id: root

  property var keys: ({})
  readonly property string path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  function pick(name, fallback) {
    var v = root.keys[name]
    return v ? v : fallback
  }

  readonly property color foreground: Color.menu.text
  readonly property color background: Color.menu.background
  readonly property color accent: pick("accent", Color.accent)

  // Contrast, WCAG's way: what decides whether a colour can carry text.
  function luminance(c) {
    function ch(x) { return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = root.luminance(a), lb = root.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }
  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }

  // The first of the theme's greys that is readable at `target` against the
  // background; else the foreground faded only as far as `target` allows.
  // Most themes' `muted` is a comment/border grey (1.5–3:1) — fine for a
  // line, too faint for words.
  function readable(names, target) {
    for (var i = 0; i < names.length; i++) {
      var v = root.keys[names[i]]
      if (v && root.contrast(Qt.color(v), root.background) >= target) return Qt.color(v)
    }
    var lo = 0, hi = 1
    for (var k = 0; k < 16; k++) {
      var mid = (lo + hi) / 2
      if (root.contrast(root.mix(root.foreground, root.background, mid), root.background) >= target) lo = mid
      else hi = mid
    }
    return root.mix(root.foreground, root.background, lo)
  }

  // Secondary text (dates, done items, code) at 4.5:1; faint things (faded
  // day numbers, borders, hints) at 3:1.
  readonly property color dim: { root.keys; return root.readable(["muted", "dark_foreground"], 4.5) }
  readonly property color faint: { root.keys; return root.readable(["dark_foreground", "muted"], 3.0) }
  readonly property color selection: pick("selection", Util.alpha(accent, 0.25))
  readonly property color red: pick("red", Color.urgent)
  readonly property color yellow: pick("yellow", accent)
  readonly property color orange: pick("orange", yellow)
  readonly property color green: pick("green", accent)
  readonly property color magenta: pick("magenta", accent)

  // How far a colour is from grey: what tells a theme's chromatic accent
  // (tokyo-night's blue, matte-black's orange) from one that is a warm or
  // cool grey (pentano's #C9C3BC, vantablack's #8D8D8D).
  function chroma(c) { return Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b) }

  // A colour taken away from the background — toward white on a dark ground,
  // black on a light one — until it reads at `target`. Moving to the extreme
  // rather than to the foreground keeps the hue: a theme's foreground is
  // itself often tinted (ethereal's peach), and mixing into it turns a blue
  // to mauve on the way.
  function toward(c, target) {
    if (root.contrast(c, root.background) >= target) return c
    var end = root.luminance(root.background) > 0.5 ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
    var lo = 0, hi = 1
    for (var k = 0; k < 16; k++) {
      var mid = (lo + hi) / 2
      if (root.contrast(root.mix(c, end, mid), root.background) >= target) hi = mid
      else lo = mid
    }
    return root.mix(c, end, hi)
  }

  // Heading levels: one colour, walking home to the text.
  //
  // Hue has no order — blue is not "more" than magenta — so giving each
  // level its own hue (the rule until 2026-10-15: the first four distinct of
  // accent/blue/magenta/cyan/green) drew four marks, not four ranks, and put
  // the accent on H1. An accent is a UI tint, mid-contrast by design: it made
  // H1 the *quietest* heading on the page in most of Omarchy's themes, and
  // under this one (accent #C9C3BC, chroma 0.05, 7.8:1) a title was a big
  // grey line dimmer than the paragraph below it.
  //
  // So rank is carried by the channels that have an order — size, weight,
  // the air above (Rows.js), and how far the colour has travelled back to
  // the prose. H1 is the theme's one chromatic voice at full strength; H2
  // and H3 are that same colour two fifths and three quarters of the way to
  // the text; H4–H6 are the text. A theme with no chroma to lend (vantablack,
  // white, solitude) ramps the only ladder it has instead — the text down
  // toward its quiet grey.
  readonly property var headings: {
    root.keys
    var prose = root.foreground
    var names = ["accent", "blue", "cyan", "green", "magenta", "yellow", "orange"]
    for (var i = 0; i < names.length; i++) {
      var v = names[i] === "accent" ? String(root.accent) : root.keys[names[i]]
      if (!v) continue
      var c = Qt.color(v)
      if (root.chroma(c) < 0.15 || root.contrast(c, root.background) < 3.0) continue
      var h1 = root.toward(c, 4.5)   // never fainter than secondary text is let be
      return [String(h1), String(root.mix(h1, prose, 0.40)),
              String(root.mix(h1, prose, 0.72)), String(prose)]
    }
    return [String(prose), String(root.mix(prose, root.dim, 0.40)),
            String(root.mix(prose, root.dim, 0.72)), String(root.dim)]
  }

  function parse(raw) {
    var out = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) out[m[1]] = m[2]
    }
    root.keys = out
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: root.keys = ({})
    onFileChanged: reload()
  }

  // A theme switch rewrites the theme folder (a file watch can miss that)
  // and pushes the new colours to the shell: when the shell's change, read
  // the palette again.
  Connections {
    target: Color
    function onForegroundChanged() { file.reload() }
    function onBackgroundChanged() { file.reload() }
    function onAccentChanged() { file.reload() }
  }
}
