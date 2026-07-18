.PHONY: generate gen-go gen-dart lint spec-lint test test-server test-fixtures test-app \
        web build run drift-check oasdiff e2e dist clean

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
	cd app && dart format --set-exit-if-changed app/lib app/test packages/waxdeck_api/lib packages/waxdeck_api/test packages/waxdeck_player/lib packages/waxdeck_player/test >/dev/null
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
	cd app/packages/waxdeck_player_testing && flutter test
	cd app/app && flutter test

# Regenerate everything and fail if the tree changes (CI codegen-drift gate).
drift-check: generate
	git diff --exit-code -- $(SPEC) server/internal/api app/packages/waxdeck_api_gen

# Breaking-change gate against the base ref (override BASE for CI).
BASE ?= origin/main
oasdiff:
	go run github.com/oasdiff/oasdiff@v1.11.7 breaking "$(BASE):$(SPEC)" $(SPEC) --fail-on WARN

## --- build -------------------------------------------------------------------

# Flutter web build -> server embed dir (WasmGC target with JS fallback).
web:
	cd app/app && flutter build web --wasm
	rm -rf $(WEB_DIST) && mkdir -p $(WEB_DIST)
	cp -r $(APP_WEB_OUT)/. $(WEB_DIST)/

# Server binary. With the embedded web UI: `make web build` (tag withweb).
# Without (placeholder page only): `make build TAGS=`
TAGS ?= withweb
build:
	cd server && go build $(if $(TAGS),-tags $(TAGS)) -o waxdeck ./cmd/waxdeck

run: build
	./server/waxdeck

## --- e2e & packaging ----------------------------------------------------------

e2e:
	cd e2e && npm ci --no-audit --no-fund && npx playwright test

dist:
	docker build -f deploy/Dockerfile -t waxdeck:dev .

clean:
	rm -rf server/waxdeck $(WEB_DIST) app/app/build e2e/test-results e2e/playwright-report
