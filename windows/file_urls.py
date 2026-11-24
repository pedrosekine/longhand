"""The page opens files elsewhere with `Qt.openUrlExternally("file://" + path)`.
On Omarchy a path begins with "/", so that is a good file:/// URL. Here it
begins with a drive: `file://C:/Users/…` reads "c" as a network host, and
`file://C:\\Users\\…` or `file://C%3A/…` do not parse at all, so Windows is
handed a link it cannot open ("Get an app to open this link"). The host takes
file URLs before Qt does and opens the file the page meant."""
import re
from urllib.parse import unquote

from PySide6.QtCore import QObject, QUrl, Slot
from PySide6.QtGui import QDesktopServices

DRIVE = re.compile(r"^/*([A-Za-z])(?::|%3A)[\\/]", re.IGNORECASE)
SOURCE = re.compile(r'source was "(.*?)"; scheme', re.DOTALL)


def local_path(url: QUrl) -> str:
    """The file a file URL from the page stands for; "" for none."""
    if url.isValid():
        host = url.host()
        if len(host) == 1 and host.isalpha():          # file://C:/… → host "c"
            return host.upper() + ":" + url.path(QUrl.ComponentFormattingOption.FullyDecoded)
        return url.toLocalFile() if url.isLocalFile() else ""
    # Qt keeps what it could not parse only in the error it gives.
    m = SOURCE.search(url.errorString())
    if not m:
        return ""
    rest = re.sub(r"^file:", "", m.group(1), flags=re.IGNORECASE)
    d = DRIVE.match(rest)
    if not d:
        return ""
    return d.group(1).upper() + ":/" + unquote(rest[d.end():]).replace("\\", "/")


class FileUrls(QObject):
    @Slot(QUrl)
    def open(self, url):
        path = local_path(url)
        # Inside a handler Qt does not call the handler again: this goes to Windows.
        QDesktopServices.openUrl(QUrl.fromLocalFile(path) if path else url)


def install() -> FileUrls:
    """Held by the caller for as long as the page runs."""
    handler = FileUrls()
    QDesktopServices.setUrlHandler("file", handler, "open")
    return handler
