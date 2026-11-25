"""The page's `Qt.openUrlExternally("file://" + path)` on Windows: a path
that begins with a drive is the file it names (windows/file_urls.py), not a
network host or a link Windows has no app for. On Omarchy the page's paths
begin with "/" and Qt opens them itself; there is nothing to test there.

Run: python tests\\run_all.py file_urls
"""
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    if os.name != "nt":
        print("skip: file:// links by drive are Windows' (on Omarchy Qt opens the page's paths itself)")
        return 0
    sys.path.insert(0, str(ROOT / "windows"))
    from PySide6.QtCore import QUrl
    import file_urls

    def path(s):
        return file_urls.local_path(QUrl(s))

    # What the page builds, with a vault at C:/Users/x/My Vault (Page.qml).
    check(path("file://C:/Users/x/My Vault/projects/tas/docs/2026-11-17 Does Time Slow Down.pdf")
          == "C:/Users/x/My Vault/projects/tas/docs/2026-11-17 Does Time Slow Down.pdf",
          "file://C:/… is the file on C:, not a host named c")
    check(path("file://C:\\Users\\x\\docs\\a b.pdf") == "C:/Users/x/docs/a b.pdf",
          "file://C:\\… (a path with backslashes, which Qt does not parse) is still the file")
    check(path("file://C%3A/Users/x/My%20Vault/a%25b.docx") == "C:/Users/x/My Vault/a%b.docx",
          "file://C%3A/… (each part encoded, as the page's vault links are) is the file, decoded once")
    check(path("file://d:/notes/a.md") == "D:/notes/a.md", "any drive")
    check(path("file:///C:/Users/x/a.pdf") == "C:/Users/x/a.pdf", "a well-formed file:/// URL is left as Qt reads it")
    check(path("file://server/share/a.pdf") == "//server/share/a.pdf", "a share keeps its server")
    check(path("https://example.org/") == "", "not a file: nothing")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
