import QtQuick
import QtTest
import "../plugin-page/Shortcuts.js" as Sc

// The keys: how a key event is written, what a hand-written keys.json may
// say, and what moving a key is allowed to do.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_shortcuts.qml
TestCase {
  name: "Shortcuts"

  function ev(key, mods) { return { key: key, modifiers: mods || 0 } }

  function init() { Sc.load({}) }

  function test_events_are_written_one_way() {
    compare(Sc.fromEvent(ev(Qt.Key_P, Qt.ControlModifier | Qt.ShiftModifier)), "Ctrl+Shift+P")
    compare(Sc.fromEvent(ev(Qt.Key_Return, Qt.ControlModifier)), "Ctrl+Enter")
    compare(Sc.fromEvent(ev(Qt.Key_Enter, Qt.ControlModifier | Qt.KeypadModifier)), "Ctrl+Enter")
    compare(Sc.fromEvent(ev(Qt.Key_Backtab, Qt.ShiftModifier)), "Shift+Tab")
    compare(Sc.fromEvent(ev(Qt.Key_Up, Qt.AltModifier)), "Alt+Up")
    compare(Sc.fromEvent(ev(Qt.Key_QuoteLeft, Qt.ControlModifier)), "Ctrl+`")
    compare(Sc.fromEvent(ev(Qt.Key_T)), "T")
    // A symbol says its own Shift: Ctrl+Shift+= is Ctrl and the plus.
    compare(Sc.fromEvent(ev(Qt.Key_Plus, Qt.ControlModifier | Qt.ShiftModifier)), "Ctrl+Plus")
    compare(Sc.fromEvent(ev(Qt.Key_Question, Qt.ControlModifier | Qt.ShiftModifier)), "Ctrl+?")
    compare(Sc.fromEvent(ev(Qt.Key_Control, Qt.ControlModifier)), "")
    // A dead key is what it prints: US-International's backtick.
    compare(Sc.fromEvent(ev(Qt.Key_Dead_Grave, Qt.ControlModifier)), "Ctrl+`")
    // A German keyboard's ß has no capital of one letter: it stays ß, not SS.
    compare(Sc.fromEvent(ev(Qt.Key_ssharp, Qt.ControlModifier | Qt.AltModifier)), "Ctrl+Alt+ß")
    compare(Sc.canonical("ctrl+ß"), "Ctrl+ß")
    compare(Sc.fromEvent(ev(Qt.Key_Eacute, Qt.ControlModifier)), "Ctrl+É")
    verify(Sc.hit(ev(Qt.Key_Dead_Grave, Qt.ControlModifier), "code"))
    verify(Sc.hit(ev(Qt.Key_E, Qt.ControlModifier), "code"))
    // The panes, left to right, are the digits (2026-10-27); Ctrl+\ and its
    // Shift, which arrives as the bar, open and close the side ones.
    verify(Sc.hit(ev(Qt.Key_1, Qt.ControlModifier), "pane1"))
    verify(Sc.hit(ev(Qt.Key_2, Qt.ControlModifier), "pane2"))
    verify(Sc.hit(ev(Qt.Key_3, Qt.ControlModifier), "pane3"))
    // The dashboard straight, with Alt (2026-10-30); Ctrl+2 stays the flip.
    verify(Sc.hit(ev(Qt.Key_2, Qt.ControlModifier | Qt.AltModifier), "dashGo"))
    verify(!Sc.hit(ev(Qt.Key_2, Qt.ControlModifier | Qt.AltModifier), "pane2"))
    verify(!Sc.hit(ev(Qt.Key_2, Qt.ControlModifier), "dashGo"))
    verify(Sc.hit(ev(Qt.Key_Backslash, Qt.ControlModifier), "sidebar"))
    verify(Sc.hit(ev(Qt.Key_Bar, Qt.ControlModifier | Qt.ShiftModifier), "day"))
    verify(!Sc.hit(ev(Qt.Key_BracketLeft, Qt.ControlModifier), "sidebar"))
    verify(Sc.hit(ev(Qt.Key_Left, Qt.AltModifier), "paneLeft"))
    verify(Sc.hit(ev(Qt.Key_BracketLeft, Qt.AltModifier), "dayPrev"))
  }

  function test_spellings() {
    compare(Sc.canonical("ctrl+shift+p"), "Ctrl+Shift+P")
    compare(Sc.canonical("Shift+Ctrl+P"), "Ctrl+Shift+P")
    compare(Sc.canonical("Ctrl++"), "Ctrl+Plus")
    compare(Sc.canonical("control+return"), "Ctrl+Enter")
    compare(Sc.canonical("Super+Escape"), "Super+Esc")
    compare(Sc.canonical("Shift+/"), "/")
    compare(Sc.canonical("Hyper+P"), "")
    compare(Sc.canonical("Ctrl+Nonsense"), "")
  }

  function test_show() {
    compare(Sc.show("Alt+Up"), "Alt+↑")
    compare(Sc.show("T"), "t")
    compare(Sc.show("Ctrl+T"), "Ctrl+T")
    compare(Sc.show("Ctrl+Plus"), "Ctrl++")
    // Super is Windows' own key there, said first, as the manual says it.
    compare(Sc.show("Alt+Super+P"), Qt.platform.os === "windows" ? "Win+Alt+P" : "Alt+Super+P")
    compare(Sc.show("Super"), "Super")
  }

  function test_defaults_hit() {
    verify(Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "bold"))
    verify(!Sc.hit(ev(Qt.Key_B, Qt.ControlModifier | Qt.ShiftModifier), "bold"))
    verify(!Sc.hit(ev(Qt.Key_B, Qt.ControlModifier | Qt.ShiftModifier), "sidebar"))   // gone 2026-10-27
    verify(Sc.hit(ev(Qt.Key_Equal, Qt.ControlModifier), "zoomIn"))
    verify(Sc.hit(ev(Qt.Key_Plus, Qt.ControlModifier | Qt.ShiftModifier), "zoomIn"))
    verify(Sc.hit(ev(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier), "redo"))
    verify(Sc.hit(ev(Qt.Key_Y, Qt.ControlModifier), "redo"))
  }

  // The keyboard pass (2026-11-25): one rule for the same act in every
  // place it is done.
  function test_the_same_act_has_the_same_keys() {
    // The Menu key is a key, not a modifier alone; Shift+F10 beside it.
    compare(Sc.fromEvent(ev(Qt.Key_Menu)), "Menu")
    verify(Sc.hit(ev(Qt.Key_Menu), "menu"))
    verify(Sc.hit(ev(Qt.Key_F10, Qt.ShiftModifier), "menu"))
    compare(Sc.canonical("menu"), "Menu")
    // Ctrl+S answers.
    verify(Sc.hit(ev(Qt.Key_S, Qt.ControlModifier), "save"))
    // Find: F3 and the arrows, the note's and a PDF's.
    verify(Sc.hit(ev(Qt.Key_F3), "findNext"))
    verify(Sc.hit(ev(Qt.Key_F3, Qt.ShiftModifier), "findPrev"))
    verify(Sc.hit(ev(Qt.Key_Down), "findNext"))
    verify(Sc.hit(ev(Qt.Key_Up), "findPrev"))
    // F2 renames and Backspace removes wherever they do one of them.
    var renames = ["dashRename", "settingsRename", "notebookCorrect"]
    for (var i = 0; i < renames.length; i++) verify(Sc.keysOf(renames[i]).indexOf("F2") >= 0, renames[i])
    var drops = ["dashDrop", "settingsForget", "notebookForget", "marginDecline", "pdfRemove"]
    for (var j = 0; j < drops.length; j++) {
      verify(Sc.keysOf(drops[j]).indexOf("Del") >= 0, drops[j] + " Del")
      verify(Sc.keysOf(drops[j]).indexOf("Backspace") >= 0, drops[j] + " Backspace")
    }
    // Space ticks on a row, as on the dashboard; Ctrl+L as in the note.
    verify(Sc.hit(ev(Qt.Key_Space), "listDone"))
    verify(Sc.hit(ev(Qt.Key_L, Qt.ControlModifier), "listDone"))
    // A bare letter in the sidebar finds a project: P and W are Alt's only.
    verify(!Sc.hit(ev(Qt.Key_P), "listPage"))
    verify(Sc.hit(ev(Qt.Key_P, Qt.AltModifier), "listPage"))
    verify(!Sc.hit(ev(Qt.Key_W), "listWeek"))
    // `?` in every list that is not typed in.
    var lists = ["dash", "lists", "files", "calendar", "pdf", "paper", "export", "margin", "settings", "notebook", "autonomy", "folders", "checkin"]
    for (var k = 0; k < lists.length; k++) verify(Sc.byId.keysHere.places.indexOf(lists[k]) >= 0, "? in " + lists[k])
    // Every place an action names is a place the sheet can say.
    for (var a = 0; a < Sc.actions.length; a++)
      for (var p = 0; p < Sc.actions[a].places.length; p++)
        verify(Sc.places[Sc.actions[a].places[p]] !== undefined, Sc.actions[a].id + ": " + Sc.actions[a].places[p])
  }

  // The six keys from outside are said in the system's words.
  function test_the_system_is_named() {
    var rows = Sc.rows("", { owned: true, actions: [{ id: "page", does: "Page", keys: ["Alt+Super+="], own: ["Alt+Super+="] }] })
    var page = rows.filter(function (r) { return r.id === "hypr:page" })[0]
    compare(page.where, Sc.systemName)
    compare(Sc.systemName, Qt.platform.os === "windows" ? "Windows" : "Hyprland")
  }

  // No two actions that can be pressed in the same place share a key.
  function test_no_default_collides() {
    for (var i = 0; i < Sc.actions.length; i++) {
      var a = Sc.actions[i]
      for (var j = 0; j < a.keys.length; j++) {
        var c = Sc.check(a.id, a.keys[j])
        verify(c.ok, a.id + " " + a.keys[j] + ": " + c.reason)
        compare(c.taken.length, 0, a.id + " " + a.keys[j] + " also " + c.taken.join(","))
      }
    }
  }

  function test_moving_a_key() {
    // Ctrl+Shift+K: free (Ctrl+K makes a link since 2026-10-28).
    var c = Sc.assign("bold", "Ctrl+Shift+K")
    verify(c.ok)
    verify(Sc.hit(ev(Qt.Key_K, Qt.ControlModifier | Qt.ShiftModifier), "bold"))
    verify(!Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "bold"))
    compare(JSON.stringify(Sc.save()), JSON.stringify({ bold: ["Ctrl+Shift+K"] }))
    // Added beside, not in place of.
    Sc.assign("bold", "Ctrl+Alt+B", true)
    compare(Sc.keysOf("bold").join(" "), "Ctrl+Shift+K Ctrl+Alt+B")
    // Back to its own, and the file forgets it.
    Sc.reset("bold")
    compare(Sc.keysOf("bold").join(" "), "Ctrl+B")
    compare(JSON.stringify(Sc.save()), "{}")
  }

  // The rest of the map (2026-10-28): the link, the symbols that are keys
  // in lists, and settings walked as a list.
  function test_the_rest_of_the_map() {
    verify(Sc.hit(ev(Qt.Key_K, Qt.ControlModifier), "link"))
    verify(Sc.hit(ev(Qt.Key_Question, Qt.ShiftModifier), "keysHere"))
    // `#` reaches a project by its letters since 2026-11-17 (plan.md item
    // 19); since 2026-11-22 any letter does, so the lists' letters moved
    // off letters: the tag Ctrl+Enter and a section Shift+Enter (as Ctrl-
    // and Shift-click), the page and week Alt+P and Alt+W, j k the arrows.
    verify(Sc.hit(ev(Qt.Key_NumberSign, Qt.ShiftModifier), "sideReach"))
    verify(Sc.hit(ev(Qt.Key_Return, Qt.ControlModifier), "listTag"))
    verify(Sc.hit(ev(Qt.Key_Return, Qt.ShiftModifier), "listClass"))
    verify(Sc.hit(ev(Qt.Key_P, Qt.AltModifier), "listPage"))
    verify(Sc.hit(ev(Qt.Key_W, Qt.AltModifier), "listWeek"))
    verify(!Sc.hit(ev(Qt.Key_T, 0), "listTag"))
    verify(!Sc.hit(ev(Qt.Key_S, 0), "listClass"))
    verify(!Sc.hit(ev(Qt.Key_J, 0), "listDown"))
    verify(!Sc.hit(ev(Qt.Key_K, 0), "listUp"))
    verify(!Sc.hit(ev(Qt.Key_T, 0), "calToday"))
    verify(Sc.hit(ev(Qt.Key_T, Qt.ShiftModifier), "dashNoDate"))
    verify(!Sc.hit(ev(Qt.Key_T, Qt.ShiftModifier), "dashWhen"))
    verify(Sc.hit(ev(Qt.Key_F2, 0), "dashRename"))
    verify(Sc.hit(ev(Qt.Key_Space, 0), "settingsChange"))
    verify(Sc.hit(ev(Qt.Key_Delete, 0), "settingsForget"))
    verify(Sc.hit(ev(Qt.Key_Delete, 0), "notebookForget"))
    // Gone: the settings sheet's own letters.
    compare(Sc.keysOf("settingsSound").length, 0)
    compare(Sc.keysOf("settingsNotebook").length, 0)
    // `?` never in a place you type in.
    verify(!Sc.check("keysHere", "?").taken.length)
    compare(Sc.byId["keysHere"].places.indexOf("note"), -1)
  }

  function test_taking_a_key_another_has() {
    var c = Sc.check("italic", "Ctrl+B")
    verify(c.ok)
    compare(c.taken.join(), "bold")
    Sc.assign("italic", "Ctrl+B")
    compare(Sc.keysOf("bold").length, 0)
    verify(Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "italic"))
    // The same key in another place is no one's business: Enter in the
    // dashboard and Enter in the calendar never meet.
    compare(Sc.check("dashOpen", "Enter").taken.length, 0)
    // Bold back takes Ctrl+B back from italic.
    compare(Sc.reset("bold").join(), "italic")
    verify(Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "bold"))
    verify(!Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "italic"))
  }

  function test_typing_is_kept() {
    // A letter alone would be typed where you write…
    verify(!Sc.check("bold", "K").ok)
    verify(!Sc.check("zoomIn", "Shift+K").ok)
    // …but the dashboard is not written in.
    verify(Sc.check("dashPriority", "J").ok)
    // The text field's own keys are never taken.
    verify(!Sc.check("bold", "Ctrl+C").ok)
    verify(!Sc.check("blockStart", "Up").ok)
    verify(!Sc.check("checkbox", "Enter").ok)
    verify(Sc.check("dashDown", "J").ok)
  }

  function test_hand_written_file() {
    // Ctrl+Shift+I: free. (Ctrl+J was, until it became the agent's pane,
    // read before any key of the note's, 2026-10-21.)
    verify(Sc.check("italic", "Ctrl+Shift+I").ok)
    Sc.load({ bold: "ctrl+k", italic: ["Ctrl+Shift+I", "nonsense"], nothing: ["Ctrl+Q"], code: 3 })
    compare(Sc.keysOf("bold").join(), "Ctrl+K")
    compare(Sc.keysOf("italic").join(), "Ctrl+Shift+I")
    compare(Sc.keysOf("code").join(), "Ctrl+`,Ctrl+E")
    compare(Sc.save().nothing, undefined)
  }

  function test_rows() {
    var r = Sc.rows("")
    compare(r[0].kind, "head")
    var r2 = Sc.rows("bold")
    compare(r2.length, 2)
    compare(r2[1].id, "bold")
    var r3 = Sc.rows("ctrl+shift+p")
    verify(r3.some(function (x) { return x.id === "private" }))
    var hy = [{ id: "pomoToggle", does: "Pomo toggle", keys: ["Alt+Super+P"], own: ["Alt+Super+P"] }]
    var r4 = Sc.rows("pomo", { owned: false, actions: hy })
    compare(r4[r4.length - 2].kind, "offer")
    compare(r4[r4.length - 1].kind, "fixed")
    compare(r4[r4.length - 1].where, "Hyprland")
    var r5 = Sc.rows("pomo", { owned: true, actions: [{ id: "pomoToggle", does: "Pomo toggle", keys: ["Alt+Super+K"], own: ["Alt+Super+P"] }] })
    compare(r5[r5.length - 1].kind, "hypr")
    compare(r5[r5.length - 1].id, "hypr:pomoToggle")
    verify(r5[r5.length - 1].changed)
    verify(!r5.some(function (x) { return x.kind === "offer" }))
    compare(Sc.rows("super+alt+k", { owned: true, actions: [{ id: "pomoToggle", does: "Pomo toggle", keys: ["Alt+Super+K"], own: ["Alt+Super+P"] }] }).length, 2)
  }

  // Reaching a project from the keyboard (plan.md item 19, 2026-11-17).
  function test_reaching_a_project() {
    verify(Sc.hit(ev(Qt.Key_O, Qt.ControlModifier), "switcher"))
    verify(Sc.hit(ev(Qt.Key_7, Qt.AltModifier), "projectKey"))
    verify(!Sc.hit(ev(Qt.Key_0, Qt.AltModifier), "projectKey"))
    verify(Sc.hit(ev(Qt.Key_Backtab, Qt.ShiftModifier), "calProjects"))
    verify(Sc.hit(ev(Qt.Key_Backtab, Qt.ShiftModifier), "listPrev"))
    verify(!Sc.hit(ev(Qt.Key_Backtab, Qt.ShiftModifier), "listBack"))
    verify(Sc.hit(ev(Qt.Key_Tab, 0), "switchDown"))
    // Nothing global takes a key of the switcher's box or the lists'.
    verify(Sc.check("switcher", "Ctrl+O").ok)
    compare(Sc.check("projectKey", "Alt+7").taken, [])
  }
}
