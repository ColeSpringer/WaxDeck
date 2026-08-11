# Package channels

Manifests and notes for distributing the WaxDeck clients through
package managers. Each subdirectory covers one channel; the real
submissions live in that channel's own repository (winget-pkgs, the
AUR, Flathub, fdroiddata). The templates carry placeholder versions and
checksums until the first real release exists; every `PLACEHOLDER` note
says what to fill in and where the value comes from.

Updating the desktop channels is a per-release chore: after the release
workflow publishes a tag's artifacts (see `docs/releasing.md`), copy
each template, fill in the version and the artifact's SHA-256, and
submit it to the channel. None of that is automated yet; when a release
cadence exists, tools like winget-releaser can take over. Android is
the exception in both directions: the self-hosted F-Droid repository
republishes itself on every release, and after the fdroiddata
submission is accepted their bot opens the version bumps.

## Channels

- `winget/` - a winget-pkgs manifest set (version, installer,
  defaultLocale) for the Velopack `Setup.exe`. Blocked on code signing:
  winget moderation rejects unsigned installers, and ours are unsigned
  today.
- `aur/` - a `PKGBUILD` for the Linux tar.gz bundle (binary package,
  `waxdeck-bin`).
- `flathub/` - a README describing the Flathub submission. The flatpak
  manifest itself lives at `deploy/flatpak/com.colespringer.WaxDeck.yml`
  and is not duplicated here.
- `fdroid/` - the Android channel, both halves: how the self-hosted
  repository works (`.github/workflows/fdroid.yaml` owns it) and the
  fdroiddata recipe to submit once the first tag exists.

## Auto-update rule

A build installed through a package manager must never update itself;
the package manager owns upgrades. Only direct-download installs (the
GitHub Release zip, tar.gz, or Velopack setup) may ever self-update.

Today this rule is trivially satisfied: **the desktop app has no
self-updater built in at all**. Velopack appears in CI purely as a
packaging format (`vpk pack` produces the Windows installer); the app
never links or runs Velopack update code, and there is no Sparkle or
other updater on any platform. Nothing needs channel detection because
nothing updates itself. If a self-updater is ever added for
direct-download installs, it must detect package-manager installs
(winget, Flathub, AUR, F-Droid) and disable itself there; until then,
"package managers own updates" is the whole story.
