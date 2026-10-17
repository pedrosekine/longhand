import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Shortcuts.js" as Sc

// The quick-add gesture for the mouse: a glyph that opens today's note. It
// takes the accent colour when a reply is waiting that the student has not
// looked at yet — the same signal as the mark in the page header.
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
  // the mouse teaches the key. Read again on each hover, since the keys
  // sheet can move it.
  property string pageKey: ""
  Process {
    id: keyProc
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
    foreground: agent.unread > 0
      ? (bar ? bar.urgent : Color.urgent)
      : (bar ? bar.barForeground : Color.foreground)
    tooltipText: (agent.unread > 0
      ? "Today's note · " + agent.unread + (agent.unread === 1 ? " reply" : " replies") + " waiting"
      : "Today's note")
      + (root.asks > 0 ? " · " + root.asks + " from the agent, in the dashboard" : "")
      + (root.pageKey !== "" ? "   " + root.pageKey : "")
    onTooltipHoveredChanged: if (tooltipHovered && !keyProc.running) keyProc.running = true
    onPressed: {
      if (root.bar) root.bar.run("omarchy-shell shell toggle longhand.page '{}'")
      else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "longhand.page", "{}"])
    }
  }
}
