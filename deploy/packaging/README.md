# Package channels

Manifests for distributing the WaxDeck desktop client through package
managers. Each subdirectory is a template for one channel; the real
submissions live in that channel's own repository (winget-pkgs,
homebrew-cask or a tap, the AUR, Flathub). These templates carry
placeholder versions and checksums until the first real release exists;
every `PLACEHOLDER` note says what to fill in and where the value comes
from.

Updating is a per-release chore: after the release workflow publishes a
tag's artifacts (see `docs/releasing.md`), copy each template, fill in
the version and the artifact's SHA-256, and submit it to the channel.
None of this is automated yet; when a release cadence exists, tools like
winget-releaser and a Homebrew tap with a bump workflow can take over.

## Channels

- `winget/` - a winget-pkgs manifest set (version, installer,
  defaultLocale) for the Velopack `Setup.exe`. Blocked on code signing:
  winget moderation rejects unsigned installers, and ours are unsigned
  today.
- `homebrew/` - a cask for the macOS dmg. Works from a personal tap
  immediately; homebrew-cask core has notability and notarization
  expectations, so start with the tap.
- `aur/` - a `PKGBUILD` for the Linux tar.gz bundle (binary package,
  `waxdeck-bin`).
- `flathub/` - a README describing the Flathub submission. The flatpak
  manifest itself lives at `deploy/flatpak/com.colespringer.WaxDeck.yml`
  and is not duplicated here.

## Auto-update rule

A build installed through a package manager must never update itself;
the package manager owns upgrades. Only direct-download installs (the
GitHub Release dmg, zip, tar.gz, or Velopack setup) may ever
self-update.

Today this rule is trivially satisfied: **the desktop app has no
self-updater built in at all**. Velopack appears in CI purely as a
packaging format (`vpk pack` produces the Windows installer); the app
never links or runs Velopack update code, and there is no Sparkle or
other updater on any platform. Nothing needs channel detection because
nothing updates itself. If a self-updater is ever added for
direct-download installs, it must detect package-manager installs
(winget, Homebrew, Flathub, AUR) and disable itself there; until then,
"package managers own updates" is the whole story.
