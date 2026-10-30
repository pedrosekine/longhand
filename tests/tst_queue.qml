import QtQuick
import QtTest
import "../plugin-page/Blocks.js" as Blocks
import "../plugin-page/Queue.js" as Queue

// What the page asks of the runner, and in what order (Queue.js, moved out
// of Page.qml on 2026-10-30).
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_queue.qml
TestCase {
  name: "Queue"
  // Blocks: 0 the heading words, 1–3 a list (the last only its marker),
  // 4 a question, 5 a list of one, apart.
  readonly property var blocks: Blocks.split("Seminar notes\n\n- [ ] read ch 2\n- [ ] draft the intro\n- \n\nwhat is due?\n\n- plain bullet")
  function h(k) { return blocks[k].hash }

  function test_a_line_s_sign() {
    compare(Queue.triggerFor("- [ ] read ch 2"), "checkbox")
    compare(Queue.triggerFor("  * [x] read ch 2"), "tick")
    compare(Queue.triggerFor("what is due?"), "question")
    compare(Queue.triggerFor("- [ ] "), "")              // a box with no words yet
    compare(Queue.triggerFor("just words"), "")
    compare(Queue.triggerOf(blocks, h(1)), "checkbox")
    compare(Queue.triggerOf(blocks, h(4)), "question")
    compare(Queue.triggerOf(blocks, h(0)), "")
    compare(Queue.triggerOf(blocks, "nope"), "")
    compare(Queue.countTicked("- [x] a\n- [ ] b\n  - [X] c\nx [x] d"), 2)
  }

  function test_the_block_the_margin_is_about() {
    compare(Queue.hashNear(blocks, 2), h(1))
    compare(Queue.hashNear(blocks, 3), h(2))
    compare(Queue.hashNear(blocks, 4), h(2))   // only its marker: the item above
    compare(Queue.hashNear(blocks, 5), h(2))   // a blank line: the block above
    compare(Queue.hashNear(blocks, 1), h(0))
    compare(Queue.hashNear(blocks, 6), h(4))
  }

  function test_one_list_one_submission() {
    compare(Queue.listAround(blocks, h(1)), [h(1), h(2), h(3)])
    compare(Queue.listAround(blocks, h(3)), [h(1), h(2), h(3)])
    compare(Queue.listAround(blocks, h(5)), [h(5)])     // a blank line apart: its own list
    compare(Queue.listAround(blocks, h(4)), [h(4)])     // not an item
    compare(Queue.listAround(blocks, "nope"), ["nope"])
  }

  function test_what_is_drawn_as_away() {
    compare(Queue.away([], blocks, [h(1)]), [h(1)])
    compare(Queue.away([h(1)], blocks, [h(1), h(4)]), [h(1), h(4)])     // each once
    compare(Queue.away(["gone", h(1)], blocks, []), [h(1)])           // no longer a block
    compare(Queue.away([], blocks, ["", h(4)]), [h(4)])
  }

  function test_answered_once() {
    verify(!Queue.answered(null))
    verify(!Queue.answered({}))
    verify(!Queue.answered({ chat: [] }))
    verify(Queue.answered({ reply: "read chapter 2 first" }))
    verify(Queue.answered({ chat: [{ who: "you", text: "and then?" }] }))
  }

  function test_in_order_each_once() {
    var a = ["longhand-agent", "run", "--trigger", "checkbox", "--hash", "x"]
    var b = ["longhand-agent", "chat", "--hash", "y", "--message", "and then?"]
    var q = Queue.added([], a, "x")
    compare(q.length, 1)
    q = Queue.added(q, b, "y")
    compare(q.map(function (e) { return e.hash }), ["x", "y"])
    var same = Queue.added(q, a.slice(), "x")
    verify(same === q, "a command already waiting is not queued twice")
    compare(Queue.added(q, a.concat(["--date", "2026.10.13"]), "x").length, 3)
  }

  function test_what_a_failed_run_says() {
    compare(Queue.failure(""), "")
    compare(Queue.failure(undefined), "")
    compare(Queue.failure("\n  error: opencode: unknown flag --model\nusage: …"), "opencode: unknown flag --model")
    compare(Queue.failure("x".repeat(200)).length, 120)
  }
}
