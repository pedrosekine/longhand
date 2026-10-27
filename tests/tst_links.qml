import QtQuick
import QtTest
import "../plugin-page/Links.js" as Links
import "../plugin-page/Rows.js" as Rows

// Links: what a note points at, and where it is, by Obsidian's rules.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_links.qml
Item {
  TestCase {
    name: "Links"

    function test_an_image_line() {
      compare(Links.imageLine("![[Pasted image 2022.png]]").target, "Pasted image 2022.png")
      compare(Links.imageLine("![[shot.png|300]]").width, 300)
      compare(Links.imageLine("![[shot.png|300x200]]").width, 300)
      compare(Links.imageLine("![[shot.png|a caption]]").alt, "a caption")
      var md = Links.imageLine("![a cat](2022-01-01.assets/cat%20one.png)")
      compare(md.target, "2022-01-01.assets/cat one.png", "a markdown path is decoded")
      compare(md.alt, "a cat")
      compare(md.wiki, false)
      compare(Links.imageLine("![x|250](a.jpg)").width, 250)
      compare(Links.imageLine("![[A note]]"), null, "an embedded note is not an image")
      compare(Links.imageLine("text ![[a.png]]"), null, "only a line that is the image")
      compare(Links.imageLine("![](https://example.org/a.png)"), null, "nothing fetched from the web")
    }

    function test_links_in_a_line() {
      var l = Links.inLine("see [[Session 1|the first]] and [[Notes#Themes]] or [web](https://x.org) [[#Top]]")
      compare(l.length, 4)
      compare(l[0].target, "Session 1")
      compare("see [[Session 1|the first]]".substring(l[0].inner[0], l[0].inner[1]), "the first")
      compare(l[1].target, "Notes")
      compare(l[1].heading, "Themes")
      compare(l[2].url, "https://x.org")
      compare(l[3].target, "")
      compare(l[3].heading, "Top")
      var md = Links.inLine("[the plan](../Plans/My%20Plan.md#Week)")[0]
      compare(md.target, "../Plans/My Plan.md")
      compare(md.heading, "Week")
      compare(Links.at(l, l[0].at), null, "a link's edge is the words around it")
      compare(Links.at(l, l[0].at + 3).target, "Session 1")
    }

    function test_resolving() {
      var idx = Links.index(["human/Studies/IT-U/Session 1.md", "human/Archive/Session 1.md", "human/Reference/People/Ada.md",
                             "human/_Attachments/shot.png", "human/Daily/2022-01-01.assets/cat one.png", "human/Daily/2022-01-01.md"])
      compare(Links.resolve(idx, "Session 1", "human/Studies/IT-U/Other.md", true), "human/Studies/IT-U/Session 1.md",
              "the note's own folder first")
      compare(Links.resolve(idx, "Session 1", "human/Daily/2026-10-27.md", true), "human/Archive/Session 1.md",
              "else the shortest path")
      compare(Links.resolve(idx, "ada", "x.md", true), "human/Reference/People/Ada.md", "a name, case aside")
      var rooted = Links.index(["Ada.md", "human/Reference/People/Ada.md"])
      compare(Links.resolve(rooted, "Ada", "human/Reference/People/x.md", true), "Ada.md", "the vault's root first, as Obsidian")
      compare(Links.resolve(idx, "People/Ada", "x.md", true), "human/Reference/People/Ada.md", "a partial path ending a real one")
      compare(Links.resolve(idx, "shot.png", "human/Daily/2026-10-27.md", true), "human/_Attachments/shot.png", "an embed by name")
      compare(Links.resolve(idx, "2022-01-01.assets/cat one.png", "human/Daily/2022-01-01.md", false),
              "human/Daily/2022-01-01.assets/cat one.png", "a markdown image, beside its note")
      compare(Links.resolve(idx, "Nowhere", "x.md", true), "", "unresolved")
      compare(Links.resolve(idx, "../../../etc/passwd", "human/x.md", false), "", "never out of the vault")
    }
  

    function test_tables_and_image_rows() {
      var rows = Rows.derive("Before\n| Week | Topic |\n|---|:---:|\n| 1 | a \\| b |\n| 2 | c |\nAfter\n![[shot.png]]\n| not | a table |")
      compare(rows.map(function (r) { return r.kind }).join(","), "plain,table,table,table,table,plain,image,plain")
      compare(rows[3].tableRow, 2)
      compare(rows[3].tableStart, 1)
      compare(rows[3].tableLen, 4)
      compare(Rows.cells(rows[3].raw).join("/"), "1/a | b", "an escaped pipe stays in its cell")
      compare(Rows.aligns(rows[2].raw).join(","), "left,center")
      compare(Rows.aligns("|:--|--:|:-:|").join(","), "left,right,center")
      compare(rows[7].kind, "plain", "a line of cells with no line of dashes under it is words")
    }
  }
}
