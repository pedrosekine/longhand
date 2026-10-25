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
    verify(Sc.hit(ev(Qt.Key_Dead_Grave, Qt.ControlModifier), "code"))
    verify(Sc.hit(ev(Qt.Key_E, Qt.ControlModifier), "code"))
    // The panes, left to right, are the bracket keys (2026-10-23).
    verify(Sc.hit(ev(Qt.Key_BracketLeft, Qt.ControlModifier), "sidebar"))
    verify(Sc.hit(ev(Qt.Key_Backslash, Qt.ControlModifier), "home"))
    verify(Sc.hit(ev(Qt.Key_BracketRight, Qt.ControlModifier), "day"))
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
  }

  function test_defaults_hit() {
    verify(Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "bold"))
    verify(!Sc.hit(ev(Qt.Key_B, Qt.ControlModifier | Qt.ShiftModifier), "bold"))
    verify(Sc.hit(ev(Qt.Key_B, Qt.ControlModifier | Qt.ShiftModifier), "sidebar"))
    verify(Sc.hit(ev(Qt.Key_Equal, Qt.ControlModifier), "zoomIn"))
    verify(Sc.hit(ev(Qt.Key_Plus, Qt.ControlModifier | Qt.ShiftModifier), "zoomIn"))
    verify(Sc.hit(ev(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier), "redo"))
    verify(Sc.hit(ev(Qt.Key_Y, Qt.ControlModifier), "redo"))
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
    var c = Sc.assign("bold", "Ctrl+K")
    verify(c.ok)
    verify(Sc.hit(ev(Qt.Key_K, Qt.ControlModifier), "bold"))
    verify(!Sc.hit(ev(Qt.Key_B, Qt.ControlModifier), "bold"))
    compare(JSON.stringify(Sc.save()), JSON.stringify({ bold: ["Ctrl+K"] }))
    // Added beside, not in place of.
    Sc.assign("bold", "Ctrl+Alt+B", true)
    compare(Sc.keysOf("bold").join(" "), "Ctrl+K Ctrl+Alt+B")
    // Back to its own, and the file forgets it.
    Sc.reset("bold")
    compare(Sc.keysOf("bold").join(" "), "Ctrl+B")
    compare(JSON.stringify(Sc.save()), "{}")
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
}
