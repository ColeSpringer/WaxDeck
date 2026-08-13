.PHONY: generate spec-bundle gen-go gen-dart gen-semantics gen-api-types gen-l10n gen-mirror lint spec-lint test test-server test-fixtures test-app test-app-chrome \
        web build run up down reset logs drift-check oasdiff e2e e2e-desktop dist clean \
        path-doctor

# Windows: run the POSIX recipes through Git's bash and userland, so
# make works from any shell. Override GIT_ROOT if Git lives elsewhere.
ifeq ($(OS),Windows_NT)
EMPTY :=
SP := $(EMPTY) $(EMPTY)
GIT_ROOT ?= C:/Program Files/Git
ifeq ($(wildcard $(subst $(SP),\ ,$(GIT_ROOT))/bin/bash.exe),)
  ifneq ($(wildcard $(subst \,/,$(LOCALAPPDATA))/Programs/Git/bin/bash.exe),)
    GIT_ROOT := $(subst \,/,$(LOCALAPPDATA))/Programs/Git
  else
    $(error no bash at $(GIT_ROOT)/bin/bash.exe; install Git for Windows or set GIT_ROOT)
  endif
endif
SHELL := $(GIT_ROOT)/bin/bash.exe
# Both halves are needed: bash prepends /usr/bin to its own shells, and
# the export covers the metacharacter-free lines make direct-spawns
# without it. The cost is usr/bin's coreutils link.exe outranking
# MSVC's linker, so a target that wraps an MSVC build prefixes
# $(MSVC_NATIVE_PATH); `make path-doctor` shows what resolves where.
# The capture is immediate and taken before the prepend, since `?=`
# would expand $(PATH) after it and defeat itself.
ifeq ($(origin WAXDECK_NATIVE_PATH),undefined)
export WAXDECK_NATIVE_PATH := $(PATH)
else
export WAXDECK_NATIVE_PATH
endif
export PATH := $(GIT_ROOT)/usr/bin;$(WAXDECK_NATIVE_PATH)
# The caller's own PATH as a per-command environment prefix, unix-form.
MSVC_NATIVE_PATH = PATH="$$(cygpath -up '$(WAXDECK_NATIVE_PATH)')"
else
MSVC_NATIVE_PATH :=
endif

SPEC        := api/openapi.yaml
SPEC_SRC    := api/spec
WEB_DIST    := server/internal/web/dist
APP_WEB_OUT := app/app/build/web

## --- codegen -----------------------------------------------------------------

generate: gen-go gen-dart gen-semantics gen-api-types gen-l10n gen-version gen-mirror gen-notices

# Bundles the api/spec/ fragments into the committed spec every consumer
# reads. Phony on purpose: a fresh checkout gives bundle and fragments
# equal mtimes, so a file target could skip exactly when drift-check runs.
spec-bundle:
	cd server && go run ./cmd/specbundle -src ../$(SPEC_SRC) -out ../$(SPEC)

gen-go: spec-bundle
	cd server && go tool oapi-codegen -config ../tools/oapi-codegen.yaml ../$(SPEC)
	cd server && gofmt -w internal/api/gen.go

gen-dart: spec-bundle
	tools/generate-dart.sh

# The semantics identifiers the e2e suite drives the UI by, emitted into
# the app and the specs from one list so the two cannot drift.
gen-semantics:
	dart run tools/gen-semantics-ids.dart
	dart format app/app/lib/src/shell/semantics_ids.dart >/dev/null

# Types the e2e driver against the contract, so a removed endpoint fails
# typecheck instead of arriving as a 404. npm ci is guarded because
# `generate` runs on Go- and Dart-only changes too.
gen-api-types: spec-bundle
	cd e2e && { test -d node_modules || npm ci --no-audit --no-fund; } && npm run --silent gen-types

# The app's copy, committed rather than built on the fly, so a
# translation that fails to compile fails here and not in a release.
# gen-l10n formats what it writes; nothing formats it again.
gen-l10n:
	cd app/app && flutter gen-l10n

