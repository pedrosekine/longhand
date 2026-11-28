import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
// Qt 6.12's QtQuick has a `Color` of its own that shadows the shell's
// (2026-10-18): the shell's palette is named through the module.
import qs.Commons as Commons
import qs.Ui
import "Shortcuts.js" as Sc

// The quick-add gesture for the mouse: a glyph that opens today's note. It
// takes the accent colour when a reply is waiting that the student has not
// looked at yet — the same signal as the mark in the page header. (It took
// the urgent one until the bar pass, 2026-11-28: a reply waiting was as
// loud as a deadline due today.) The right button opens the dashboard,
// where what the agent proposes or asks is settled.
BarWidget {
  id: root
  moduleName: "longhand.page"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service { id: svc }
  AgentState { id: agent; config: svc.config }

  // What the agent proposes or asks, waiting (docs/agent.md): a quiet count
  // beside the glyph — never a notification, never a sound.
  property int asks: 0
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/longhand/proposals.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.asks = JSON.parse(text()).items.filter(function (x) { return x.status === "open" }).length }
      catch (e) { root.asks = 0 }
    }
    onLoadFailed: root.asks = 0
    onFileChanged: reload()
  }

  // The Hyprland key that opens the page from anywhere, for the tooltip:
  // the mouse teaches the key. Read again when the keys' files change,
  // since the keys sheet can move it (it was read on every hover: a Python
  // started each time the pointer crossed the glyph).
  property string pageKey: ""
  readonly property string hyprDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr/"
  function readKeys() { if (keyProc.running) keyAgain = true; else keyProc.running = true }
  property bool keyAgain: false
  Repeater {
    model: ["longhand.lua", "bindings.lua"]
    Item {
      required property string modelData
      FileView {
        path: root.hyprDir + parent.modelData
        watchChanges: true
        printErrors: false
        onFileChanged: root.readKeys()
      }
    }
  }
  Process {
    id: keyProc
    onExited: if (root.keyAgain) { root.keyAgain = false; running = true }
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("hyprkeys.py").toString().replace(/^file:\/\//, "")), "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var page = JSON.parse(text).actions.filter(function (a) { return a.id === "page" })[0]
          root.pageKey = page && page.keys.length > 0 ? Sc.show(page.keys[0]) : ""
        } catch (e) {}
      }
    }
  }
  Component.onCompleted: keyProc.running = true

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏫" + (root.asks > 0 ? " " + root.asks : "")
    foreground: agent.unread > 0 ? Commons.Color.accent
      : (bar ? bar.barForeground : Commons.Color.foreground)
    tooltipText: (agent.unread > 0
      ? "Today's note · " + agent.unread + (agent.unread === 1 ? " reply" : " replies") + " waiting"
      : "Today's note")
      + (root.asks > 0 ? " · " + root.asks + " from the agent, in the dashboard" : "")
      + (root.pageKey !== "" ? "   " + root.pageKey : "")
      + "\nleft: today's note · right: the dashboard"
    onPressed: function (b) {
      if (b === Qt.RightButton) Quickshell.execDetached(["omarchy-shell", "shell", "summon", "longhand.page", JSON.stringify({ view: "dashboard" })])
      else if (root.bar) root.bar.run("omarchy-shell shell toggle longhand.page '{}'")
      else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "longhand.page", "{}"])
    }
  }
}
