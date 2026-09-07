# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **A re-ask TTL on a missed art marker.** The artist-art and
  auxiliary-art backfills mark a target nothing answered for, and the
  marker is a plain existence check with no expiry: an artist Deezer
  does not hold today is never asked about again, however long the
  catalog runs. Providers gain images, so "nothing found once" is not a
  durable fact the way a match is. Wanted: an age on the marker, so a
  walk re-asks a miss after some window (a config knob, or a fixed one
  in the tens of days) without a forced run re-searching everything.
  Shipped workaround: none that is cheap - a forced enrichment run
  re-asks every target, matched ones included, so WaxDeck documents the
  rule in the curation doc rather than working around it.

- **A barcode on the release-rung art request.** The release-rung art
  request carries the group's MBID, title and artist and no printed
  identifier, so a provider keyed on one cannot tell which pressing is
  being asked about - and a picture chosen by title search on that rung
  is the wrong edition's as often as not, which is the failure the rung
  exists to avoid. The fields walk already carries `Barcode` on the same
  target for exactly this reason. Wanted: `Barcode` filled on the
  release-rung art request too, so a UPC-keyed provider can answer for
  the pressing rather than for the record. Shipped workaround: Deezer
  declines art on that rung and answers only its fields, so a
  per-edition cover comes from the Cover Art Archive alone.

## WaxTap

- **Enrich overwrites an entry's listing fields with whatever the lookup
  answered, zeros included.** `enrichEntries` assigns `Title`, `Author`
  and `Duration` from the fetched `Video` unconditionally, so an
  `InfoBasic` answer for a live item or a premiere - duration 0 - clobbers
  the listing's own duration, and a consumer overlaying the two has no
  listing value left to fall back to. Wanted: the refresh to keep a
  listing field where the fetched one is empty or zero, the way a
  consumer's own overlay would. Shipped workaround: none; WaxDeck's
  overlay guards are kept but cannot restore what the refresh already
  replaced, and a live entry's duration reaches the catalog as 0.

## WaxSeal

(nothing outstanding)

## WaxFlow

- **The fMP4 FLAC sample entry declares 16 bits whatever the stream
  holds.** `container/mp4/seg.go` `audioSampleEntry` writes the
  AudioSampleEntry `samplesize` as a constant 16 for every codec, on the
  grounds that the codec config box is authoritative. Chromium's MP4
  parser does not agree for FLAC: it refuses the init segment unless
  that field equals `STREAMINFO.bits_per_sample`
  (`CHUNK_DEMUXER_ERROR_APPEND_FAILED: Failure parsing MP4: FLAC
  AudioSampleEntry sample size mismatches FLACSpecificBox STREAMINFO
  sample size`), so every FLAC rendering at a depth other than 16 is
  unplayable over Media Source Extensions in every Chromium-based
  browser. A timeline reaches that depth easily: any lossy member decodes
  to float, the envelope goes float, and `waxflow.go`'s FLAC `adjust`
  quantizes an unrequested depth to 24 - so a queue mixing one MP3 into
  a FLAC album renders as 24-bit FLAC and the browser refuses the whole
  stream at the first append. Wanted: `samplesize` written from the
  STREAMINFO for FLAC (the ISOBMFF FLAC encapsulation spec says the two
  shall agree). Shipped workaround: WaxDeck asks for `bits=16` on every
  FLAC timeline render, which makes the two fields agree at the cost of
  quantizing a lossless 24-bit source to 16 on that path; the request
  comes out again when this lands.

## WaxLabel

(nothing outstanding)
