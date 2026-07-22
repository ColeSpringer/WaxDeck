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
