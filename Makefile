.PHONY: generate gen-go gen-dart lint spec-lint test test-server test-fixtures test-app \
        web build run up down logs drift-check oasdiff e2e dist clean

SPEC        := api/openapi.yaml
WEB_DIST    := server/internal/web/dist
APP_WEB_OUT := app/app/build/web

## --- codegen -----------------------------------------------------------------

generate: gen-go gen-dart

gen-go:
	cd server && go tool oapi-codegen -config ../tools/oapi-codegen.yaml ../$(SPEC)
	cd server && gofmt -w internal/api/gen.go

gen-dart:
	tools/generate-dart.sh

## --- quality gates -----------------------------------------------------------

lint: spec-lint
	cd server && go vet ./... && test -z "$$(gofmt -l .)"
	cd server && go run ./cmd/spawnlint ./...
	cd fixtures && go vet ./... && test -z "$$(gofmt -l .)"
	cd app && dart format --set-exit-if-changed app/lib app/test app/integration_test app/tool packages/waxdeck_api/lib packages/waxdeck_api/test packages/waxdeck_player/lib packages/waxdeck_data/lib packages/waxdeck_data/test >/dev/null
	cd app && flutter analyze --no-pub

spec-lint:
	npx --yes @stoplight/spectral-cli lint --fail-severity=warn $(SPEC)

test: test-server test-fixtures test-app

test-server:
	cd server && go test ./...

test-fixtures:
	cd fixtures && go test ./...

test-app:
	cd app/packages/waxdeck_api && dart test
	cd app/packages/waxdeck_data && flutter test
	cd app/packages/waxdeck_player_testing && flutter test
	cd app/app && flutter test

# Regenerate everything and fail if the tree changes (CI codegen-drift gate).
drift-check: generate
	git diff --exit-code -- $(SPEC) server/internal/api app/packages/waxdeck_api_gen

# Breaking-change gate against the base ref (override BASE for CI).
# api/oasdiff-allow.txt, when present, lists deliberately accepted
# breaking changes (one oasdiff output line per entry); it is temporary
# by construction and is deleted once the base ref contains the change.
BASE ?= origin/main
OASDIFF_ALLOW := api/oasdiff-allow.txt
oasdiff:
	git show "$(BASE):$(SPEC)" > .oasdiff-base.yaml
	go run github.com/oasdiff/oasdiff@v1.11.7 breaking .oasdiff-base.yaml $(SPEC) --fail-on WARN \
		$(if $(wildcard $(OASDIFF_ALLOW)),--err-ignore $(OASDIFF_ALLOW) --warn-ignore $(OASDIFF_ALLOW)); \
	status=$$?; rm -f .oasdiff-base.yaml; exit $$status

## --- build -------------------------------------------------------------------

# Flutter web build -> server embed dir (WasmGC target with JS fallback).
web:
	cd app/app && flutter build web --wasm
	rm -rf $(WEB_DIST) && mkdir -p $(WEB_DIST)
	cp -r $(APP_WEB_OUT)/. $(WEB_DIST)/

# The embedded UI's freshness marker and the Flutter sources it is built
# from. WEB_STAMP is a real file (not phony) so it rebuilds only when a
# source is newer, which is what keeps `make run` from serving a stale
# build without paying a Flutter compile on every Go-only iteration.
WEB_STAMP := $(WEB_DIST)/flutter_bootstrap.js
DART_SRCS := $(shell find app/app/lib -name '*.dart' 2>/dev/null) \
             $(shell find app/packages -path '*/lib/*.dart' 2>/dev/null) \
             app/app/pubspec.yaml

$(WEB_STAMP): $(DART_SRCS)
	$(MAKE) web

# Server binary. With the embedded web UI: `make web build` (tag withweb).
# Without (placeholder page only): `make build TAGS=`. `build` embeds
# whatever is in the dist dir and never runs Flutter, so it stays usable
# in Flutter-less environments (CI, packaging).
TAGS ?= withweb
build:
	cd server && go build $(if $(TAGS),-tags $(TAGS)) -o waxdeck ./cmd/waxdeck

# `run` is the fast local path: one binary with the embedded UI and no
# streaming engine. It refreshes the UI when the Dart sources changed,
# and sources a root .env (gitignored) so config persists across runs
# instead of being retyped. Good for iterating on the app; for a full
# realistic instance (streaming engine, the real container topology),
# use `make up`.
run: $(WEB_STAMP)
	$(MAKE) build
	set -a; [ -f .env ] && . ./.env; set +a; ./server/waxdeck

## --- run the full stack (Docker) ---------------------------------------------

COMPOSE := docker compose -f deploy/compose.yaml

# The complete, testable instance: the waxdeck image plus the flavored
# waxflow streaming sidecar, wired over the internal network. Generates
# deploy/.env with fresh internal keys on first run; set WAXDECK_LIBRARY
# in it to point at your music (defaults to an empty deploy/library).
up: deploy/.env
	@mkdir -p deploy/library deploy/podcasts
	WAXDECK_UID=$$(id -u) WAXDECK_GID=$$(id -g) $(COMPOSE) up --build -d
	@echo "WaxDeck is up on http://localhost:4420  (make logs / make down)"

# Generate deploy/.env from the example with matching internal API keys,
# so the stack comes up without hand-editing secrets.
deploy/.env:
	@key=$$(openssl rand -hex 24); \
	 worker=$$(openssl rand -hex 24); \
	 sed -e "s|^WAXFLOW_API_KEYS=.*|WAXFLOW_API_KEYS=$$key|" \
	     -e "s|^WAXDECK_FLOW_API_KEY=.*|WAXDECK_FLOW_API_KEY=$$key|" \
	     -e "s|^WAXDECK_WORKER_TOKENS=.*|WAXDECK_WORKER_TOKENS=$$worker|" \
	     deploy/.env.example > deploy/.env
	@echo "wrote deploy/.env with generated keys; set WAXDECK_LIBRARY to your music path"

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

## --- e2e & packaging ----------------------------------------------------------

e2e:
	cd e2e && npm ci --no-audit --no-fund && npx playwright test

dist:
	docker build -f deploy/Dockerfile -t waxdeck:dev .

clean:
	rm -rf server/waxdeck $(WEB_DIST) app/app/build e2e/test-results e2e/playwright-report
