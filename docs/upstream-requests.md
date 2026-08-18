# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **Artwork has no provenance row.** `model.ArtImage` is data, format,
  dimensions and a hash, and `model.FieldProvenance` covers scalar fields
  only, so a cover written by an enrichment provider is indistinguishable
  from one read out of the file's tags. WaxDeck wants to mark art it
  fetched from a third party as such - a small source mark under the
  cover, the same one radio would draw (`docs/deferred-work.md`). A
  provider id beside the art, or an artwork row in the provenance table,
  would carry it. Workaround today: nothing is marked, and the only
  provenance any surface shows is the metadata editor's field table.

## WaxLabel
