# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **Unicode-aware folding in `model.SortKey`.** Every name sort and
  index bucket rides the stored `sort_key`, and its derivation is
  deliberately ASCII-level: lowercase, strip leading articles, pad
  digit runs, compare BINARY. The function's own comment names the
  extension point - "Unicode collation can be added here without
  changing callers or the stored column" - and WaxDeck would like it
  taken: diacritic folding and default-table weights, so "Édith"
  files under E and non-Latin names interleave by something better
  than codepoint order. Locale-independent only; the stored column is
  one ordering for all users, so per-locale tailoring (pinyin for one
  account, radical order for another) is out of scope. The change
  means recomputing stored keys, and `sortKeyDrift` in the sqlite
  store already counts stale ones, so the detection half exists.
  Shipped workaround: none needed - ASCII folding plus codepoint
  order stands, which groups accented and non-Latin names after "z"
  instead of interleaving them.

## WaxLabel

- **`SaveBack` holds the source open across its own rename, so an
  in-place save can never succeed on Windows.** `saveBack` in
  `destination.go` opens the file and keeps it with `defer src.Close()`
  while `writeAtomic` renames the temp onto that same path. POSIX does
  not mind; Windows refuses, because Go's `os.Open` does not ask for
  `FILE_SHARE_DELETE` and `MoveFileEx` then answers
  ERROR_ACCESS_DENIED. Closing the source before the rename would fix
  it - the planned bytes are in the temp by then. Confirmed with a
  five-line reproduction.
  Shipped workaround: none available, since the handle is internal to
  `saveBack`. Every tag write on Windows fails as "writing tags to
  <file>: rename ... Access is denied", taking book merge, book split,
  cue split, metadata write-back and acquisition provenance with it.
  Windows is not a shipped server target, but it is a supported dev
  box.
