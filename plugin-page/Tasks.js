// Tasks — finding a checkbox line again in a note that may have changed.
//
// The what's-next list is read once; by the time a task in it is ticked,
// its note may have moved on. A line is found by its words — where it was,
// else wherever it is now — never by its number alone.
.pragma library

function escape(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// The index of the line holding checkbox `text` (ticked or not, as asked),
// trying `hint` first; -1 when it is gone.
function find(lines, hint, text, ticked) {
  var re = new RegExp("^(\\s*[-*+] )\\[" + (ticked ? "[xX]" : " ") + "\\] " + escape(text) + "$")
  if (hint >= 0 && hint < lines.length && re.test(lines[hint])) return hint
  for (var i = 0; i < lines.length; i++) if (re.test(lines[i])) return i
  return -1
}

// That line with its box flipped.
function flip(line, tick) {
  return line.replace(/^(\s*[-*+] )\[[ xX]\]/, function (all, lead) { return lead + "[" + (tick ? "x" : " ") + "]" })
}
