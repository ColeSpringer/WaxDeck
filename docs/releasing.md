# Releasing

Cutting a WaxDeck release is one action: push a tag matching `v*`.

```sh
git tag v0.2.0
git push origin v0.2.0
```

The release workflow (`.github/workflows/release.yaml`) does the rest:

- **Container images.** Multi-arch (linux/amd64 + linux/arm64) builds
  of `deploy/Dockerfile` and `deploy/Dockerfile.waxflow`, pushed to
  `ghcr.io/colespringer/waxdeck` and
  `ghcr.io/colespringer/waxdeck-waxflow`, each tagged with the git tag
  and `latest`. These are the images `deploy/compose.yaml` references,
  so `docker compose pull` picks up a release without edits.
- **Server binaries.** The server cross-compiled for linux, macOS, and
  Windows on amd64 and arm64, each with the web UI embedded
  (`-tags withweb`), attached to a GitHub Release created from the tag
  as `waxdeck-server_<version>_<os>_<arch>.tar.gz` (`.zip` on
  Windows).
- **Desktop installers.** The packaging matrix
  (`.github/workflows/package.yaml`, reused via `workflow_call`) runs
  with the tag's version and its artifacts are attached to the same
  release: macOS dmg, Linux tar.gz, Windows zip, MSIX, the Velopack
  `Setup.exe`, and the full Velopack output as a zip.

## How the version is stamped

The tag, minus its `v` prefix, becomes the version everywhere:

- The server binary and both images build with
  `-ldflags "-X main.version=<version>"`, the mechanism
  `cmd/waxdeck/main.go` documents. It surfaces in `waxdeck --version`,
  the startup log, and the `waxdeck_build_info` metric. Local builds
  keep the in-source `0.1.0-dev` default.
- The desktop matrix receives it as the `pack_version` input, which
  sets the Velopack package version and the artifact names.
- The MSIX version is the exception: `msix_version` lives in
  `app/app/pubspec.yaml` (a four-part number), so bump it there as
  part of preparing a release.

## What the web bundle weighs

The server binaries carry the web UI inside them (`-tags withweb`), so
the bundle is both a download budget for browsers and a floor under the
binary. Measured on Flutter 3.44, `make web`, WasmGC target:

| First paint | Raw | gzip |
|---|---|---|
| `main.dart.wasm` (the app) | 5.31 MB | 1.84 MB |
| `canvaskit/skwasm.wasm` (the renderer) | 3.42 MB | 1.46 MB |
| Eager fonts (Archivo, Inter, Spline Sans Mono, two Phosphor subsets) | 1.33 MB | 615 KB |
| Loader, glue, manifests, `index.html` | 145 KB | 41 KB |
| **Total** | **10.2 MB** | **3.95 MB** |

Nothing else is fetched to draw the first screen. What is on disk and
not in that total:

- **`main.dart.js`, 5.76 MB** (1.51 MB gzipped). The JS fallback for
  browsers without WasmGC, fetched *instead of* the wasm, never beside
  it.
- **The rest of `canvaskit/`, 33 MB.** Every renderer variant Flutter
  ships - CanvasKit, the Chromium build, the multi-threaded
  `skwasm_heavy`, WIMP, and the `.symbols` files for each. One is
  loaded; the loader picks it, and the app pins single-threaded skwasm
  (see the deferred-work entry on flutter/flutter#190039). They are
  embedded because the engine resolves them at runtime from this origin
  and a LAN-only instance cannot reach Google's CDN.
- **On-demand fonts.** Noto Sans CJK 15.7 MB, Arabic 598 KB, Thai
  89 KB, Hebrew 32 KB - fetched only when metadata in those scripts
  appears on screen. CJK is unsubset by decision (ADR-0016): a curated
  core still renders tofu for names outside it.
- **`NOTICES`, 1.49 MB**, fetched only if somebody opens the licence
  page.

The whole embedded tree is 67.5 MB, which is what a server binary
gains from `-tags withweb`. Note that WaxDeck serves these
uncompressed; a reverse proxy that compresses is worth roughly the
gzip column on every cold load.

Re-measure when the engine version moves, when a font joins the eager
chain, or when the single-threaded skwasm force is lifted.

## After the workflow finishes

Package-channel manifests are updated by hand per release; the
templates and per-channel notes live in `deploy/packaging/`. Fill in
the new version and artifact checksums for winget, Homebrew, the AUR,
and Flathub as each channel opens.

Nothing is signed yet. The Windows and macOS artifacts are unsigned
and unnotarized, which blocks the winget submission outright and makes
Gatekeeper quarantine the dmg; the release notes should say so until
signing lands.

The desktop app has no self-updater, so releases propagate through
package managers and direct downloads only; there is no update channel
to feed beyond the GitHub Release itself.
