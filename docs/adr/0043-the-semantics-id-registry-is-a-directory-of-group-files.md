# 43. The semantics-id registry is a directory of group files

Date: 2026-08-02

## Status

Accepted. Amends the registry path named in ADR-0016's aside; rule 8's
contract - identifiers are generated, never typed - is unchanged.

## Context

`app/semantics-ids.json` had grown to five hundred identifiers in
twenty-six groups: 2,600 lines, most of them ceremony rather than
content. A parameterless entry spent four lines saying a name and an id,
and every parameterised entry restated its placeholders in a `params`
array the id string already carried, in the same order - all 153 of
them, verified at migration. Editing the player group meant scrolling a
monolith of everything else, the same attention tax ADR-0013 removed
from the OpenAPI contract.

## Decision

The registry is `app/semantics-ids/`, one JSON file per group, read in
filename order; the filename is the group name, so the two cannot
disagree. A group file is a `doc` line and a map of constant names to
identifier strings:

    {
      "doc": "The admin console: users, settings, ...",
      "ids": {
        "adminAudit": "admin-audit",
        "auditRow": "audit-row-{id}"
      }
    }

`params` is gone: an entry with `{name}` placeholders becomes a function
in both languages, its parameters the placeholders in order of first
appearance. The typo the double entry used to catch - a placeholder
matching no declared param - stopped mattering once there is nothing to
declare: parameters are positional in both generated languages, so a
misspelled placeholder renames an argument without changing any call
site, and a malformed one (`{foo-bar}`, a stray brace) now fails
generation outright.

Groups were already alphabetical in the monolith, so filename order
reproduces the old output exactly; the generated files, the
`SemanticsIds` surface, and every call site are untouched.

Two hazards of the new shape are closed in the generator. JSON object
keys can repeat, and `jsonDecode` resolves that silently in favor of the
later entry - which here would drop a registry line without a trace - so
the generator scans the source at grammar level (a string is a key
exactly when its next token is a colon, each open object tracking its
own keys) and fails naming any key an object declares twice. And the
retired monolith path fails generation if it reappears: an agent
recreating `app/semantics-ids.json` from stale memory would otherwise
have its entries ignored.

The rest of the validation holds every string to what the emitted code
and comments can carry: constants and placeholders may not be reserved
words in either output language, ids keep to the kebab alphabet outside
their placeholder holes (a quote, backslash, or dollar would break the
generated literals), and a doc is one printable line without braces (a
newline would split its comment into bare code; a braced word would trip
the leftover-placeholder guard as a substitution that never happened).
Each of these would otherwise surface as a confusing failure inside a
generated file marked do-not-edit.
