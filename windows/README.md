# Longhand on Windows — spike

A host that stands in for `omarchy-shell`, so `plugin-page/` loads on Windows
with nothing in it changed. Started 2026-11-23 to answer one question: does
`Page.qml` load, draw and take keys under a shim? It does (`first-run.png`).

Nothing here is used on Omarchy, and nothing outside `windows/` was touched.

## Run it

Python 3.13 and `pip install PySide6` (6.12, the Qt the page is written for);
Git for Windows for the page's few `sh`/`find` calls.

```powershell
.venv\Scripts\python windows\longhand_host.py --sandbox $env:TEMP\longhand-try   # a throwaway vault
.venv\Scripts\python windows\longhand_host.py                                    # your own ~/.config/longhand/config.json
.venv\Scripts\python windows\longhand_host.py --overlay                          # the unpinned shape
```

`--sandbox DIR --check out.json --shot out.png` types into the note as a
keyboard would, saves, reads the file back, writes into it from outside and
says what the page did.

## What stands in for what

| The page imports | Here |
|---|---|
| `Quickshell.Io` — `Process`, `StdioCollector`, `SplitParser`, `FileView`, `FileViewError` | `qs_io.py`, on QProcess and plain files |
| `Quickshell` — the singleton, `PanelWindow`, `FloatingWindow` | `shim/Quickshell/`, on Qt Quick's `Window` |
| `Quickshell.Wayland` — layer-shell names | `qs_wayland.py`: accepted, not acted on |
| `qs.Commons` — `Style`, `Color`, `Border`, `Util` | `shim/qs/Commons/`: Windows' light/dark and accent, live |
| `qs.Ui` — `BorderSurface`, `TextField`, `PanelToolTip` | `shim/qs/Ui/` |
| scripts by name or in `~/.local/bin` | `qs_io.resolve`: the repo's own, run by Python or Git's bash |
| `fcntl.flock` | `pyshim/fcntl.py` |

## Known, not done

- The keys are not in the note on first open until `focusCenter()` runs: a
  hidden `focus: true` item holds them. Whether Omarchy wins this by timing
  is not checked.
- `hyprctl` (pointer follows the pane, raise, key capture) has no stand-in.
- `pomo` is bash: it reads under Git's bash, and cannot write (no `flock`).
- No global key, no tray, no bar widgets, no installer.
- Borders are flat (no gradient ring); the page's prose face is named in the
  sandbox config (`Segoe UI Variable Text`), since Windows has none of the
  faces the page looks for.
