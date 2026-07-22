# 13. The contract is authored as fragments and bundled

Date: 2026-07-22

## Status

Accepted. Amends the authoring mechanics of ADR-0001; the contract-first
rule itself is unchanged.

## Context

The contract had grown into a fifteen-thousand-line `api/openapi.yaml`.
Every change meant navigating one monolith, and an agent editing the
uploads surface paid attention tax on fourteen thousand lines of
everything else.

Splitting the spec with cross-file `$ref`s is the textbook answer and
was rejected. The contract has six consumers — `oapi-codegen`, the
dart-dio generator, spectral, oasdiff, drift-check, and the CI probe
that reads the spec out of the base ref with `git show` — and their
support for multi-file documents is uneven: oapi-codegen treats
external references as cross-package imports unless each one is mapped
away, the spectral config addresses schemas by bundle path, and the
oasdiff gate diffs a single file fetched from git history. Six
consumers would have needed six migrations, each with its own failure
modes.

## Decision

The spec is authored as fragment files in `api/spec/` and assembled
into `api/openapi.yaml` by `server/cmd/specbundle`, which runs first in
`make generate`. Every consumer keeps reading the bundled file, which
stays committed; none of them changed at all.

### Fragment layout

One file per API tag (`admin.yaml`, `uploads.yaml`, ...) holding that
domain's paths and the components only it uses, plus three special
files:

- `_root.yaml` — the preamble: `openapi`, `info`, `servers`, `tags`,
  `security`. Nothing else may appear here.
- `_shared.yaml` — components referenced across domains: the error
  model, the shared responses and parameters, and cross-domain entity
  summaries (`ItemSummary`, `MediaType`, `ChapterMark`).
- `events.yaml` — the WebSocket frame DTOs (`api/events.md`), which no
  REST path references.

Ownership rules, applied when a component's home is ambiguous: an
entity lives with the domain that defines it even when others reference
it (`User` with users, `ToolTask` with tools); `sync` mirrors other
domains' state and never claims ownership of what it mirrors; all of
`components.securitySchemes` lives in `auth.yaml`, because security
requirements reference schemes by name, not `$ref`, so usage analysis
cannot see them. Fragments use internal `#/components/...` references
exactly as before — references resolve in the bundle, so a fragment is
not independently a valid OpenAPI document, and no `$ref` rewriting
exists anywhere.

### Bundling is textual, verified semantically

specbundle moves each fragment's section bodies into the bundle
verbatim — never re-encoded — so hand-written formatting, comments, and
deliberate quoting (the YAML 1.1 `"off"` trap) survive byte for byte.
Correctness does not rest on the carving: the tool re-parses the
assembled bundle and deep-compares it against the merged fragment
documents, and any mismatch is a hard error before the file is
written. Duplicate paths or component names across fragments, unknown
top-level keys, and unknown component kinds are errors. A leading
comment block in a fragment is a file header and is dropped from the
bundle.

The bundle opens with a generated-file banner and is never hand-edited.
`make drift-check` already regenerates and diffs the spec, so a stale
bundle — fragments edited without `make generate` — fails CI through
the existing gate.

## Consequences

- Editing the contract means editing a fragment (largest is ~1,400
  lines) and running `make generate`; fragments, bundle, and generated
  code are committed together.
- The migration itself was provably lossless: the first bundle
  deep-equals the old monolith, regenerated `gen.go` was byte-identical,
  and oasdiff reported no changes against it.
- oasdiff, spectral, CI, and both generators are untouched; the
  `git show BASE:api/openapi.yaml` probe keeps working across the
  migration boundary because the bundle stays committed at the same
  path.
- A new path goes in the fragment matching its tag; a new shared
  component goes in `_shared.yaml`; specbundle's duplicate detection
  arbitrates collisions.
