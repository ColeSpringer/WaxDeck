# ADR-0060: Where the brand comes from

Status: accepted

## Context

Until now the visual identity was a placeholder: a hand-parameterised
needle mark drawn by a `CustomPainter`, a traced wordmark SVG, and a set
of app icons `tools/generate-brand.py` composed from those parts. The
official logo now exists - an illustration of a candle burning against a
record, delivered as one raster image - and every surface that carried
the placeholder has to carry it instead: app icons on five platforms,
tray glyphs in three platform conventions, the web boot screen, the
in-app wordmark, the README.

The delivered artwork is a flat photograph-like raster on its own paper
ground, not a layered design source. There is no vector, no alpha
channel, and no separate wordmark cut. Whatever derives from it has to
be derived by measurement and image processing, and there are a lot of
derivatives: forty-odd files today, plus whatever the next platform
wants. Deriving them by hand in an editor would make every one of them
a small unrepeatable decision.

## Decision

The shipped master is the single source of truth. It lives at
`docs/brand/waxdeck.png`, and `make brand` (`tools/generate-brand.py`)
derives every other brand artifact from it: the README lockup, the
emblem chips, the app icons and `.ico`, the adaptive-icon layers, the
tray glyphs, the boot emblem inlined into `web/index.html`, the paper
grain. Nothing brand-shaped is authored anywhere else; changing the
brand means replacing the master and re-running the script. The run is
deterministic - two runs produce byte-identical files - so the diff of a
rerun is empty unless the master or the script changed.

The script stays on the Python standard library: PNG decode and encode,
the resampler, and the compositor are written out rather than imported.
`tools/` carries no pip dependencies today, and pulling in Pillow for
four transforms would trade a page of understandable arithmetic for an
external dependency whose resampling and quantisation choices move
between versions - the wrong trade for artifacts whose whole value is
being reproducible.

The regions the derivatives crop are measured constants in the script,
not detected at runtime. The emblem boxes are centred on the record
disc (its centre and radius are measured constants too), deliberately
not on the ink bounding box: the tonearm trails a faint tail to the
right, and centring on ink visibly off-centres the disc everyone
actually sees.

Two treatments cover every surface:

* **The chip** - the master's emblem region on its own paper, rounded
  corners - is the app icon everywhere, and is also the in-app mark
  (`WaxWordmark`). The emblem's ink is dark, so a keyed silhouette dies
  on dark surfaces, and tinting the artwork to rescue it would make it
  a different picture per theme; the chip keeps the artwork's own
  colours on every ground. In-app, only the logotype text tints.
* **The keyed silhouette** serves the surfaces that require a single
  colour plus alpha: tray glyphs, the macOS template image, Android's
  monochrome launcher layer and status icon. The key is warmth (red
  minus blue), not luminance and not distance-from-paper: the grooves
  are paper-coloured and shred a luma key into arcs, while the candle
  and flame are the only warm region of the image. The disc itself is
  filled from the measured geometry, and dark ink (the tonearm) is
  admitted outside the disc, so the silhouette reads as
  candle-in-record down to 16 px.

Playback state on the tray is a play or pause badge composited over the
glyph with a knocked-out halo, replacing the old mark's
needle-deflection animation as the state signal. The colour Linux tray
variant gives the badge the amber accent; the single-colour variants
carry it in their one colour.

Outputs are size-audited: the encoder picks an exact palette when the
image fits 256 colours and posterised truecolour otherwise, with
adaptive per-row PNG filtering. That is what keeps a photographic
master's forty derivatives from weighing megabytes, and it is why the
boot emblem can afford to be inlined as base64 between
`<!-- brand:boot-emblem -->` markers rather than fetched.

If a transparent-background export of the emblem ever materialises from
the original design source, saved as
`docs/brand/waxdeck-emblem-alpha.png`, the script auto-detects it and
uses its alpha as the exact silhouette key in place of the warmth
keyer. Nothing depends on it; it is an upgrade path, not a requirement.

## Consequences

* The repo's no-binary-media rule gets its one deliberate exception:
  the rule exists so test media is synthesized rather than committed,
  and the master is not media under test - it is a source file, the
  same way a font is. `docs/brand/waxdeck.png` (~3 MB) is committed
  because everything derives from it; `lockup-640.png` and
  `emblem-512.png` are committed although regenerable, because the
  README and the Discord portal consume them as files, not through the
  pipeline.
* `make brand` is safe to re-run at any time; a clean diff is the
  expected result. It stays out of `make generate` because it is slow,
  and out of CI because its output is committed.
* A brand change is reviewed the way code is: replace the master, run
  the script, read the diff, and eyeball
  `tools/.cache/brand-contact-sheet.png`, which renders every
  derivative on light and dark grounds.
* The measured constants (crop boxes, disc geometry, warmth
  thresholds) are coupled to this master. A new master means
  re-measuring them - the script's docstrings say which and how - not
  discovering by artifact review that the old numbers silently cropped
  the wrong region.
* The design-system goldens moved with the mark, in the same change
  (both trees; ADR-0058). Because the wordmark now decodes an image
  asset, golden captures and the share-card export precache it before
  drawing; a future surface that captures a single frame with the mark
  in it inherits that obligation (`WaxWordmark.markImage`).
