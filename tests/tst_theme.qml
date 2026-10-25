import QtQuick
import QtTest
import "../plugin-page/Theme.js" as Theme

// Hyprland's active border, read from a theme's hyprland.lua in each of the
// ways Omarchy writes it (the stock themes and its template), for the focus
// frame to draw as the active window's border is drawn.
TestCase {
  name: "Theme"

  function test_a_gradient() {
    compare(Theme.activeBorder('local active_border_color = { colors = { "#D6C24A", "#EC9E3E", "#FF8D92" }, angle = 45 }\n'
                               + 'local inactive_border_color = "#38382F"\n'),
            "#D6C24A #EC9E3E #FF8D92 45deg")
    compare(Theme.activeBorder('local active_border_color = { colors = { "rgba(8a8588ee)", "rgba(e2dddcee)" }, angle = 45 }'),
            "rgba(8a8588ee) rgba(e2dddcee) 45deg")
  }

  function test_one_colour() {
    compare(Theme.activeBorder('local active_border_color = "rgb(dcd7ba)"\nlocal inactive_border_color = "rgba(595959aa)"\n'),
            "rgb(dcd7ba)")
  }

  function test_the_inactive_one_is_never_read() {
    compare(Theme.activeBorder('local inactive_border_color = "#38382F"\n'), "")
    compare(Theme.activeBorder(""), "")
  }

  function test_written_over_lines() {
    compare(Theme.activeBorder('local active_border_color = {\n  colors = { "#111111",\n "#222222" },\n  angle = 90,\n}\nhl.config({})\n'),
            "#111111 #222222 90deg")
  }
}
