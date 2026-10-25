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
