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
