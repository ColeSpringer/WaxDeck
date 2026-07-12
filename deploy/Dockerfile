# syntax=docker/dockerfile:1
# WaxDeck server image. Build context is the REPO ROOT:
#   docker build -f deploy/Dockerfile .
#
# Generated code (server/internal/api/gen.go, Dart client) is committed to
# git, so no codegen toolchain is needed here: only Flutter (web build) and Go.

## --- stage 1: Flutter web build ----------------------------------------------
# Pin note: 3.44.0 is the newest 3.44.x tag published at ghcr.io/cirruslabs/flutter
# as of 2026-07 (3.44.6 exists as a Flutter stable release but has no image tag
# yet). Bump when cirruslabs catches up so this matches CI's 3.44.6.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS web

WORKDIR /src
COPY app/ app/
# Pub workspace: resolve at the workspace root, build in the application package.
RUN cd app && flutter pub get
RUN cd app/app && flutter build web --wasm

## --- stage 2: Go server build -------------------------------------------------
FROM golang:1.26 AS build

ENV CGO_ENABLED=0
WORKDIR /src/server
COPY server/ ./
# The web build is embedded via go:embed when built with -tags withweb.
COPY --from=web /src/app/app/build/web/ internal/web/dist/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download && \
    go build -tags withweb -trimpath -o /out/waxdeck ./cmd/waxdeck

## --- stage 3: runtime ----------------------------------------------------------
FROM debian:bookworm-slim

# ffmpeg: transcoding/probing. libchromaprint-tools: fpcalc for AcoustID.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg libchromaprint-tools \
    && rm -rf /var/lib/apt/lists/*

# UID 10001 matches the Wax* container convention (see WaxFlow).
RUN groupadd --system --gid 10001 waxdeck \
    && useradd --system --uid 10001 --gid 10001 --home-dir /data --shell /usr/sbin/nologin waxdeck \
    && mkdir -p /data /library \
    && chown waxdeck:waxdeck /data

COPY --from=build /out/waxdeck /usr/local/bin/waxdeck

ENV WAXDECK_ADDR=0.0.0.0:4420 \
    WAXDECK_DATA_DIR=/data

VOLUME /data
EXPOSE 4420
USER waxdeck:waxdeck

ENTRYPOINT ["/usr/local/bin/waxdeck"]
