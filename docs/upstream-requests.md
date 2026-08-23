# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **`NormalizeFormat` does not fold `image/pjpeg`.** The fold table
  covers the spellings older servers send - `jpg`, `jpe`, `x-png`,
  `x-bmp`, `x-ms-bmp`, `x-tiff`, `heif` - and progressive JPEG's legacy
  media type is the one missing from that family. A remote answering
  `image/pjpeg` therefore stores under `pjpeg`, and every surface that
  derives a media type from the stored token then serves `image/pjpeg`.
  One line beside `case "jpg", "jpe"` closes it.

  Workaround today: none is needed, which is why this is one line rather
  than an entry with a table behind it. The declared format is consulted
  only for bytes `art.Describe` could not read, and a progressive JPEG
  decodes with the standard library like any other - so the fold is
  reachable only for a truncated one, which has no good answer anyway.
  WaxDeck deleted its own `imageFormat` fold (which did cover `pjpeg`)
  rather than keep a second normalizer beside the facade's.

- **A sized resolve can answer with bytes the caller cannot paint.**
  `ResolveArt` serves the source unscaled when it already fits the box
  (`size <= 0 || longest <= size`), which is right for bytes, and wrong
  for a source in a format the asking client has no decoder for. TIFF is
  the live case now that it decodes: a 900-pixel TIFF cover thumbnails
  correctly into a grid tile and comes back raw at the player hero's
  1024 rung, so the same picture draws in one place and not the other.
  Answering a positive `size` with a re-encode whenever the source
  format is outside the set a browser paints - or exposing the choice on
  the call - would make a sized request mean "something I can draw".

  Workaround today: none. WaxDeck could call `art.Thumbnail` itself for
  those formats, but that is a second thumbnail path with no cache
  behind it, which is worse than the inconsistency. The set of stored
  formats this reaches is small (TIFF, and the exotics that were never
  paintable), and every one of them is a cover somebody put there by
  hand.


## WaxLabel
