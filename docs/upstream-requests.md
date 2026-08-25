# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **Album rename-in-place.** Editing a release-keying field (`album`,
  `album_artist`, `year`) on an unidentified album's members re-resolves
  each member's entities in the edit transaction, so the release regroups
  onto a fresh `al-` pid and the old entity is left as a ghost until the
  orphan GC sweeps it. Track pids and playlist membership survive, but
  everything hung on the album pid - entity curation, artwork and its pin,
  a client's open route - is orphaned. Wanted: a facade verb that renames
  a release in place (rewrite the members' keying fields and the entity's
  identity together, keeping the pid and moving curation/art), or an
  album-key recompute that reuses an existing entity row when every member
  moves at once. Shipped workaround: the release workbench is built to the
  regroup - the bulk-edit response reports the album the edited members
  landed on (`resultingAlbumPid`), the rewrite section warns before it
  writes, and the workbench follows the tracks to the new entry -
  and `TestBulkEditAlbumFieldsRegroupsTheRelease` pins the behavior it is
  built to. Entity curation, artwork and pins on the old entity are still
  orphaned by the move, which is what rename-in-place would keep.

## WaxLabel
