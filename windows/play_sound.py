"""One short sound, played and done: what `pw-play file` is on Omarchy.

The page and the deadlines' popup tick when a box is ticked; they ask a
shell line for it, and the host sends that here on Windows (qs_io.resolve).
The file comes as the page names it: a path, a path cut from a file:// URL
("/C:/Users/…", which Windows cannot open as written), or the URL itself.
"""
import sys
from urllib.parse import unquote, urlsplit


def path_of(named: str) -> str:
    if named.startswith("file:"):
        named = unquote(urlsplit(named).path)
    if len(named) > 3 and named[0] == "/" and named[2] == ":" and named[1].isalpha():
        named = named[1:]                      # "/C:/…": the slash before a drive
    return named


def main() -> int:
    if len(sys.argv) < 2 or sys.platform != "win32":
        return 2
    import winsound
    try:
        winsound.PlaySound(path_of(sys.argv[1]), winsound.SND_FILENAME | winsound.SND_NODEFAULT)
    except RuntimeError:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
