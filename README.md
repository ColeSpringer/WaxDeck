<p align="center">
  <img src="docs/brand/lockup-640.png" width="360" alt="WaxDeck: a candle burning against a record">
</p>

# WaxDeck

Self-hosted player, library manager, and metadata completer for **music, podcasts, and
audiobooks**.

## Layout

| Path | What |
|---|---|
| `api/` | The contract: `spec/` (hand-edited fragments, one per API domain) bundled into `openapi.yaml` (REST, `/api/v1`) + `events.md` (WebSocket envelope). First artifact, single source of truth: server handlers and the Dart client are generated from it. |
| `server/` | Go module. `oapi-codegen` strict-server over stdlib `net/http`; embeds the Flutter web build. |
| `app/` | Flutter workspace (melos/pub workspace): `packages/waxdeck_api_gen` (generated dio client), `packages/waxdeck_api` (hand-written repository layer over it), `app` (adaptive shell). |
| `deploy/` | `compose.yaml` + profiles, `Dockerfile`, `.env.example`. |
| `fixtures/` | Fixture *generator* that synthesizes tiny media at test-setup (WaxFlow codec packages + optional ffmpeg). No binary media in git. |
| `e2e/` | Compose harness + Playwright suite. |
| `tools/` | Codegen configs and scripts (oapi-codegen, openapi-generator, spectral, oasdiff). |
| `docs/adr/` | Architecture decision records. |

## Quick start (development)

```sh
make generate   # spec to Go server stubs + Dart client (checked for drift in CI)
make test       # Go + Flutter tests
make web        # Flutter web build into server embed dir
make build      # Go server binary with embedded web UI (requires `make web` first)
make run        # build + run on http://localhost:4420
```

Deployment (compose):

```sh
cd deploy && cp .env.example .env   # edit paths/keys
mkdir -p waxflow-config && cp waxflow-config.example.json waxflow-config/waxflow.json
docker compose up -d                # waxdeck on :4420, waxflow internal-only
```

The second line seeds the streaming engine's roots file, which the server
then owns: creating a library at runtime merges it into that file and has
the engine reconcile, so a new root streams without a restart. `make up`
does both steps for you.

## Contract-first rule

The contract is the single source of truth, authored as fragments in `api/spec/`
and bundled into `api/openapi.yaml` by `make generate`. Never hand-edit generated
code (`api/openapi.yaml`, `server/internal/api/gen.go`,
`app/packages/waxdeck_api_gen/`). Edit fragments, run `make generate`, commit
fragments, bundle, and generated code together. CI fails on drift and on breaking
spec changes.

## License

GPL-3.0-only. See [LICENSE](LICENSE). Contributions are accepted under the project 
license, no CLA (see [CONTRIBUTING.md](CONTRIBUTING.md)).