# The app version from the pubspec that declares it; Flutter answers no
# version at runtime without a plugin, and a hand-typed copy goes stale.
gen-version:
	dart run tools/gen-app-version.dart

# The client mirror's database.g.dart (named for the mirror, not the
# drift-check gate). Runs its own pub get: under `make -j` nothing
# orders this after gen-dart, and build_runner needs a package config.
gen-mirror:
	cd app && dart pub get
	cd app/packages/waxdeck_data && dart run build_runner build

# Embedded third-party notices (waxdeck --third-party-notices). GOWORK=off
# pins the module set to the zips, not workspace checkouts. The app LICENSE
# copy is how Flutter's NOTICES bundling conveys the GPL text.
gen-notices:
	cd server && GOWORK=off go run ./cmd/noticegen -out internal/notices/third_party_notices.txt
	cp LICENSE app/app/LICENSE

# Rarely regenerated assets; not in `generate` because they hit the
# network and take minutes. Run them when the design changes.
.PHONY: fonts icons brand goldens-linux
fonts:
	tools/fetch-fonts.sh

icons:
	tools/fetch-icons.sh

brand:
	python3 tools/generate-brand.py

# Rebaselines the readable goldens (goldens/linux/): they render real
# type, which rasterises host-specifically, so the container is what keeps
# any OS able to run this. Flutter version comes from ci.yaml so baselines
# are rendered by the toolchain that checks them.
FLUTTER_VERSION := $(shell sed -n 's/^[[:space:]]*FLUTTER_VERSION:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' .github/workflows/ci.yaml | head -1)
goldens-linux:
	@test -n "$(FLUTTER_VERSION)" || { echo "make goldens-linux: no FLUTTER_VERSION found in .github/workflows/ci.yaml" >&2; exit 1; }
	docker build --platform linux/amd64 --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
		-f tools/goldens.Dockerfile -t waxdeck-goldens:$(FLUTTER_VERSION) tools
	docker run --rm --platform linux/amd64 --user $$(id -u):$$(id -g) -e HOME=/tmp \
		-v "$(CURDIR)":/repo -v waxdeck-pub-cache:/pub-cache \
		waxdeck-goldens:$(FLUTTER_VERSION)
	@echo "goldens/linux rebaselined; review the diff before committing"

## --- quality gates -----------------------------------------------------------

lint: spec-lint
	cd server && go vet ./... && test -z "$$(gofmt -l .)"
	cd server && go run ./cmd/spawnlint ./...
	cd server && go run ./cmd/querylint ./...
	cd fixtures && go vet ./... && test -z "$$(gofmt -l .)"
	cd app && dart format --set-exit-if-changed app/lib app/test app/integration_test app/tool packages/waxdeck_api/lib packages/waxdeck_api/test packages/waxdeck_player/lib packages/waxdeck_player_testing/lib packages/waxdeck_player_testing/test packages/waxdeck_data/lib packages/waxdeck_data/test packages/waxdeck_ui/lib packages/waxdeck_ui/test packages/waxdeck_ui/example/lib packages/waxdeck_ui/example/test >/dev/null
	cd app && flutter analyze --no-pub
	cd e2e && { test -d node_modules || npm ci --no-audit --no-fund; } && npm run --silent conform

# Lints the committed bundle as-is; freshness is drift-check's job.
spec-lint:
	npx --yes @stoplight/spectral-cli lint --fail-severity=warn $(SPEC)

test: test-server test-fixtures test-app

