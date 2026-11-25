pragma Singleton
import QtQuick

// The shell's palette, where the shell is Windows: light or dark as the
// system's app mode says, the accent the person picked in Settings, both
// followed live. The names are omarchy-shell's (qs.Commons Color), so the
// page's ThemeColors takes them as it takes a theme's. A colors.toml at
// ~/.local/state/omarchy/current/theme/ still wins there, key by key.
QtObject {
  id: root

  readonly property SystemPalette sys: SystemPalette { colorGroup: SystemPalette.Active }
  readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark

  // Windows 11's own grounds and text for each mode.
  property color foreground: dark ? "#f3f3f3" : "#1b1b1b"
  property color background: dark ? "#202020" : "#f9f9f9"
  property color accent: sys.accent
  property color urgent: dark ? "#ff99a4" : "#c42b1c"
  property color warning: dark ? "#fce100" : "#9d5d00"
  property color muted: dark ? "#9a9a9a" : "#6b6b6b"

  readonly property var shellValues: ({})

  function loadColors(raw) {
    var lines = String(raw || "").split("\n"), got = {}
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) got[m[1]] = m[2]
    }
    if (got.foreground) root.foreground = got.foreground
    if (got.background) root.background = got.background
    if (got.accent) root.accent = got.accent
    if (got.red) root.urgent = got.red
    if (got.yellow) root.warning = got.yellow
    if (got.muted) root.muted = got.muted
  }
  function loadShell(raw) { /* shell.toml overrides, unused on Windows */ }

  function fade(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  readonly property QtObject menu: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.fade(root.foreground, 0.16)
    property color scrim: root.fade(root.background, 0.5)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.dark ? "#2c2c2c" : "#f3f3f3"
    property color text: root.foreground
    property color border: root.fade(root.foreground, 0.16)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.fade(root.foreground, 0.16)
  }
  readonly property QtObject bar: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color active: root.urgent
  }
}
