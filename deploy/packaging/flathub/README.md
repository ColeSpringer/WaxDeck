# Flathub submission

The flatpak manifest is `deploy/flatpak/com.colespringer.WaxDeck.yml`;
it is deliberately not duplicated here. This note lists what a Flathub
submission needs beyond that manifest.

## What Flathub requires

1. **A source it can build from.** The current manifest bundles a
   locally built Flutter bundle via a `type: dir` source, which only
   works on a machine that has already run `flutter build linux`.
   Flathub builders need a fetchable, checksummed source: change the
   module to a `type: archive` source pointing at the release tarball
   (`waxdeck-linux-x64-<version>.tar.gz` from the GitHub Release) with
   its `sha256`, updated per release.
2. **AppStream metainfo.** A `com.colespringer.WaxDeck.metainfo.xml`
   installed to `/app/share/metainfo/`, with a name, summary, long
   description, at least one screenshot URL, an OARS content rating,
   and a `<releases>` entry per version. Flathub validates this with
   `flatpak-builder-lint` and rejects manifests without it.
3. **Desktop entry and icons.** A `com.colespringer.WaxDeck.desktop`
   file and icons (at least 128x128 PNG or scalable SVG) installed
   under `/app/share/applications/` and `/app/share/icons/hicolor/`,
   both named after the app id. The icons exist: a full hicolor tree
   (16 through 512, from the official mark) lives at
   `app/app/linux/icons/hicolor/` and ships inside the release tarball
   as `icons/`, so the module installs them from the archive - renaming
   to the app id - rather than needing new art.
4. **The submission itself.** A PR against
   `github.com/flathub/flathub` (new-pr branch) containing the
   manifest; after acceptance Flathub creates a dedicated
   `flathub/com.colespringer.WaxDeck` repo where per-release bumps
   land as PRs (checksum + version + metainfo release entry).
5. **Permissions review.** The manifest's `finish-args` are reviewed;
   the current set (wayland/x11 fallback, pulseaudio, network, dri) is
   modest and should pass without argument.

## Updates

Flathub builds update through Flathub itself; the app has no built-in
self-updater, so there is nothing to disable in the sandboxed build.
Per release: bump the archive URL and sha256, add the metainfo release
entry, open the bump PR.
