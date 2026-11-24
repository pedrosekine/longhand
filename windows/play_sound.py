"""One short sound, played and done: what `pw-play --volume=0.6 file` is on
Omarchy, and never while notifications are silenced.

The page and the deadlines' popup tick when a box is ticked; they ask a
shell line for it, and the host sends that here on Windows (qs_io.resolve).
`pomo` rings its bell through here too. The file comes as the page names
it: a path, a path cut from a file:// URL ("/C:/Users/…", which Windows
cannot open as written), or the URL itself.

    play_sound.py [--volume 0.6] FILE

Windows plays a file at the system's own volume; the shell plays these at
six tenths of it, so the samples are scaled here before Windows has them.
Silenced is Windows' Do Not Disturb (Focus assist: priority only or alarms
only) and its own quiet times — a presentation, the hours after an update —
as the shell asks `omarchy-shell notifications isDnd` (Settings: "never
while notifications are silenced").
"""
from __future__ import annotations

import io
import sys
import wave
from array import array
from urllib.parse import unquote, urlsplit

VOLUME = 0.6                                  # pw-play --volume=0.6, the shell's
# Windows' "Focus assist" profile, as the shell's own toggle publishes it:
# 0 off, 1 priority only (Do Not Disturb), 2 alarms only.
WNF_SHEL_QUIETHOURS_ACTIVE_PROFILE_CHANGED = 0x0D83063EA3BF1C75
QUNS_PRESENTATION_MODE, QUNS_QUIET_TIME = 4, 6


def path_of(named: str) -> str:
    if named.startswith("file:"):
        named = unquote(urlsplit(named).path)
    if len(named) > 3 and named[0] == "/" and named[2] == ":" and named[1].isalpha():
        named = named[1:]                      # "/C:/…": the slash before a drive
    return named


def silenced() -> bool:
    """Whether Windows has notifications silenced just now."""
    if sys.platform != "win32":
        return False
    import ctypes
    try:
        name = ctypes.c_uint64(WNF_SHEL_QUIETHOURS_ACTIVE_PROFILE_CHANGED)
        stamp, size, profile = ctypes.c_ulong(0), ctypes.c_ulong(4), ctypes.c_uint32(0)
        if ctypes.WinDLL("ntdll").NtQueryWnfStateData(ctypes.byref(name), None, None, ctypes.byref(stamp),
                                                       ctypes.byref(profile), ctypes.byref(size)) == 0 \
                and size.value >= 4 and profile.value != 0:
            return True
    except (OSError, AttributeError):
        pass
    try:
        state = ctypes.c_int(0)
        if ctypes.windll.shell32.SHQueryUserNotificationState(ctypes.byref(state)) == 0 \
                and state.value in (QUNS_PRESENTATION_MODE, QUNS_QUIET_TIME):
            return True
    except (OSError, AttributeError):
        pass
    return False


def quieter(path: str, volume: float) -> bytes | None:
    """The file's sound at `volume` of its own, as a WAV in memory; None
    when it is not 16-bit PCM (then it is played as it is)."""
    try:
        with wave.open(path, "rb") as w:
            params = w.getparams()
            frames = w.readframes(w.getnframes())
    except (OSError, wave.Error, EOFError):
        return None
    if params.sampwidth != 2:
        return None
    samples = array("h")
    samples.frombytes(frames[: len(frames) - len(frames) % 2])
    if sys.byteorder != "little":
        samples.byteswap()
    v = max(0.0, min(1.0, volume))
    samples = array("h", (int(s * v) for s in samples))
    if sys.byteorder != "little":
        samples.byteswap()
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setparams(params)
        w.writeframes(samples.tobytes())
    return out.getvalue()


def main(argv: list[str]) -> int:
    volume = VOLUME
    if len(argv) >= 2 and argv[0] == "--volume":
        try:
            volume = float(argv[1])
        except ValueError:
            pass
        argv = argv[2:]
    if not argv or sys.platform != "win32":
        return 2
    if silenced():
        return 0
    import winsound
    path = path_of(argv[0])
    data = quieter(path, volume)
    try:
        if data is not None:
            winsound.PlaySound(data, winsound.SND_MEMORY | winsound.SND_NODEFAULT)
        else:
            winsound.PlaySound(path, winsound.SND_FILENAME | winsound.SND_NODEFAULT)
    except RuntimeError:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
