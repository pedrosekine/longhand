# Longhand logo — source of truth

**Use the A2 seal. The active asset is its “Open cuts” refinement.**
For logo placement, exports, and theme integration, start with the assets below.
The files under `explorations/` are historical references.

![Current launcher logo](../../launcher/longhand.svg)

## STATUS — 17 October 2026

| Decision | Status |
| --- | --- |
| Chosen design | **A2**, explicitly chosen by Pedro in round two |
| Active refinement | **Open cuts**, selected by the agent for the authorised launcher trial; further optical tuning remains possible |
| Canonical identity | `a2-open-cuts`; use the current assets below for new work |
| Launcher | Installed through the existing hicolor symlink to `launcher/longhand.svg` |
| Page header | **Placed 2026-10-17**: the seal hangs before the date and opens or closes the sidebar (calendar, projects, keys, settings); drawn from the master path by `plugin-page/LogoMark.qml` |
| Other product placements | Future work; no rollout across the bar or agent UI yet |
| Theme adaptation | In the page, yes: the seal takes the theme's colours (faint, the accent on hover, the foreground while the sidebar is open). The launcher still has fixed colours |
| Verification | SVGs rendered at 16, 24, 32, 48, 64, and 256 px; installed bytes match. Rechecked 2026-10-17 at 16–64 px on dark and light: clear from 24 px; at 16 px the five cuts nearly close into a plain flower. The live launcher itself is still unseen |

The user chose the design; the agent selected its small refinement for trial.
Original A2 is an approved historical ancestor, not a second active logo.

## Assets to use

| Resource | Use |
| --- | --- |
| [Canonical mark](../../launcher/longhand-mark.svg) | Transparent, single-colour vector; authoritative silhouette for new placements and colour variants |
| [Launcher icon](../../launcher/longhand.svg) | Same silhouette, cream on a charcoal tile; current desktop asset |
| [Desktop entry](../../launcher/longhand.desktop) | Launcher integration; resolves the `longhand` icon name |
| [Historical comparison](explorations/round-three/comparison.png) | Explains the finishing decision; contains alternatives and is not an export source |

Both canonical SVG roots identify themselves with `data-longhand-logo="a2-open-cuts"`
and `data-longhand-status="canonical"`. Historical SVGs carry
`data-longhand-status="historical-reference"` instead.

Reuse the master's path for derivatives. The launcher contains that same path
with a scale/translation and a separate rounded-square tile. The tile is a
presentation treatment, not part of the seal. Proof images and historical
generators are not sources for current product exports.

## Identity and placement

A minimal maker's signature for a personal writing tool: five broad lobes,
five short rounded recesses, upright and symmetrical. The Montblanc reference
inspired the writing-instrument association and restraint, not a source asset.
The five parts have no assigned symbolic meaning.

Keep the contour, orientation, and proportions consistent. Scale uniformly and
retain breathing room. Colour and surrounding surface can follow the context.
The serif lettering in proof sheets was contextual; no brand typeface or
wordmark has been selected.

Use the seal to identify Longhand itself. It should not become an agent-reply,
notification, urgency, or task-status indicator. Repeated product placements
are intended; their exact locations remain open.

**In the page (2026-10-17):** the seal hangs in the margin before the
header's date, so the date stays in line with the writing, at about the
date's height. It is the visible door to the sidebar — where the calendar,
projects, keys and settings live, kept out of the main pane — and clicking it
opens or closes the sidebar, nothing else; "back to today" beside the date is
the way to today. It is drawn from the master's path (`LogoMark.qml`,
multisampled; `tests/test_brand.py` fails if the path drifts) and coloured
by the page from the Omarchy theme. Clicks are counted as `seal` in the
usage log, so the stats can say whether the mark is found.

## Colour and theme adaptation

**Current:** the master uses `currentColor`; the launcher has explicit fills
`#f2efe8` (mark) and `#26262b` (tile). SVG format alone does not make an icon
theme-aware. A separately loaded SVG does not inherit its host's CSS colour;
QML also needs an explicit rendering/tinting approach. Supply a concrete fill
or render the vector through the product's colour mechanism.

**Follow-up direction, not implemented:** derive a shared logo colour from the
Omarchy accent. Check contrast against the actual surface, adjust lightness
when necessary, and fall back to the theme's foreground. Neutral themes may
intentionally yield a neutral mark. Window-frame highlights and the palette
accent are different roles; do not assume they are interchangeable.

Longhand watches the palette in [ThemeColors.qml](../../plugin-page/ThemeColors.qml).
In the installed Omarchy version, palettes live under
`~/.local/state/omarchy/current/theme/`, and changes invoke the user `theme-set`
hook. Launcher adaptation needs a generated runtime icon plus verified cache
invalidation. Keep generated theme colours in user runtime state and canonical
geometry in the repo. Test live theme changes, light/dark surfaces, and caching
before describing adaptation as complete. Recheck installed Omarchy interfaces
when implementing it.

## Export and verification

Use canonical SVGs directly where supported. Raster images are derivatives,
never replacement masters. For example, from the repo root:

```bash
rsvg-convert launcher/longhand.svg -w 256 -h 256 -o /tmp/longhand-icon.png
```

For the transparent mark, supply an explicit colour through the renderer or
SVG fill. Preview it against its intended background. After rendering changes,
compare the silhouette with the master and inspect 16, 24, 32, and 48 px on
light/dark surfaces. Check contrast against the actual surface. For desktop
integration, verify the resolved icon file and live refresh behaviour.

## History and future decisions

[The exploration index](explorations/README.md) records each study's disposition.
Proof sheets, historical SVG snapshots, and the former page icon are reference
material. Generators there rebuild studies only; they do not publish a logo.

Update this document and the canonical assets together when a later decision
changes the active logo. Record durable user decisions in the vault's Longhand
project record as required by the working-environment rules.
