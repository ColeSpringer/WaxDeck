# Releasing

Cutting a WaxDeck release is one action: push a tag matching `v*`.

```sh
git tag v0.2.0
git push origin v0.2.0
```

The release workflow (`.github/workflows/release.yaml`) does the rest:

- **Container image.** A multi-arch (linux/amd64 + linux/arm64) build
  of `deploy/Dockerfile`, pushed to `ghcr.io/colespringer/waxdeck` and
  tagged with the git tag and `latest`. It is what `deploy/compose.yaml`
  references, so `docker compose pull` picks up a release without edits
  - or pins one, with `WAXDECK_TAG=v1.2.3` in `.env`. The engine is the
  WaxFlow repo's own image; record the version a release was run
  against beside the WaxSeal note in `docs/configuration.md`, pinned
  with `WAXFLOW_TAG`.
- **Binaries.** The server, with the web UI embedded (`-tags withweb`),
  and the analysis worker, cross-compiled for linux, macOS, and Windows
  on amd64 and arm64 and attached to a GitHub Release created from the
  tag as `waxdeck-server_<version>_<os>_<arch>.tar.gz` and
  `waxdeck-analyzer_<version>_<os>_<arch>.tar.gz` (`.zip` on Windows).
- **Desktop installers.** The packaging matrix
  (`.github/workflows/package.yaml`, reused via `workflow_call`) runs
  with the tag's version and its artifacts are attached to the same
  release: Linux tar.gz, Windows zip, MSIX, the Velopack `Setup.exe`,
  and the full Velopack output as a zip.
- **Android APKs.** From the same matrix: one per ABI
  (`armeabi-v7a`, `arm64-v8a`, `x86_64`) for anyone who cares about
  download size, plus a universal one for anyone who does not know
  which they need. The release call passes `secrets: inherit`, so these
  are the signed builds; see Android signing below for what happens
  without the secrets.

## How the version is stamped

The tag, minus its `v` prefix, becomes the version everywhere:

- The server binary and the images build with
  `-ldflags "-X main.version=<version>"`, the mechanism
  `cmd/waxdeck/main.go` documents. It surfaces in `waxdeck --version`,
  the startup log, and the `waxdeck_build_info` metric. Local builds
  keep the in-source `0.1.0-dev` default.
- The desktop matrix receives it as the `pack_version` input, which
  sets the Velopack package version and the artifact names.
- The Android APKs take it as `--build-name`, which is the version
  name a user sees.

Two version numbers are not stamped from the tag, and both live in
`app/app/pubspec.yaml`, so both are part of preparing a release:

- `msix_version`, a four-part number, for the Windows MSIX.
- The pubspec build number (the `+N` in `version: 0.1.0+1`), which
  becomes the Android `versionCode`. Android decides what counts as an
  upgrade by that integer alone, so it has to rise with every published
  APK. It is deliberately not derived from the run number: F-Droid
  builds from source and needs a `versionCode` the source tree can
  produce on its own.

  The release build checks both halves and refuses to build without
  them: the version name has to equal the tag, and `N` has to rise
  above whatever the previous `v*` tag's pubspec carried. It is checked
  rather than trusted because the failure is otherwise invisible. Two
  releases sharing a `versionCode` still install by hand, since Android
  only refuses a downgrade; what they do not do is *update*. F-Droid
  and every other updater decide whether a new version exists by
  comparing that integer, so an unbumped release reaches nobody
  automatically, and re-tagging cannot fix it once the APK is
  published.

  The comparison is skipped for the first release, and warns rather
  than fails if the previous tag's pubspec has no build number to read.
  It is the only reason the Android job clones full history.

## What the web bundle weighs

The server binaries carry the web UI inside them (`-tags withweb`), so
the bundle is both a download budget for browsers and a floor under the
binary. Measured on Flutter 3.50.1, `make web`, WasmGC target:

| First paint | Raw | gzip |
|---|---|---|
| `main.dart.wasm` (the app) | 6.27 MB | 2.25 MB |
| `canvaskit/skwasm.wasm` (the renderer) | 3.45 MB | 1.48 MB |
| Eager fonts (Archivo, Inter, Spline Sans Mono, two Phosphor subsets) | 1.34 MB | 634 KB |
| The engine's default Roboto and the Material icon subset | 64 KB | 63 KB |
| Loader, glue, manifests, `index.html` | 166 KB | 61 KB |
| Brand emblem and favicon | 84 KB | 84 KB |
| **Total** | **11.4 MB** | **4.54 MB** |

Nothing else is fetched to draw the first screen. Firefox runs the same
wasm build, drawn by `skwasm_heavy.wasm` (4.99 MB, 2.19 MB gzipped) in
place of `skwasm.wasm`: it lacks the codecs and break iterators the
smaller renderer leans on. What is on disk and not in that total:

- **`main.dart.js`, 6.73 MB** (1.90 MB gzipped). The JS build, for
  Safari (kept on it, see docs/deferred-work.md) and for browsers that
  cannot run the wasm build, fetched *instead of* the wasm, never beside
  it.
- **The rest of `canvaskit/`, 33 MB.** Every renderer variant Flutter
  ships: CanvasKit with its Chromium and WebParagraph builds,
  `skwasm_heavy`, WIMP, and the `.symbols` files for each. One is
  loaded, and the loader picks it. They are embedded because the engine
  resolves them at runtime from this origin and a LAN-only instance
  cannot reach Google's CDN.
