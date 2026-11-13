.PHONY: generate spec-bundle gen-go gen-dart gen-semantics gen-api-types gen-l10n gen-mirror app-deps lint dart-format-check spec-lint workflow-lint shell-lint test test-server test-fixtures test-app test-app-chrome \
        web build run images preflight up down reset logs drift-check oasdiff e2e e2e-desktop dist clean \
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

# The Dart client's models, codec, interfaces and calls. -client fails the
# run unless client.dart takes calls.g.dart, its one part, and -extensions
# unless model_extensions.dart's extensions on generated classes take no
# generated field's name (and each copyWith takes every field). -format
# formats the output before comparing it, so only changed files are
# written and a run that changes nothing leaves the web build current.
gen-dart: spec-bundle
	cd server && go run ./cmd/dartgen -format -spec ../$(SPEC) -hints ../app/packages/waxdeck_api/dartgen.yaml -out ../app/packages/waxdeck_api/lib/src/gen -client ../app/packages/waxdeck_api/lib/src/client.dart -extensions ../app/packages/waxdeck_api/lib/src/model_extensions.dart

# The semantics identifiers the e2e suite drives the UI by, emitted into
# the app and the specs from one list so the two cannot drift. The tool
# formats the Dart by app/app's analysis options, which resolve once
# app-deps has.
gen-semantics: app-deps
	dart run tools/gen-semantics-ids.dart

# Types the e2e driver against the contract, so a removed endpoint fails
# typecheck instead of arriving as a 404. npm ci is guarded because
# `generate` runs on Go- and Dart-only changes too. gen-types passes
# --default-non-nullable=false (e2e/package.json): without it a property
# that has a default is typed required, and every request body a spec
# builds without it fails typecheck.
gen-api-types: spec-bundle
	cd e2e && { test -d node_modules || npm ci --no-audit --no-fund; } && npm run --silent gen-types

# The app's copy and the design system's. The classes gen-l10n writes are
# not committed (flutter pub get mints them too); generating them here
# fails a translation that does not compile before a build does. The app's
# table is authored as per-feature fragments in app/app/l10n/, which the
# bundler merges into the per-locale files gen-l10n reads. gen-l10n
# formats what it writes, but only in a resolved workspace; nothing
# formats it again. It rewrites every class it writes, so it runs on a
# staging copy, and only the classes that changed are written.
gen-l10n: app-deps
	dart run tools/gen-l10n-bundle.dart
	dart run tools/gen-l10n-classes.dart app/app app/packages/waxdeck_ui

# Resolves the pub workspace, which also mints the l10n classes. The lint,
# test and web targets depend on it, as do the generate steps that need
# it, so a fresh clone needs no earlier step.
app-deps:
	cd app && flutter pub get

# The app version from the pubspec that declares it; Flutter answers no
# version at runtime without a plugin, and a hand-typed copy goes stale.
gen-version:
	dart run tools/gen-app-version.dart

# The client mirror's database.g.dart (named for the mirror, not the
# drift-check gate). build_runner needs a package config, which app-deps
# resolves, and analyzes waxdeck_data, which imports the client gen-dart
# writes, so under make -j it waits for that to finish.
gen-mirror: gen-dart app-deps
	cd app/packages/waxdeck_data && dart run build_runner build

# Embedded third-party notices (waxdeck --third-party-notices). GOWORK=off
# pins the module set to the zips, not workspace checkouts. The app LICENSE
# copy is how Flutter's NOTICES bundling conveys the GPL text; it is a web
# input, so it is copied only when it differs.
gen-notices:
	cd server && GOWORK=off go run ./cmd/noticegen -out internal/notices/third_party_notices.txt
	cmp -s LICENSE app/app/LICENSE || cp LICENSE app/app/LICENSE

# Rarely regenerated assets; not in `generate` because they hit the
# network and take minutes. Run them when the design changes.
.PHONY: fonts icons brand hlsjs goldens-linux
fonts:
	tools/fetch-fonts.sh

icons:
	tools/fetch-icons.sh

# The hls.js build the web app serves for gapless playback. Its license
# travels beside it and rides `make gen-notices` into the binary's
# notices, so re-vendoring and regenerating go together.
hlsjs:
	tools/fetch-hlsjs.sh

brand:
	python3 tools/generate-brand.py

# Rebaselines the readable goldens (goldens/linux/): they render real
# type, which rasterises host-specifically, so the container is what keeps
# any OS able to run this. Flutter version comes from ci.yaml so baselines
# are rendered by the toolchain that checks them.
#
# After a Flutter bump, drop the pub-cache volume first:
# `docker volume rm waxdeck-pub-cache`. Docker seeds a named volume from
# the image only while the volume is empty, so one left over from the
# previous image keeps that image's ownership - and the run fails on a
# bare "Permission denied" from pub rather than anything naming the
# cause.
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