# Browser-only suites, matched by suffix so new ones run when written.
# Not in `test`: it needs a local Chrome, and CI is where it ratchets.
test-app-chrome:
	cd app/app && flutter test --platform chrome test/*_web_test.dart

test-server:
	cd server && go test ./...

test-fixtures:
	cd fixtures && go test ./...

test-app:
	cd app/packages/waxdeck_api && dart test
	cd app/packages/waxdeck_ui && flutter test
	cd app/packages/waxdeck_ui/example && flutter test
	cd app/packages/waxdeck_data && flutter test
	cd app/packages/waxdeck_player_testing && flutter test
	cd app/app && flutter test

# Regenerate everything and fail if the tree changes (CI codegen-drift gate).
drift-check: generate
	git diff --exit-code -- $(SPEC) server/internal/api app/packages/waxdeck_api_gen \
		app/app/lib/src/shell/semantics_ids.dart e2e/tests/semantics-ids.ts \
		e2e/tests/api-types.ts \
		app/app/lib/src/l10n/gen \
		app/app/lib/src/shell/app_version.dart \
		app/packages/waxdeck_data/lib/src/database.g.dart \
		server/internal/notices/third_party_notices.txt app/app/LICENSE

# Breaking-change gate against the base ref. The allow file lists accepted
# breaks (one oasdiff line each) and is deleted once the base has them.
# --flatten-allof: both generators flatten, so allOf moves are wire no-ops.
BASE ?= origin/main
OASDIFF_ALLOW := api/oasdiff-allow.txt
oasdiff:
	git show "$(BASE):$(SPEC)" > .oasdiff-base.yaml
	go run github.com/oasdiff/oasdiff@v1.11.7 breaking .oasdiff-base.yaml $(SPEC) --fail-on WARN --flatten-allof \
		$(if $(wildcard $(OASDIFF_ALLOW)),--err-ignore $(OASDIFF_ALLOW) --warn-ignore $(OASDIFF_ALLOW)); \
	status=$$?; rm -f .oasdiff-base.yaml; exit $$status

## --- build -------------------------------------------------------------------

# Flutter web build -> server embed dir (WasmGC target with JS fallback).
web:
	cd app/app && flutter build web --wasm
	rm -rf $(WEB_DIST) && mkdir -p $(WEB_DIST)
	cp -r $(APP_WEB_OUT)/. $(WEB_DIST)/

# A real file target, so the web bundle rebuilds only when a Dart source
# is newer: no stale UI, no Flutter compile on Go-only iterations.
WEB_STAMP := $(WEB_DIST)/flutter_bootstrap.js
DART_SRCS := $(shell find app/app/lib -name '*.dart' 2>/dev/null) \
             $(shell find app/packages -path '*/lib/*.dart' 2>/dev/null) \
             app/app/pubspec.yaml

$(WEB_STAMP): $(DART_SRCS)
	$(MAKE) web

# Server binary: `make web build` embeds the UI; `make build TAGS=` gives
# the placeholder page. Never runs Flutter, so Flutter-less envs can build.
TAGS ?= withweb
build:
	cd server && go build $(if $(TAGS),-tags $(TAGS)) -o waxdeck ./cmd/waxdeck

# Fast local path: one binary, embedded UI, no streaming engine (that is
# `make up`). Sources a gitignored root .env so config persists across runs.
run: $(WEB_STAMP)
	$(MAKE) build
	set -a; [ -f .env ] && . ./.env; set +a; ./server/waxdeck

## --- run the full stack (Docker) ---------------------------------------------

COMPOSE := docker compose -f deploy/compose.yaml

# The full stack. The preflight proves WAXDECK_LIBRARY writable first
# (docker creates a missing bind source root-owned), resolving it the way
# compose resolves it. id -u/-g are skipped only on Windows, where MSYS
# ids are SID-derived noise; macOS keeps them so volumes stay readable.
up: deploy/.env deploy/waxflow-config/waxflow.json
	@lib="$${WAXDECK_LIBRARY-}"; \
	 if [ -z "$$lib" ]; then \
	   lib=$$(sed -n 's/^WAXDECK_LIBRARY=//p' deploy/.env | tail -n 1 | tr -d '\r' \
	     | sed -e 's/^"\(.*\)"$$/\1/' -e "s/^'\(.*\)'$$/\1/"); \
	 fi; \
	 lib=$${lib:-./library}; \
	 case "$$lib" in "~") lib="$$HOME" ;; "~/"*) lib="$$HOME/$${lib#\~/}" ;; /*|[A-Za-z]:*) ;; *) lib="deploy/$${lib#./}" ;; esac; \
	 mkdir -p "$$lib" || { echo "make up: cannot create WAXDECK_LIBRARY=$$lib" >&2; exit 1; }; \
	 if ! touch "$$lib/.write-probe" 2>/dev/null; then \
	   echo "make up: WAXDECK_LIBRARY=$$lib is not writable by $$(id -un); imports in the container would fail. Fix its ownership or point deploy/.env at another path." >&2; \
	   exit 1; \
	 fi; \
	 rm -f "$$lib/.write-probe"
	@case "$$(uname -s)" in \
	   MINGW*|MSYS*|CYGWIN*) $(COMPOSE) up --build -d ;; \
	   *) WAXDECK_UID=$$(id -u) WAXDECK_GID=$$(id -g) $(COMPOSE) up --build -d ;; \
	 esac
	@echo "WaxDeck is up on http://localhost:4420  (make logs / make down)"

# Seed the sidecar's roots from the example. A file rather than
# WAXFLOW_ROOTS so runtime-created libraries reconcile without a restart;
# deployment state, so untracked.
deploy/waxflow-config/waxflow.json: deploy/waxflow-config.example.json
	@mkdir -p $(@D)
	@cp deploy/waxflow-config.example.json $@
	@echo "wrote $@ (the sidecar's roots; WaxDeck merges runtime libraries into it)"

# deploy/.env from the example, with matching generated internal keys.
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

# Down plus volumes: the first-run stack again. Your library is a bind
# mount and untouched, as are deploy/.env and deploy/waxflow-config/.
reset:
	$(COMPOSE) down -v
	@echo "stack down and volumes dropped: catalog, accounts, episodes, sidecar cache"
	@echo "kept: your library, deploy/.env, deploy/waxflow-config/  ->  make up"

logs:
	$(COMPOSE) logs -f --tail=100

## --- e2e & packaging ----------------------------------------------------------

# The suite tests the embedded UI through the real binary, so both must
# be current: a stale bundle reads exactly like a missing feature. The
# unconditional build also heals the tagless binary e2e-desktop leaves.
# WAXDECK_BASE_URL means the caller's own stack; nothing is ours to build.
e2e:
ifndef WAXDECK_BASE_URL
	$(MAKE) $(WEB_STAMP)
	$(MAKE) build
endif
	cd e2e && npm ci --no-audit --no-fund && npm run typecheck && npm run --silent conform && npx playwright test

# Desktop journey plus engine conformance against the real mpv backend.
# Needs a display and audio sink; the runner documents headless wrapping.
e2e-desktop:
	bash e2e/run-desktop.sh

dist:
	docker build -f deploy/Dockerfile -t waxdeck:dev .

clean:
	rm -rf server/waxdeck $(WEB_DIST) app/app/build e2e/test-results e2e/playwright-report

## --- diagnostics --------------------------------------------------------------

# What a recipe's PATH resolves, and how to get MSVC's linker back.
# Every line carries a metacharacter, so it routes through SHELL.
path-doctor:
	@echo "SHELL=$(SHELL)"; echo "make $(MAKE_VERSION)"
	@echo "PATH=$$PATH"
	@echo "WAXDECK_NATIVE_PATH=$${WAXDECK_NATIVE_PATH:-<unset: not Windows>}"
	@for t in find sed cp bash link; do \
	   echo "  $$t -> $$(command -v $$t || echo '<none>')"; \
	 done
ifeq ($(OS),Windows_NT)
	@echo "link on make's PATH:"; where link 2>&1 | sed 's/^/  /'
	@echo "link on the caller's PATH (\$$(MSVC_NATIVE_PATH)):"; \
	 $(MSVC_NATIVE_PATH) where link 2>&1 | sed 's/^/  /'
endif
