# Homebrew cask (template) for the WaxDeck desktop client (macOS dmg).
#
# Lives in a tap (e.g. ColeSpringer/homebrew-waxdeck) to start;
# homebrew-cask core has notability and notarization expectations the
# project does not meet yet.
#
# PLACEHOLDERS per release:
#   - version: release tag without the v (the url derives from it)
#   - sha256: `shasum -a 256 waxdeck-macos-<version>.dmg`
#
# The dmg is unsigned and unnotarized today, so Gatekeeper quarantines
# it; document `xattr -d com.apple.quarantine` or ship `--no-quarantine`
# guidance until notarization lands.
cask "waxdeck" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/ColeSpringer/WaxDeck/releases/download/v#{version}/waxdeck-macos-#{version}.dmg"
  name "WaxDeck"
  desc "Self-hosted player and library manager for music, podcasts, and audiobooks"
  homepage "https://github.com/ColeSpringer/WaxDeck"

  # The app has no built-in self-updater; brew owns upgrades.
  auto_updates false

  # Bundle name comes from PRODUCT_NAME in
  # app/app/macos/Runner/Configs/AppInfo.xcconfig.
  app "waxdeck.app"

  zap trash: [
    "~/Library/Application Support/com.colespringer.waxdeck",
    "~/Library/Preferences/com.colespringer.waxdeck.plist",
  ]
end