lint: spec-lint workflow-lint shell-lint app-deps
	cd server && go vet ./... && test -z "$$(gofmt -l .)"
	cd server && go run ./cmd/spawnlint ./...
	cd server && go run ./cmd/querylint ./...
	cd server && go run ./cmd/importlint ./...
	cd server && go run ./cmd/bodylint ./...
	cd fixtures && go vet ./... && test -z "$$(gofmt -l .)"
	$(MAKE) --no-print-directory dart-format-check
	cd app && flutter analyze --no-pub
	cd e2e && { test -d node_modules || npm ci --no-audit --no-fund; } && npm run --silent conform

# The Dart sources `dart format` keeps formatted: one list for `make lint`
# and CI's flutter job, which calls the target after its pub get.
DART_FORMAT_PATHS := app/lib app/test app/integration_test app/tool packages/waxdeck_api/lib packages/waxdeck_api/test packages/waxdeck_player/lib packages/waxdeck_player_testing/lib packages/waxdeck_player_testing/test packages/waxdeck_data/lib packages/waxdeck_data/test packages/waxdeck_ui/lib packages/waxdeck_ui/test packages/waxdeck_ui/example/lib packages/waxdeck_ui/example/test

# Rewrites any misformatted file in place and fails if it changed one,
# printing dart format's report (the files it names) only then. It needs
# the resolved workspace: each package's language version comes from the
# package config, and without it dart format falls back to the old style
# and rewrites most files, so it refuses to run without one. `lint` runs it
# from its recipe, after app-deps.
dart-format-check:
	@test -f app/.dart_tool/package_config.json || { echo "dart-format-check: no app/.dart_tool/package_config.json; run flutter pub get (make app-deps) first" >&2; exit 1; }
	cd app && out=$$(dart format --set-exit-if-changed $(DART_FORMAT_PATHS) 2>&1) || { printf '%s\n' "$$out"; exit 1; }

# Lints the committed bundle as-is; freshness is drift-check's job. The
# linter comes from e2e's lockfile rather than a bare npx: the CLI's own
# pin leaves its rulesets at >=1, and a rule added upstream would red CI
# on a change that never touched the spec. npm ci is guarded the way
# gen-api-types guards it, and spectral runs from here so it finds the
# repo's .spectral.yaml.
spec-lint:
	cd e2e && { test -d node_modules || npm ci --no-audit --no-fund; }
	e2e/node_modules/.bin/spectral lint --fail-severity=warn $(SPEC)

