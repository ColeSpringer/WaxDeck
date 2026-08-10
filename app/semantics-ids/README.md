# Semantics identifiers

The identifiers WaxDeck's UI exposes as `flt-semantics-identifier`, and
the single source for both the app's registry and the e2e suite's
constants. `make generate` emits `app/app/lib/src/shell/semantics_ids.dart`
and `e2e/tests/semantics-ids.ts` from the files here. Never write an
identifier string in a widget or a spec: add it here, regenerate, and use
the constant, so the app and the specs cannot drift apart.

One JSON file per group, read in filename order; the filename is the
group name. Each file:

```json
{
  "doc": "What the group covers, in one line.",
  "ids": {
    "adminAudit": "admin-audit",
    "auditRow": "audit-row-{id}"
  }
}
```

An id with `{name}` placeholders becomes a function in both languages,
its parameters the placeholders in order of first appearance. Entries
stay sorted by constant name.

Renaming an id is a contract change: the spec that drives it moves in the
same commit (CLAUDE.md rule 8). The generator
rejects duplicate names, duplicate JSON keys, reserved words, and
malformed placeholders.
