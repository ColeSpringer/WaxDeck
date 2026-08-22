# syntax=docker/dockerfile:1
# WaxDeck server image. Build context is the REPO ROOT:
#   docker build -f deploy/Dockerfile .
#
# Generated code (server/internal/api/gen.go, Dart client) is committed to
# git, so no codegen toolchain is needed here: only Flutter (web build) and Go.

## --- stage 1: Flutter web build ----------------------------------------------
# Pin note: 3.44.0 is the newest tag published at ghcr.io/cirruslabs/flutter
# as of 2026-08-22 - nothing in 3.45, 3.46 or 3.47 has an image yet, so this
# now trails CI's 3.47.1 by three minor releases rather than one patch.
# Bump when cirruslabs catches up. Worth watching rather than ignoring: the
# gap is wide enough that the image's analyzer, formatter and golden
# rendering are not the ones the gates ran against, and only the web bundle
# is built here - a divergence would surface as a rendering difference in a
# container image nothing else covers.
#
# --platform=$BUILDPLATFORM: the web bundle is architecture-independent, so
# multi-arch builds (release workflow) run this stage once on the build host
# instead of re-running Flutter under emulation per target platform.
FROM --platform=$BUILDPLATFORM ghcr.io/cirruslabs/flutter:3.44.0 AS web

# Flutter prints a "running as root" advisory here. Expected and
# accepted: docker build steps run as root, this stage is discarded
# after the web bundle is copied out, and silencing it would mean
# chown-ing the multi-gigabyte SDK to a build user (a full extra layer
# in the build cache) for zero runtime effect. The runtime stage below
# already runs as the non-root waxdeck user.
WORKDIR /src
COPY app/ app/
# Pub workspace: resolve at the workspace root, build in the application package.
RUN cd app && flutter pub get
RUN cd app/app && flutter build web --wasm

## --- stage 2: Go server build -------------------------------------------------
# Cross-compiles from the build host (Go needs no emulation), so multi-arch
# builds stay fast: only the runtime stage below differs per target platform.
FROM --platform=$BUILDPLATFORM golang:1.26 AS build

ENV CGO_ENABLED=0
WORKDIR /src
# The server module replaces the sibling fixtures module by relative
# path, so both trees are needed to resolve the build list.
COPY server/ server/
COPY fixtures/ fixtures/
WORKDIR /src/server
# The web build is embedded via go:embed when built with -tags withweb.
COPY --from=web /src/app/app/build/web/ internal/web/dist/
# VERSION stamps `waxdeck --version` (and /metrics build info); the release
# workflow passes the tag, local builds keep the in-source dev default.
ARG VERSION=0.1.0-dev
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -tags withweb -trimpath \
      -ldflags "-X main.version=${VERSION}" \
      -o /out/waxdeck ./cmd/waxdeck

## --- stage 3: runtime ----------------------------------------------------------
FROM debian:bookworm-slim

# libchromaprint-tools: fpcalc for AcoustID fingerprinting, the single
# external tool this image ships. Decode and DSP are pure Go (WaxFlow
# codec packages); there is no ffmpeg anywhere in the stack.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libchromaprint-tools \
    && rm -rf /var/lib/apt/lists/*

# UID 10001 matches the Wax* container convention (see WaxFlow), and is the
# default. The compose stack overrides it with the host user's UID/GID (so the
# bind-mounted library, owned by the host user, is writable); the Docker-managed
# data and podcast volumes are made world-writable so they accept whatever UID
# the container runs as, without an entrypoint chown dance.
RUN groupadd --system --gid 10001 waxdeck \
    && useradd --system --uid 10001 --gid 10001 --home-dir /data --shell /usr/sbin/nologin waxdeck \
    && mkdir -p /data /library /podcasts \
    && chown waxdeck:waxdeck /data /podcasts \
    && chmod 0777 /data /podcasts

COPY --from=build /out/waxdeck /usr/local/bin/waxdeck
# The artifact conveys its own terms: the GPL text beside the
# third-party notices; the binary also prints the latter
# (--third-party-notices).
COPY LICENSE /usr/local/share/doc/waxdeck/LICENSE
COPY --from=build /src/server/internal/notices/third_party_notices.txt /usr/local/share/doc/waxdeck/THIRD-PARTY-NOTICES.txt

ENV WAXDECK_ADDR=0.0.0.0:4420 \
    WAXDECK_DATA_DIR=/data

VOLUME /data
EXPOSE 4420
USER waxdeck:waxdeck

ENTRYPOINT ["/usr/local/bin/waxdeck"]
