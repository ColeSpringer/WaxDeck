# Contributing to WaxDeck

## Licensing

WaxDeck is licensed GPL-3.0-only (see [LICENSE](LICENSE)). Inbound
equals outbound: by opening a pull request you license your
contribution under GPL-3.0-only, and that is the whole arrangement.
There is no CLA, and you keep your copyright.

## Getting started

The quick start lives in [README.md](README.md). `make run` builds and
serves the app on http://localhost:4420; `make up` runs the full
compose stack with the streaming sidecar.

## Developing

Go 1.26, Node and Flutter (a pub workspace under `app/`), the last two at
the versions `NODE_VERSION` and `FLUTTER_VERSION` pin in
`.github/workflows/ci.yaml`. On Windows, install a native GNU make as
`make` (`winget install ezwinports.make`; MSYS2's
`mingw-w64-ucrt-x86_64-make` is the same build but installs as
`mingw32-make.exe`, and its `msys/make` is a POSIX one the recipes'
`;`-separated PATH does not suit). Recipes run through Git's bash, so
make works from any shell, and `make path-doctor` shows what a recipe's
PATH resolves - including the coreutils `link.exe` that outranks MSVC's.
The everyday loop:

```sh
make generate   # api/spec/ fragments to api/openapi.yaml, Go server stubs, Dart client
make lint test  # the gate for every change
make run        # build and serve on http://localhost:4420
make e2e        # Playwright suite against the compose stack
```

`make lint` also checks the workflows and shell scripts, with the same
pinned actionlint and shellcheck as CI; the first run on a machine
fetches both into `~/.cache/waxdeck/linters/`.

The API contract is the source of truth. Change the fragments in
`api/spec/`, run `make generate`, and commit fragments, bundle, and
regenerated code together; never hand-edit `api/openapi.yaml`,
`server/internal/api/gen.go`, or `app/packages/waxdeck_api/lib/src/gen/`. CI
fails on generated-code drift and on breaking spec changes. The gen-l10n
classes and `e2e/tests/api-types.ts` are not committed: `flutter pub get`
mints the classes (a direct `flutter test`, `run` or `build` does not, so
run it first on a fresh clone), `npm run typecheck` the types, and
`make generate` both.

The Dart client is generated from the bundle by `server/cmd/dartgen`,
steered by `app/packages/waxdeck_api/dartgen.yaml` for what the spec
cannot say about the Dart side (names, client defaults, the shape of a
method); the top comment of `server/cmd/dartgen/hints.go` documents every
key, and a run fails naming the key or schema at fault. A new tag needs
its fragment, its entry under `tags:` in `api/spec/_root.yaml` (spectral
requires it, and dartgen takes the interface's doc from it) and
`make generate`; as with any new operation, the app's test fakes then
fail to compile until they implement its methods. A string the client
resolves against the server's origin is `format: uri-reference`:
`make spec-lint` fails a property described as "Origin-relative ..."
without it, and a hand-written class cannot cover such a property.