# The workflows and the shell beside them, checked as CI's workflows job
# checks them, since that job runs these two targets (and lint-tooling.yaml
# runs them on Windows and macOS). actionlint reads the YAML, the
# expressions and every run: block (through shellcheck); shellcheck reads
# the repository's own scripts at warning severity, in the gcc format
# CI's problem matcher parses. Each linter is the pinned build
# tools/fetch-linter.sh caches per user, never one from PATH or a runner
# image: those move on their own and would red a change that touched
# nothing here, which is also why pyflakes stays off. Keep the && chain -
# actionlint silently skips a shellcheck it cannot run, so a failed fetch
# must stop it. The workflows are named rather than found: actionlint's
# own search wants a git checkout, and a tree cut with git archive is not
# one.
WORKFLOWS := $(wildcard .github/workflows/*.yaml .github/workflows/*.yml)
workflow-lint:
	al=$$(tools/fetch-linter.sh actionlint) && sc=$$(tools/fetch-linter.sh shellcheck) && "$$al" -shellcheck="$$sc" -pyflakes= $(WORKFLOWS)

shell-lint:
	sc=$$(tools/fetch-linter.sh shellcheck) && "$$sc" -f gcc -S warning e2e/*.sh e2e/tools/*.sh tools/*.sh tools/ci/*.sh

test: test-server test-fixtures test-app

# Browser-only suites, matched by suffix so new ones run when written.
# Not in `test`: it needs a local Chrome, and CI is where it ratchets.
# Linux or macOS only, and not by choice: on Windows flutter_tools'
# own test server answers every CanvasKit request with a 404, because
# `_localCanvasKitHandler` gates on `path.fromUri(...).startsWith
# ('canvaskit/')` and fromUri hands back backslashes there. The web
# engine never boots, so the suite never connects - a bare `flutter
# create` project fails the same way, so there is nothing here to fix.
test-app-chrome: app-deps
	cd app/app && flutter test --platform chrome test/*_web_test.dart

# The cap is a deadlock detector, not a budget. Go's default is 10
# minutes per package, so a worker that never returns costs ten minutes
# and answers with an eight-thousand-line goroutine dump - which is how
# a supervised teardown that deadlocked `Group.Wait` was found. On four
# CPUs `internal/service` measures about two minutes, `internal/api`
# about 85s, the gpodder adapter about 50s, and everything else under
# four, so four minutes still turns a hang into a fast answer. Raise it
# when a package legitimately grows past it; do not raise it to make a
# hang pass.
#
# CI is deliberately not this number: it runs the same suite under
# `-race` on a shared runner, where `internal/service` and
# `internal/api` run for minutes rather than seconds, and
# `.github/workflows/ci.yaml` sets 20m for that with its own note.
test-server:
	cd server && go test -timeout 240s ./...

test-fixtures:
	cd fixtures && go test ./...

test-app: app-deps
	cd app/packages/waxdeck_api && dart test
	cd app/packages/waxdeck_ui && flutter test
	cd app/packages/waxdeck_ui/example && flutter test
	cd app/packages/waxdeck_data && flutter test
	cd app/packages/waxdeck_player_testing && flutter test
	cd app/app && flutter test

# Regenerate everything and fail if the tree changes (CI codegen-drift
# gate): a tracked file the run changed, or one under these paths that git
# does not track, which a commit made without it would lack.
DRIFT_PATHS := $(SPEC) server/internal/api app/packages/waxdeck_api/lib/src/gen \
	app/app/lib/src/shell/semantics_ids.dart e2e/tests/semantics-ids.ts \
	app/app/lib/src/l10n/arb \
	app/app/lib/src/shell/app_version.dart \
	app/packages/waxdeck_data/lib/src/database.g.dart \
	server/internal/notices/third_party_notices.txt app/app/LICENSE
drift-check: generate
	git diff --exit-code -- $(DRIFT_PATHS)
	@untracked=$$(git status --porcelain --untracked-files=all -- $(DRIFT_PATHS) | grep '^??' || true); \
	 if [ -n "$$untracked" ]; then printf 'drift-check: untracked under the generated paths:\n%s\n' "$$untracked" >&2; exit 1; fi

# Breaking-change gate against the base ref. The allow file lists accepted
# breaks, one per line as `METHOD /path` followed by the change text the
# way this recipe prints it, backticks included: the match is on that
# text, so a paraphrase or a requoting allows nothing. --color never is
# part of that: coloured output quotes values with ' instead, and a line
# copied from it would allow nothing. The file is deleted once the base
# has the breaks.
# --flatten-allof: an allOf move is a wire no-op, and the wire is all the
# gate judges.
BASE ?= origin/main
OASDIFF_ALLOW := api/oasdiff-allow.txt
oasdiff:
	git show "$(BASE):$(SPEC)" > .oasdiff-base.yaml
	go run github.com/oasdiff/oasdiff@v1.32.1 breaking .oasdiff-base.yaml $(SPEC) --fail-on WARN --flatten-allof --color never \
		$(if $(wildcard $(OASDIFF_ALLOW)),--err-ignore $(OASDIFF_ALLOW) --warn-ignore $(OASDIFF_ALLOW)); \
	status=$$?; rm -f .oasdiff-base.yaml; exit $$status

## --- build -------------------------------------------------------------------

# Flutter web build -> server embed dir (WasmGC target with JS fallback).
web: app-deps
	cd app/app && flutter build web --wasm
	rm -rf $(WEB_DIST) && mkdir -p $(WEB_DIST)
	cp -r $(APP_WEB_OUT)/. $(WEB_DIST)/

# A real file target, so the web bundle rebuilds only when one of its
# inputs is newer: no stale UI, no Flutter compile on Go-only iterations.
WEB_STAMP := $(WEB_DIST)/flutter_bootstrap.js
# Everything the web build reads, so that none of it can change under a
# bundle that stays: the Dart and the l10n bundles beside it, every font
# and asset a pubspec declares, the pubspecs and the lockfile, the
# licenses its NOTICES carry, and the page template with the files served
# beside it. `make fonts`, `make brand` and a dependency bump each change
# some of these without touching a line of Dart.
WEB_INPUTS := $(shell find app/app/lib app/app/web app/app/assets \
                $(wildcard app/packages/*/lib app/packages/*/fonts app/packages/*/assets) \
                -type f 2>/dev/null) \
              $(wildcard app/pubspec.yaml app/pubspec.lock app/app/pubspec.yaml app/app/l10n.yaml \
                app/packages/*/pubspec.yaml app/packages/*/l10n.yaml app/app/LICENSE app/packages/*/LICENSE)

$(WEB_STAMP): $(WEB_INPUTS)
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
# Dev images, tagged apart from the published ones.
DEV_TAGS := WAXDECK_TAG=dev WAXFLOW_TAG=dev

# The server image and the engine at the version server/go.mod pins.
images:
	docker build -f deploy/Dockerfile -t ghcr.io/colespringer/waxdeck:dev .
	docker build -f deploy/Dockerfile.waxflow -t ghcr.io/colespringer/waxflow:dev .

dist: images

# Both media folders, resolved the way compose resolves them: a default
# folder is created, a configured one must exist (a typo would start an
# empty library), and either must be writable by this user.
preflight: deploy/.env
	@folder() { \
	   dir="$$2"; \
	   if [ -z "$$dir" ]; then \
	     dir=$$(sed -n "s/^$$1=//p" deploy/.env | tail -n 1 | tr -d '\r' \
	       | sed -e 's/^"\(.*\)"$$/\1/' -e "s/^'\(.*\)'$$/\1/"); \
	   fi; \
	   given=$$dir; \
	   dir=$${dir:-./$$3}; \
	   case "$$dir" in "~") dir="$$HOME" ;; "~/"*) dir="$$HOME/$${dir#\~/}" ;; /*|[A-Za-z]:*) ;; *) dir="deploy/$${dir#./}" ;; esac; \
	   if [ -z "$$given" ] || [ "$$given" = "./$$3" ]; then \
	     mkdir -p "$$dir" || { echo "make up: cannot create $$1=$$dir" >&2; exit 1; }; \
	   elif [ ! -d "$$dir" ]; then \
	     echo "make up: $$1=$$dir does not exist; docker would create it empty and root-owned. Point deploy/.env at your folder." >&2; \
	     exit 1; \
	   fi; \
	   if ! touch "$$dir/.write-probe" 2>/dev/null; then \
	     echo "make up: $$1=$$dir is not writable by $$(id -un); imports in the container would fail. Fix its ownership or point deploy/.env at another path." >&2; \
	     exit 1; \
	   fi; \
	   rm -f "$$dir/.write-probe"; \
	 }; \
	 folder WAXDECK_MUSIC "$${WAXDECK_MUSIC-}" music && folder WAXDECK_AUDIOBOOKS "$${WAXDECK_AUDIOBOOKS-}" audiobooks

# The stack from this checkout's images. Docker Desktop, macOS runtimes,
# rootless Docker and a userns-remapped daemon cannot share the host's
# network: there the stdin override puts the stack on the project network.
up: deploy/.env preflight images
	@ids=; case "$$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) ids="WAXDECK_UID=$$(id -u) WAXDECK_GID=$$(id -g)" ;; esac; \
	 if [ "$$(uname -s)" = Darwin ] || docker info --format '{{.OperatingSystem}} {{.SecurityOptions}}' 2>/dev/null | grep -q 'Docker Desktop\|name=rootless\|name=userns'; then \
	   echo "make up: this Docker cannot share the host network; the stack runs on the project network (no cast discovery)"; \
	   printf '%s\n' 'services:' '  waxdeck:' '    network_mode: !reset null' '    extra_hosts: !reset []' '    ports: ["4420:4420"]' \
	     '  waxflow:' '    network_mode: !reset null' '    environment:' '      WAXFLOW_ADDR: 0.0.0.0:4418' \
	     '  waxseal:' '    network_mode: !reset null' '    command: ["server", "--host", "0.0.0.0", "--tenant-keys", "$${WAXDECK_SEAL_KEY:-$${WAXDECK_INTERNAL_KEY:-}}"]' \
	     | env $$ids $(DEV_TAGS) $(COMPOSE) -f - up -d --wait; \
	 else \
	   env $$ids $(DEV_TAGS) $(COMPOSE) up -d --wait; \
	 fi
	@echo "WaxDeck is up on http://localhost:4420  (make logs / make down)"

# deploy/.env from the example, with a generated internal key.
deploy/.env:
	@umask 077; \
	 key=$$(openssl rand -hex 24); \
	 sed -e "s|^WAXDECK_INTERNAL_KEY=.*|WAXDECK_INTERNAL_KEY=$$key|" deploy/.env.example > deploy/.env
	@echo "wrote deploy/.env with a generated internal key; set WAXDECK_MUSIC and WAXDECK_AUDIOBOOKS to your folders"

down:
	$(COMPOSE) down

# Down plus volumes: a first-run stack again. Media folders and deploy/.env stay.
reset:
	$(COMPOSE) down -v
	@echo "stack down and volumes dropped: catalog, accounts, episodes, the engine's roots file and cache"
	@echo "kept: your music and audiobooks, deploy/.env  ->  make up"

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
e2e-desktop: app-deps
	bash e2e/run-desktop.sh


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