- **On-demand fonts.** Twenty deferred faces, about 34 MB in all -
  Noto Sans CJK at 16 MB and the colour emoji face at 10.4 MB are the
  bulk, the fifteen script faces plus Arabic, Thai, and Hebrew the rest
  (`waxdeck_ui/assets/fonts/README.md` carries the list) - each fetched
  only when metadata in its script appears on screen. CJK is unsubset
  by decision: a curated core still renders tofu for names outside it.
- **`NOTICES`, 1.55 MB**, fetched only if somebody opens the licence
  page.

The whole embedded tree is about 86 MB, which is what a server binary
gains from `-tags withweb`. Note that WaxDeck serves these
uncompressed; a reverse proxy that compresses is worth roughly the
gzip column on every cold load.

A warm load fetches almost none of it. The build names the entrypoints
and everything under `assets/` after their content
(`tools/build-web.sh`), and the server answers a file whose name
carries its own hash with a year's `immutable` caching. Everything else,
`index.html` and `flutter_bootstrap.js` first, is revalidated against
its ETag, so a deploy is picked up on the next load.

Re-measure when the engine version moves or when a font joins the eager
chain.

## Android signing

The release build type signs with a keystore loaded from
`app/app/android/key.properties`, and falls back to the debug keystore
when that file is absent - so a fresh clone and CI both keep building.
The file and `*.jks` are gitignored; nothing about the key is in the
repo.

The fallback answers "no keystore configured", not "keystore configured
badly". A `key.properties` that exists but names a file that does not
fails the build outright:

```
Execution failed for task ':app:validateSigningRelease'.
> Keystore file '/home/you/waxdeck-upload.jks' not found for signing config 'release'.
```

That is deliberate. Writing the file is how you declare an intent to
sign, and quietly downgrading a typo'd path to debug keys would hand
back an APK that looks publishable and is not.

Make the keystore once and keep it somewhere durable. Losing it means
no existing installation can ever be upgraded, because Android
identifies an app by its signature:

```sh
keytool -genkey -v -keystore ~/waxdeck-upload.jks -alias waxdeck \
  -keyalg RSA -keysize 4096 -validity 10000
```

Then `app/app/android/key.properties`, with `storeFile` relative to
`app/app/android/` (or absolute):

```properties
storeFile=/Users/you/waxdeck-upload.jks
storePassword=...
keyAlias=waxdeck
keyPassword=...
```

`flutter build apk --release` picks it up with no flag. Confirm which
key an APK actually carries before publishing it - the fallback is
silent by design:

```sh
"$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs app-release.apk
```

A debug-signed APK answers `CN=Android Debug`, which is the one thing
this check exists to catch. Not `keytool -printcert -jarfile`: that
reads v1 JAR signatures, `minSdk 24` means AGP signs v2/v3 only, and it
answers `Not a signed jar file` for a perfectly well-signed APK.

For CI signing, four secrets carry the same four values, with the
keystore base64-encoded (`base64 -i ~/waxdeck-upload.jks`) since a
secret is text: `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The packaging job decodes
the keystore and writes `key.properties` before building; absent them
it produces debug-signed APKs, which are installable for testing and
not publishable.

The job runs on every push to main, but it only signs when the release
workflow called it. Repository secrets reach a push build too, and
using them there would put the upload key on four publicly
downloadable artifacts per merge - which Android cannot tell apart
from a release, and which would then block the real one, since a
device refuses a same-signature APK whose `versionCode` did not rise.
Push builds are debug-signed instead. To check the secrets without
cutting a tag, run the workflow by hand with `sign_android` on.

One catch worth knowing: a called workflow receives no secrets unless
the caller says so, which is why `release.yaml` invokes the matrix
with `secrets: inherit`. Drop that line and the release quietly ships
debug-signed APKs. Note that `github.event_name` cannot be used to
detect the call - inside a called workflow it reports the *caller's*
event, which for a release is `push`. The signal is a non-empty
`inputs.pack_version`, which is also what the version stamping uses.

The same builds by hand, from `app/app`:

```sh
flutter build apk --release --split-per-abi   # per-ABI
flutter build apk --release                   # universal
```

Both land in `build/app/outputs/flutter-apk/`. Add
`--build-name=<version>` to stamp a version name the way CI does;
without it the pubspec version is used.

## After the workflow finishes

Desktop package-channel manifests are updated by hand per release; the
templates and per-channel notes live in `deploy/packaging/`. Fill in
the new version and artifact checksums for winget, the AUR, and
Flathub as each channel opens.

Android needs no per-release chore: publishing the release triggers
`.github/workflows/fdroid.yaml`, which rebuilds the self-hosted
F-Droid repository's signed index over the new per-ABI APKs and
redeploys it to GitHub Pages. Anyone adds the repository with the full
line - the fingerprint is the credential, and a URL without it is
refused:

```
https://colespringer.github.io/WaxDeck/repo?fingerprint=18BB5776333A744A3C0519BF9C019C09C745E0FFE5207AF5BF8F4D054D9CBE35
```

The fdroiddata submission - the main F-Droid catalogue - is prepared
in `deploy/packaging/fdroid/` and waits on the first tag; once
accepted, their bot opens each new tag's version bump on its own. Both
halves and the signing keys are documented in
`deploy/packaging/fdroid/README.md`; the keys themselves live in
gitignored `deploy/keys/`, which wants an off-machine backup.

The desktop artifacts are not signed. The Windows ones are unsigned,
which blocks the winget submission outright; the release notes should
say so until signing lands. Android is the exception in kind rather
than degree: an APK must be signed to install at all, so an unsigned
build is not a thing that exists. With the four secrets set it carries
the upload key and is publishable; without them it is debug-signed,
which installs for testing and cannot be published.

The desktop app has no self-updater, so releases propagate through
package managers and direct downloads only; there is no update channel
to feed beyond the GitHub Release itself.
