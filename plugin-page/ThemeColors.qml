import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import "Theme.js" as Theme

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

  readonly property color foreground: Commons.Color.menu.text
  readonly property color background: Commons.Color.menu.background
  readonly property color accent: pick("accent", Commons.Color.accent)

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
  readonly property color red: pick("red", Commons.Color.urgent)
  readonly property color yellow: pick("yellow", accent)
  readonly property color orange: pick("orange", yellow)
  readonly property color green: pick("green", accent)
  readonly property color magenta: pick("magenta", accent)
  readonly property color blue: pick("blue", accent)        // links (docs/files.md)
  // The paper private things are sunk into (docs/files.md, B · Paper): the
  // theme's own darker ground, which light themes give as a shade darker too.
  // Taken only when it is what it says, a shade darker than the ground the
  // page is drawn on (contrast under 1.35): the ground comes from the shell
  // and the key from colors.toml, and a page caught between two themes once
  // sank light paper under light words. Else the ground, darkened.
  readonly property color sunk: {
    root.keys
    var c = root.keys["dark_background"] ? Qt.color(root.keys["dark_background"]) : null
    if (c && root.luminance(c) < root.luminance(background) && root.contrast(c, background) < 1.35) return c
    return Qt.darker(background, root.luminance(background) > 0.5 ? 1.07 : 1.25)
  }

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

  // Perceptual distance, CIE76: how far apart two colours *look*. Contrast
  // cannot answer that — three tints of one blue at 6:1, 8:1 and 10:1 are
  // three readable steps and one colour, which is how the first ramp came
  // out (ΔE 14, 12, 11 under this theme: a difference you have to hunt for).
  // Roughly, under 10 is "the same colour, maybe", over 20 is "plainly not".
  function lab(c) {
    function lin(x) { return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4) }
    function f(t) { return t > 0.008856 ? Math.pow(t, 1 / 3) : 7.787 * t + 16 / 116 }
    var r = lin(c.r), g = lin(c.g), b = lin(c.b)
    var x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
    var y = f(0.2126 * r + 0.7152 * g + 0.0722 * b)
    var z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)]
  }
  function apart(a, b) {
    var p = root.lab(a), q = root.lab(b)
    return Math.sqrt(Math.pow(p[0] - q[0], 2) + Math.pow(p[1] - q[1], 2) + Math.pow(p[2] - q[2], 2))
  }

  // A colour taken further from `from` — out along the line that joins them,
  // which deepens it without turning it into another colour — until the two
  // are plainly not the same. It stops at 1.3× (past that the page would be
  // inventing a chroma the theme chose not to have), and never below 4.5:1.
  function deepen(c, from, want) {
    var out = c
    for (var k = 1.05; k <= 1.301; k += 0.05) {
      if (root.apart(out, from) >= want) break
      var v = Qt.rgba(Math.min(1, Math.max(0, from.r + (c.r - from.r) * k)),
                      Math.min(1, Math.max(0, from.g + (c.g - from.g) * k)),
                      Math.min(1, Math.max(0, from.b + (c.b - from.b) * k)), 1)
      if (root.contrast(v, root.background) < 4.5) break
      out = v
    }
    return out
  }

  // Heading levels: four states, each a different kind of thing.
  //
  // Hue has no order — blue is not "more" than magenta — so giving each
  // level its own hue (the rule until 2026-10-15: the first four distinct of
  // accent/blue/magenta/cyan/green) drew four marks, not four ranks, and put
  // the accent on H1. An accent is a UI tint, mid-contrast by design: it made
  // H1 the *quietest* heading on the page in most of Omarchy's themes, and
  // under this one (accent #C9C3BC, chroma 0.05, 7.8:1) a title was a big
  // grey line dimmer than the paragraph below it.
  //
  // The first fix ramped one colour to the text in four even steps, which
  // was right about hue and wrong about spacing: the top three all landed in
  // the pale end, ΔE 14/12/11 apart, near enough that you could not tell a
  // level from its neighbour without comparing. So the ladder now spends its
  // whole range, and each rung changes a different quality rather than a
  // little more of the same one:
  //
  //   H1  the theme's chroma, deepened until it is plainly not the text
  //   H2  that colour halfway home — a tint, still coloured
  //   H3  the prose, with no colour at all
  //   H4  the quiet grey (`dim`), the one step below the prose there is
  //
  // Rank still rides the channels that have an order — size, weight and the
  // air above a heading (Rows.js) — and no rung is within ΔE 20 of the one
  // under it in this theme. A palette with no chroma to lend (vantablack,
  // white, solitude) has only the one ladder, and walks the text down to the
  // same grey in even thirds.
  readonly property var headings: {
    root.keys
    var prose = root.foreground
    var names = ["accent", "blue", "cyan", "green", "magenta", "yellow", "orange"]
    for (var i = 0; i < names.length; i++) {
      var v = names[i] === "accent" ? String(root.accent) : root.keys[names[i]]
      if (!v) continue
      var c = Qt.color(v)
      if (root.chroma(c) < 0.15 || root.contrast(c, root.background) < 3.0) continue
      var h1 = root.deepen(root.toward(c, 4.5), prose, 45)
      return [String(h1), String(root.mix(h1, prose, 0.5)), String(prose), String(root.dim)]
    }
    return [String(prose), String(root.mix(prose, root.dim, 0.33)),
            String(root.mix(prose, root.dim, 0.66)), String(root.dim)]
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

  // Hyprland's active border, as the theme gives it (its hyprland.lua,
  // shipped or made from Omarchy's template): its colours and angle in the
  // shell's own words, "#D6C24A #EC9E3E #FF8D92 45deg", for Border to read.
  // Empty when the theme says nothing, and the accent stands in. The focus
  // frame is drawn with it (2026-10-25), so the page's active pane looks
  // like the active window.
  property string activeBorder: ""

  FileView {
    id: hyprFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/hyprland.lua"
    watchChanges: true
    printErrors: false
    onLoaded: root.activeBorder = Theme.activeBorder(text())
    onLoadFailed: root.activeBorder = ""
    onFileChanged: reload()
  }

  // A theme switch rewrites the theme folder (a file watch can miss that)
  // and pushes the new colours to the shell: when the shell's change, read
  // the palette again.
  Connections {
    target: Commons.Color
    function onForegroundChanged() { file.reload(); hyprFile.reload() }
    function onBackgroundChanged() { file.reload(); hyprFile.reload() }
    function onAccentChanged() { file.reload(); hyprFile.reload() }
  }
}
