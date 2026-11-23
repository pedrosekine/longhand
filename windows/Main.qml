import QtQuick
import "../plugin-page"

// What omarchy-shell is to the page, for the spike: something that holds it,
// opens it, and hears it ask to be hidden. Page.qml is loaded as it is.
Item {
  id: host

  QtObject {
    id: shell
    function hide(id) { page.close(); return true }
  }

  Page {
    id: page
    objectName: "longhandPage"
    shell: shell
    manifest: ({ id: "longhand.page" })
  }

  // No tray and no global key yet: when the page is put away, the host ends.
  Connections {
    target: page
    function onShowingChanged() { if (!page.showing && !hostKeepAlive) Qt.quit() }
  }

  // The shell has had the page loaded long before anyone summons it; here it
  // is opened as soon as it has read its config (or found there is none).
  property bool summoned: false
  // Opened before the note has been read, the page asks the note to take the
  // keys while it has no rows yet, and a sheet's hidden key catcher keeps
  // them (so the page's own "keys nowhere" net never fires). The host owes
  // the note the keys once it has loaded: the page's own way to the middle.
  property bool keysOwed: false
  function summon() {
    if (host.summoned) return
    host.summoned = true
    host.keysOwed = !page.noteService.ready
    page.open(JSON.stringify({ shape: hostShape === "overlay" ? "" : "alongside" }))
  }
  Connections {
    target: page.noteService
    function onConfigChanged() { host.summon() }
    function onLoaded() {
      if (!host.keysOwed) return
      host.keysOwed = false
      Qt.callLater(page.focusCenter)
    }
  }
  Timer { interval: 1500; running: true; onTriggered: host.summon() }
}
