// What a theme's hyprland.lua says Hyprland's active border is, in the
// shell's own words for a border ("#D6C24A #EC9E3E #FF8D92 45deg"), for
// Border.resolvedGradient to read. Omarchy writes it one of two ways, as a
// colour or as a gradient:
//   local active_border_color = "rgb(dcd7ba)"
//   local active_border_color = { colors = { "rgba(8a8588ee)", "rgba(e2dddcee)" }, angle = 45 }
// Empty when the file says nothing (ThemeColors' activeBorder; the accent
// stands in).
.pragma library

function activeBorder(text) {
  var t = String(text || "")
  var at = t.search(/\bactive_border_color\s*=/)
  if (at < 0) return ""
  var rest = t.slice(at).replace(/^[^=]*=/, "")
  var end = rest.search(/\n\s*(local\s|hl\.)/)
  var def = end >= 0 ? rest.slice(0, end) : rest
  var colours = [], m, re = /"([^"]+)"/g
  while ((m = re.exec(def)) !== null) colours.push(m[1].replace(/\s+/g, ""))
  var angle = def.match(/angle\s*=\s*(-?\d+(?:\.\d+)?)/)
  return colours.length === 0 ? "" : colours.join(" ") + (angle ? " " + angle[1] + "deg" : "")
}

// How strongly the page's secondary text must read, as a contrast with the
// ground, given what its faint text is held to (`faint`, 4.5:1) and what the
// theme's own foreground reaches (`top`). The two greys are two steps of one
// ladder — a block the agent may answer reads dim, one it may not reads
// faint — so secondary text sits between the faint grey and the foreground:
// their middle as the eye counts it (a ratio's middle is its geometric
// mean), and no brighter than 6:1, where it would stop reading as secondary.
// On 2026-11-20 both were held to 4.5:1 and came out one colour.
function dimTarget(faint, top) {
  if (!(top > faint)) return faint
  return Math.min(6.0, Math.sqrt(faint * top))
}
