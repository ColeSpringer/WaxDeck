# F-Droid

Android's channel comes in two halves. The self-hosted repository is
live machinery: `.github/workflows/fdroid.yaml` rebuilds a signed index
from every published release and deploys it to GitHub Pages, so it
needs no per-release chore at all. The fdroiddata submission is the
half that puts WaxDeck in the main F-Droid client's default search, and
that one is a merge request to their repository, prepared here.

## The self-hosted repository

Add it to any F-Droid client with the full line - the fingerprint is
the credential, and a URL without it is refused:

```
https://colespringer.github.io/WaxDeck/repo?fingerprint=18BB5776333A744A3C0519BF9C019C09C745E0FFE5207AF5BF8F4D054D9CBE35
```

How it works, so nobody re-derives it:

1. **Stateless.** Each run rebuilds the repo from one release's per-ABI
   APKs (`armeabi-v7a`, `arm64-v8a`, `x86_64` - the universal APK stays
   on the GitHub Release for sideloaders). Nothing accumulates on
   Pages; republishing is re-running the workflow. Flutter stamps the
   split builds with distinct versionCodes (`abi * 1000 + N`), which is
   what lets the three coexist in one index with every device offered
   its own ABI.
2. **Two keys, one warning.** `deploy/keys/waxdeck-upload.jks` signs
   the APKs (via the `ANDROID_*` secrets `package.yaml` reads);
   `deploy/keys/waxdeck-fdroid-index.p12` signs the repo index (via
   `FDROID_KEYSTORE_BASE64` / `FDROID_KEYSTORE_PASS`). The keys live
   only in `deploy/keys/` (gitignored) and the repository secrets.
   **Back both up off-machine: the upload key is the app's permanent
   identity, and losing it means no installed copy can ever be
   upgraded.**
3. **Wrong signatures cannot enter.** The app metadata pins
   `AllowedAPKSigningKeys` to the upload certificate and the workflow
   asserts every downloaded APK against the same hash, so a
   debug-signed build fails the run loudly instead of poisoning the
   index.
4. **Store texts have one source.** `fastlane/metadata/android/en-US/`
   carries the title, summary, description, and icon (the icon is
   emitted by `make brand`); the workflow reads them into the index and
   fdroiddata reads the same files, so the two listings cannot drift.
5. **Dry runs.** Dispatching the workflow builds the index into a plain
   artifact and touches nothing public; flip `dry_run` off to publish
   outside a release, which is also how a failed release-triggered run
   is redone. Before the first release a dispatch skips gracefully.

If the index key is ever reissued, recompute the fingerprint and update
it in the workflow env, this file, `README.md`, and `docs/releasing.md`:

```sh
keytool -exportcert -keystore deploy/keys/waxdeck-fdroid-index.p12 \
  -alias waxdeck-fdroid -storepass "$(cat deploy/keys/waxdeck-fdroid-index.pass)" \
  | shasum -a 256
```

## What the fdroiddata submission needs

1. **A tagged release.** `metadata-recipe.yml` beside this file is the
   recipe; its PLACEHOLDER notes take the first tag's version, build
   number, and commit. F-Droid builds from source, which is why the
   Android `versionCode` is the pubspec build number rather than a CI
   run number - their build server has to reproduce it from the tree
   alone.
2. **The merge request.** Fork `gitlab.com/fdroid/fdroiddata`, add the
   recipe as `metadata/com.colespringer.waxdeck.yml`, and open the MR.
   Their pipeline lints and test-builds it; expect review rounds. The
   fastlane texts in this repo are picked up automatically.
3. **Reproducibility notes.** The build is
   `flutter build apk --release` against the pinned Flutter (their
   `flutter` srclib, pinned to the same version CI uses) with the
   pubspec-carried versionCode, so there is nothing run-numbered or
   time-stamped in the artifact path. No `gradle-wrapper.jar` is in the
   tree - `.gitignore` excludes it and only the wrapper properties are
   committed - so their binary scanner has nothing to flag: Flutter's
   own tooling supplies Gradle from the SDK's cache when the srclib
   build runs. Do not commit a wrapper jar to "fix" a local build; the
   flutter command never needs one.
4. **Updates after acceptance.** `AutoUpdateMode: Version v%v` +
   `UpdateCheckMode: Tags` mean their bot notices each new `v*` tag and
   opens the version bump on its own; the pubspec release check in
   `package.yaml` is what keeps those tags buildable.

Screenshots are skipped for now; adding
`fastlane/metadata/android/en-US/images/phoneScreenshots/` in any
release is enough to light them up in both listings.
