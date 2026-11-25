import QtQuick
import QtQuick.Controls
import QtTest
import "../plugin-page"

// The page's menu on a box typed in (FieldMenu.qml): a right click asks the
// page for its edit menu, with what the box can do, and Qt's own menu on
// the field stays shut. The edits run on the box itself.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_fieldmenu.qml
Item {
  width: 400
  height: 200

  Item {
    id: stubPage
    property var asked: null
    property string usedAs: ""
    property bool handOn: true
    function used(what, how) { stubPage.usedAs = what + ":" + how }
    function editMenuAt(over, x, y, list) { stubPage.asked = { over: over, list: list } }
  }

  TextField {
    id: f
    width: 300
    text: "hello world"
    FieldMenu { page: stubPage; field: parent }
  }

  TestCase {
    name: "FieldMenu"
    when: windowShown

    function entry(name) {
      return stubPage.asked.list.filter(function (e) { return e.text === name })[0]
    }

    function test_a_right_click_asks_the_page() {
      stubPage.asked = null
      f.select(0, 5)
      mouseClick(f, 10, f.height / 2, Qt.RightButton)
      verify(stubPage.asked !== null, "the page was asked for its menu")
      compare(stubPage.asked.over, f)
      compare(stubPage.usedAs, "edit-menu:box")
      verify(entry("Copy").enabled, "words selected: copy offered")
      verify(entry("Cut").enabled)
      verify(f.ContextMenu.menu === null, "Qt's own menu stays shut")
    }

    function test_the_box_lights_only_under_the_hand() {
      stubPage.handOn = true
      wait(20)
      verify(f.hoverEnabled, "the hand on the mouse: the box's hover look may show")
      stubPage.handOn = false
      verify(!f.hoverEnabled, "the keys typing: no hover look under a still pointer")
      stubPage.handOn = true
    }

    function test_its_edits_run_on_the_box() {
      f.text = "hello world"
      f.select(0, 5)
      mouseClick(f, 10, f.height / 2, Qt.RightButton)
      entry("Cut").run()
      compare(f.text, " world")
      f.cursorPosition = f.length
      mouseClick(f, f.width - 10, f.height / 2, Qt.RightButton)
      verify(!entry("Copy").enabled, "nothing selected: no copy")
      entry("Paste").run()
      compare(f.text, " worldhello")
      entry("Select all").run()
      compare(f.selectedText, " worldhello")
    }
  }
}
