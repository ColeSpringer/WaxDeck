# ADR-0057: The LAN-cleartext posture

Status: accepted

## Context

WaxDeck's server is one a listener runs. The overwhelmingly common
deployment is a box on a home network reached at `http://192.168.1.x:4420`
with no certificate, because there is no name to get a certificate for
and no authority that would issue one for an RFC 1918 address. The
reverse-proxy guide covers the other case, and it is the minority.

Both mobile platforms refuse that by default, and both refuse it
silently. Android's `targetSdk` 36 blocks cleartext outright: the
request fails, nothing in the UI says why, and the app looks like it
cannot sign in. iOS App Transport Security does the same. Each platform
has its own knob, expressed in its own file, and the temptation is to
answer them one at a time as each platform's build starts failing -
which is how two platforms end up with two different postures and
neither one written down.

The release Android manifest also had no `INTERNET` permission at all
(it lived only in the debug and profile manifests, where Flutter's
template puts it for the hot-reload channel). Every real Android build
this project has produced could not reach the network. That is the same
class of failure as the cleartext block - silent, release-only, fatal to
sign-in - and it argues for the same remedy.

## Decision

**Cleartext is permitted by default, on every platform, as the product's
posture rather than a development shortcut.** Android gets
`res/xml/network_security_config.xml` with
`cleartextTrafficPermitted="true"`; iOS gets `NSAllowsArbitraryLoads`
when its build lands. One decision, recorded once, so the second
platform is a citation rather than a fresh argument.

Scoping it narrower was considered and rejected. Android can permit
cleartext per-domain, and iOS has `NSAllowsLocalNetworking`, but a
self-hosted server has no domain this repo can enumerate - the address
is whatever the listener typed - and "local" is not the boundary either,
since a listener reaching their own server over a VPN or a Tailscale
address is doing the ordinary thing. A rule that cannot name its
exceptions in advance is not a rule.

**User trust anchors are trusted, alongside the system ones.** The
listener who does put a self-signed certificate in front of their server
has already installed its CA on the device; Android ignores user CAs
unless a network-security config asks for them. Refusing them would
punish the more secure configuration, which is backwards. This is the
on-ramp from plain HTTP, not a second hole.

**The permission and the config are asserted on the built APK, in CI.**
A new `android` job builds the release APK and greps `aapt dump` output
for `INTERNET`, `POST_NOTIFICATIONS`, and `networkSecurityConfig`. The
assertion is on the artifact, not the source, so the manifest merge is
part of what is tested - and the bug that motivated this ADR becomes a
permanent regression test rather than a fixed commit.

**Release signing loads from a gitignored `android/key.properties` and
falls back to the debug keystore when it is absent.** Failing the build
instead would break `flutter run --release` and the CI gate above for
everyone without a keystore, to protect against a mistake - shipping a
debug-signed APK - that only Cole is positioned to make and only at the
moment of publishing. What ships is signed locally, where the file
exists.

**R8 was already on, so this is about what it needs, not whether to run
it.** Flutter's Gradle plugin has been defaulting `minify` +
`shrinkResources` for release builds all along; the release path simply
had not been exercised, because those builds could not reach the
network. `proguard-rules.pro` lands empty-but-commented as the obvious
place for the next keep rule (background_downloader's reflective
callbacks are the documented likely one).

**`res/raw/keep.xml` keeps every notification drawable, not only this
app's.** The rule started as the status-bar icon alone, which is named
by a Dart string and would otherwise be stripped. Verifying that on a
release build found the larger half: audio_service's own transport
glyphs are named the same way, from Dart, and the shrinker had removed
all seven. Six of them only draw blank, because `NotificationCompat`
accepts a zero icon. `audio_service_fast_forward` does not - it is the
glyph on the sleep-timer extra, and `CustomAction.Builder` throws
without an icon. That throw lands while the playback state is being
built, so no state ever reached the platform session: no notification,
no lock screen, no Android Auto, and a media service that never went
foreground, for the whole run. Release-only, caught and logged rather
than crashing, and it would have shipped. The rule is a wildcard over
`@drawable/audio_service_*` for that reason: a set owned by a
dependency, named from Dart, is not a list this repo can keep current
by hand.

**macOS gets the two network entitlements and deliberately not the
keychain one.** `Release.entitlements` had only `app-sandbox`, so the
packaged app could not open a connection at all; `network.client` fixes
that, and `network.server` covers the loopback listener OIDC returns
through. `keychain-access-groups` was going to be added beside them on
the strength of flutter_secure_storage's README, and is not, for two
reasons found while doing it. It is a restricted entitlement: its
presence makes the build demand a development certificate, and
`flutter build macos --release` fails outright without one - which would
have broken the packaging workflow, whose whole posture is unsigned
artifacts. And it buys nothing here anyway, because the plugin sets
`kSecAttrAccessGroup` only when the caller passes a `groupId` and
`SecureCredentialStore` constructs a bare `FlutterSecureStorage()`. It
is signing work, and it lands when signing does.

## Consequences

An Android release build now reaches the network, over plain HTTP, to
the address the listener typed - which is what the app is for. The three
silent failures behind that sentence (no `INTERNET`, no cleartext, no
signing config of its own) are closed together because they had one
symptom and one moment of discovery.

The cleartext default will need a justification at store review, if and
when an Android or iOS store build is submitted. The rationale is the
standard self-hosted-server one and it is written above. If a reviewer
refuses it, the narrower fallbacks are `NSAllowsArbitraryLoadsForMedia`
plus an IP-literal exception on iOS, and per-domain rules keyed off a
configured host on Android - both meaningfully worse for the listener,
both available.

Traffic to a listener's own server over their own LAN is unencrypted,
and this is a real property of the default configuration rather than an
oversight. Media tokens are short-TTL and HMAC-signed, so a capture is
not a durable credential, but a session token on the wire is a session
token on the wire. The reverse-proxy guide remains the answer for anyone
whose threat model includes their own network, and user trust anchors
mean a self-signed certificate is now a working middle option.

The notification icon is generated by `tools/generate-brand.py` like
every other brand asset, at five densities, as an alpha silhouette that
Android tints with the accent passed from Dart. The colour crosses the
package boundary as a parameter rather than a constant because
waxdeck_player cannot import waxdeck_ui (ADR-0016), and a second copy of
the amber in the player package would drift from the token.
