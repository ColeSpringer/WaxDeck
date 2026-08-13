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

Go 1.26 and Flutter 3.44 (a pub workspace under `app/`). On Windows,
install a native GNU make as `make` (`winget install ezwinports.make`;
MSYS2's `mingw-w64-ucrt-x86_64-make` is the same build but installs as
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

The API contract is the source of truth. Change the fragments in
`api/spec/`, run `make generate`, and commit fragments, bundle, and
regenerated code together; never hand-edit `api/openapi.yaml`,
`server/internal/api/gen.go`, or `app/packages/waxdeck_api_gen/`. CI
fails on generated-code drift and on breaking spec changes.
