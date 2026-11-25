.pragma library

// The shell's buttons name their pictures by a Nerd Font's code points.
// Windows has no Nerd Font, and has the same pictures in its own icon face
// (Segoe Fluent Icons on Windows 11, Segoe MDL2 Assets before it, the same
// code points in both). The ones Longhand's popups use:
var OWN = {
  "": "",   // play
  "": "",   // pause
  "": "",   // on to the next
  "": ""    // back to the start
}

function face(families) {
  if (families.indexOf("Segoe Fluent Icons") >= 0) return "Segoe Fluent Icons"
  if (families.indexOf("Segoe MDL2 Assets") >= 0) return "Segoe MDL2 Assets"
  return ""
}

// What to draw for a picture and in which face: Windows' own when it has
// one, else the text as it was given, in the face asked for.
function drawn(iconText, families, fallbackFace) {
  var f = face(families)
  if (f !== "" && OWN[iconText] !== undefined) return { text: OWN[iconText], face: f }
  return { text: iconText, face: fallbackFace }
}
