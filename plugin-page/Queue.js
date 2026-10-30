// Queue — what the page asks of the runner, and in what order (moved out of
// Page.qml on 2026-10-30, the split's third pass; `tests/tst_queue.qml`
// holds it). The note comes in as its blocks (Blocks.split) and the queue
// as the list the page keeps; nothing here starts a process.
.pragma library
.import "Blocks.js" as Blocks

function countTicked(t) {
  var m = t.match(/^\s*[-*+] \[[xX]\] /gm)
  return m ? m.length : 0
}

// A line's sign for the agent: an open box, a ticked one, a closing ?.
function triggerFor(lineText) {
  var t = lineText.trim()
  if (/^[-*+] \[ \] \S/.test(t)) return "checkbox"
  if (/^[-*+] \[[xX]\] \S/.test(t)) return "tick"
  if (/\?$/.test(t)) return "question"
  return ""
}

// A block's sign, from its first line or its last.
function triggerOf(blocks, hash) {
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].hash !== hash) continue
    var lines = blocks[i].text.split("\n")
    return triggerFor(lines[0]) || triggerFor(lines[lines.length - 1])
  }
  return ""
}

// An item that is only its marker (what Enter leaves behind).
function bare(text) { return /^\s*[-*+] (\[[ xX]\] )?$/.test(text) }

// For the margin: the block under the cursor, or the nearest one above
// when the cursor rests on a blank line — which is where it lands right
// after finishing a line. An item that is only its marker is as good as a
// blank line: look up to the block that has words.
function hashNear(blocks, lineIndex) {
  var k = Blocks.blockAt(blocks, lineIndex)
  if (k >= 0 && bare(blocks[k].text)) k = -1
  if (k < 0) for (var i = blocks.length - 1; i >= 0; i--) if (blocks[i].start <= lineIndex && !bare(blocks[i].text)) { k = i; break }
  return k < 0 ? "" : blocks[k].hash
}

// The run of adjacent list items around a block: no blank line between
// them, all top-level items. One list, one submission.
function listAround(blocks, hash) {
  var k = -1
  for (var i = 0; i < blocks.length; i++) if (blocks[i].hash === hash) { k = i; break }
  if (k < 0 || blocks[k].kind !== "item") return [hash]
  var lo = k, hi = k
  while (lo > 0 && blocks[lo - 1].kind === "item" && blocks[lo - 1].end === blocks[lo].start) lo--
  while (hi < blocks.length - 1 && blocks[hi + 1].kind === "item" && blocks[hi + 1].start === blocks[hi].end) hi++
  var out = []
  for (var j = lo; j <= hi; j++) out.push(blocks[j].hash)
  return out
}

// What is drawn as away, with `hashes` added. Anything no longer a block in
// the note is dropped: a line whose date bound between the ask and the send
// is a different block now.
function away(sending, blocks, hashes) {
  var live = {}
  for (var b = 0; b < blocks.length; b++) live[blocks[b].hash] = true
  var next = []
  for (var k = 0; k < sending.length; k++)
    if (live[sending[k]]) next.push(sending[k])
  for (var i = 0; i < hashes.length; i++) {
    var h = String(hashes[i])
    if (h !== "" && next.indexOf(h) < 0) next.push(h)
  }
  return next
}

// A block the agent has already answered is not asked again. The hash is
// of the block's text, so a block that still carries its answer is text
// that has not changed since: the second pass would send the identical
// question, pay for it again, and — because a run overwrites the record —
// throw the first answer away. Change the words and it is a different
// block with no answer, which runs as usual; leave them and what you
// want is the conversation, which continues the session the first pass
// opened rather than starting a new one.
function answered(rec) {
  return !!rec && (!!rec.reply || (!!rec.chat && rec.chat.length > 0))
}

// In order, each once: a confirmed send must never be dropped because
// something else was asked for while the runner was busy. The queue with
// the command at its end, or the same queue when it waits there already.
function added(queued, cmd, hash) {
  var key = JSON.stringify(cmd)
  for (var i = 0; i < queued.length; i++) if (JSON.stringify(queued[i].cmd) === key) return queued
  return queued.concat([{ cmd: cmd, hash: hash }])
}

// What a failed run said, for the status line: its first line, without
// the "error:" it starts with, short.
function failure(said) {
  var lines = String(said || "").split("\n")
  for (var i = 0; i < lines.length; i++)
    if (lines[i].trim() !== "") return lines[i].trim().replace(/^error:\s*/, "").substring(0, 120)
  return ""
}
