# syntax=docker/dockerfile:1
# WaxDeck server image. Build context is the REPO ROOT (the root
# .dockerignore admits only what these stages COPY). Generated code is
# committed, so the only toolchains here are Flutter (web) and Go.

## --- stage 1: Flutter web build ----------------------------------------------
# Flutter from the official release archive (as tools/goldens.Dockerfile
# does), so the image builds with the SDK the gates ran. The ARG default
# is the pin for compose builds; CI fails if it drifts from the workflows.

# BUILDPLATFORM: the web bundle is arch-independent, so multi-arch builds
# run this stage once, on the build host - which must be x64 (Flutter
# publishes no linux-arm64 SDK archive).
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS web

ARG FLUTTER_VERSION=3.47.1

# git: the flutter tool reads its own SDK version through it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# --no-same-owner: root's tar would keep the packager's uid, and git then
# refuses the SDK as dubiously owned.
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
    && tar xf /tmp/flutter.tar.xz -C /opt --no-same-owner \
    && rm /tmp/flutter.tar.xz
ENV PATH=/opt/flutter/bin:$PATH
# Warms the tool and the web engine artifacts; fails here, not
# mid-compile, on a bad archive. Rebuilds only on a version bump.
RUN flutter --version && flutter precache --web

# Flutter's "running as root" advisory is expected: build stages run as
# root and this one is discarded; the runtime stage is non-root.
WORKDIR /src

# Pub workspace: resolve at the root, build in app/app. Pubspecs first,
# so source edits reuse the resolved layer; a new workspace member needs
# a COPY line here (pub get fails loudly until it gets one).
COPY app/pubspec.yaml app/pubspec.lock app/
COPY app/app/pubspec.yaml app/app/
COPY app/packages/waxdeck_api/pubspec.yaml app/packages/waxdeck_api/
COPY app/packages/waxdeck_api_gen/pubspec.yaml app/packages/waxdeck_api_gen/
COPY app/packages/waxdeck_data/pubspec.yaml app/packages/waxdeck_data/
COPY app/packages/waxdeck_player/pubspec.yaml app/packages/waxdeck_player/
COPY app/packages/waxdeck_player_testing/pubspec.yaml app/packages/waxdeck_player_testing/
COPY app/packages/waxdeck_ui/pubspec.yaml app/packages/waxdeck_ui/
COPY app/packages/waxdeck_ui/example/pubspec.yaml app/packages/waxdeck_ui/example/
RUN cd app && flutter pub get

COPY app/ app/
RUN cd app/app && flutter build web --wasm

## --- stage 2: Go server build -------------------------------------------------
# Cross-compiles from the build host (Go needs no emulation), so multi-arch
# builds stay fast: only the runtime stage below differs per target platform.
FROM --platform=$BUILDPLATFORM golang:1.26 AS build

ENV CGO_ENABLED=0
WORKDIR /src
# Both go.mods: the server module replaces the sibling fixtures module by
# relative path. Download is its own layer so source edits reuse it.
COPY server/go.mod server/go.sum server/
COPY fixtures/go.mod fixtures/go.sum fixtures/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    cd server && go mod download
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
    GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -tags withweb -trimpath \
      -ldflags "-X main.version=${VERSION}" \
      -o /out/waxdeck ./cmd/waxdeck

## --- stage 3: runtime ----------------------------------------------------------
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/ColeSpringer/WaxDeck" \
      org.opencontainers.image.description="WaxDeck: self-hosted player and library manager for music, podcasts, and audiobooks" \
      org.opencontainers.image.licenses="GPL-3.0-only"

# libchromaprint-tools: fpcalc for AcoustID fingerprinting, the single
# external tool this image ships. Decode and DSP are pure Go (WaxFlow
# codec packages); there is no ffmpeg anywhere in the stack.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libchromaprint-tools \
    && rm -rf /var/lib/apt/lists/*

# UID 10001 per the Wax* container convention. Compose overrides it with
# the host user's uid, so /data and /podcasts are world-writable to
# accept any uid without an entrypoint chown dance.
RUN groupadd --system --gid 10001 waxdeck \
    && useradd --system --uid 10001 --gid 10001 --home-dir /data --shell /usr/sbin/nologin waxdeck \
    && mkdir -p /data /library /podcasts \
    && chown waxdeck:waxdeck /data /podcasts \
    && chmod 0777 /data /podcasts

COPY --from=build /out/waxdeck /usr/local/bin/waxdeck
# The artifact conveys its own terms; the binary also prints the
# notices (--third-party-notices).
COPY LICENSE /usr/local/share/doc/waxdeck/LICENSE
COPY --from=build /src/server/internal/notices/third_party_notices.txt /usr/local/share/doc/waxdeck/THIRD-PARTY-NOTICES.txt

ENV WAXDECK_ADDR=0.0.0.0:4420 \
    WAXDECK_DATA_DIR=/data

EXPOSE 4420
USER waxdeck:waxdeck

# The binary dials its own health endpoint (no curl in the image);
# start-interval probes every 2s until first success, so --wait is fast.
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --start-interval=2s \
  CMD ["/usr/local/bin/waxdeck", "-ping"]

ENTRYPOINT ["/usr/local/bin/waxdeck"]
