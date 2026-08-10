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

Go 1.26 and Flutter 3.44 (a pub workspace under `app/`). The everyday
loop:

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
