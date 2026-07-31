# 37. The settings registry, and which store a setting lives in

Date: 2026-07-31

## Status

Accepted.

## Context

Settings was one screen: a `ListView` of headings with the account, the
theme dropdown, the device list, and every integration section stacked
under each other. It had grown to the point where finding anything meant
scrolling past everything, and the layout blueprint asks for eight
sections plus Account with a search field over them.

Four things were waiting on it, each recorded in `docs/deferred-work.md`
and each blocked on the same thing - a control:

- **Crossfade and ReplayGain did not feed timelines.** The mint has taken
  a crossfade since it was built and the gain parameter has always been
  explicit; both were hard-coded to nothing, because nowhere stored what a
  listener wanted.
- **No wifi-only switch for gapless preloading.** Playback prepares the
  next entry thirty seconds early with no way to hold that back on mobile
  data. The per-device store existed (ADR-0027); the connectivity port did
  not.
- **Spoken-word skip intervals were constants.** The deck bar jumped 15
  back and 30 forward, which is what every client ships and not what
  everyone wants.
- **Radio scrobbling had no off switch** (API item 14), which is wrong for
  anyone whose station's stream titles parse but are not worth reporting.

## Decision

### Nine locations, not one screen

`/settings` is a search field and a list of sections; each section is
`/settings/:section` and a location a stranger can open, so "it is under
Playback" is a link rather than directions. Sections are drilled into and
leave to the settings home, including when opened cold.

An unknown segment redirects to the settings home rather than drawing a
blank section: the segments are a closed set, so anything else is a typo
or a link from a build that named them differently.

**About is a location too**, `/settings/about`, declared ahead of the
`:section` pattern so the literal wins over it. It was pushed as a
`MaterialPageRoute` first, on the reasoning that no location under
settings would land a stranger anywhere sensible - which is wrong, and
8.3 answers it directly: a stranger opening `/settings/about` gets the
page, exactly as they do for `/settings/playback`. Pushing cost a
shareable link, an F5 that stayed put, and a route-table entry, and
bought nothing. Back lands on the settings home rather than on the
section it was opened from, which is what a location declared beneath
`/settings` means and is equally true of every section.

The section screen carries **no semantics identifier of its own**. The
obvious one is the row's, and using it makes one handle name two
different things - a retried click meant for the row lands in the middle
of the screen it already opened. The e2e suite found this by opening the
timezone dialog when it meant to reach About.

### The registry is the thing that makes it findable

Every leaf setting has an entry: an id, a title, the section it lives in,
and the words somebody would search by that are not in the title
("loudness" for ReplayGain, "gapless" for the preload switch). The field
at the top of the settings home searches those, and the command palette
will read the same list.

The ranking is three tiers and no scoring - title-starts-with, then
title-contains, then keyword. A fuzzy score would order "Density" against
"Display name" for the query "d" on a tie-break nobody could predict, and
the list is short enough that the honest ordering is the useful one.

The registry is a `const` list beside the sections rather than something
derived from the widgets, because a widget tree cannot be searched before
it is built. `settings_registry_test.dart` is what keeps the two together:
it mounts every section and fails on a registered setting no section
draws, which is the failure that matters - search offers a row, the row
opens a section, and the setting is not in it.

An entry may name a handle other than `setting-<id>` where the control
predates the registry (the theme picker, the timezone row) or where the
entry names a group rather than one control (the device list, app
passwords). Those groups are wrapped in a `Semantics` node carrying the
registry's handle, so the check presses something real either way.

### Which store a setting lives in, revisited

ADR-0027 drew the line: the account's synced `Prefs` document holds what
follows a listener to a new phone, and the per-device store holds what
describes the machine in front of them. Three settings this phase adds
sit on the account side for a reason that line did not anticipate.

**`crossfadeSeconds`, `replayGain`, and `radioScrobbleOptOut` join
`Prefs`** (additive, `oasdiff` clean). The first two are not there because
they follow a listener - they are there because **the server is what
applies them, and the client is not in the loop when it does**. A cast
session is re-rendered server-side on every queue edit, shuffle, and
repeat reload, and those arrive over the control socket carrying no client
state at all. A per-device value would reach the first load and none of
the reloads, so a queue would change how it sounds halfway through.
`radioScrobbleOptOut` is the same shape from the other end: the stream
proxy reports a finished radio segment with a user id and nothing else.

This is not section 11's item 18 (syncing per-device settings for
convenience), which stays untaken. It is a narrower rule, and it belongs
beside ADR-0027's: **a preference the server acts on lives on the
account**, because a device that is not present cannot supply it.

The connect resolver reads those preferences itself rather than taking
them as parameters. The `MediaResolver.Timeline` port dropped its
`crossfade` argument entirely: both call sites passed a literal zero, and
a parameter that is passed correctly on the first load and as a zero on
every reload after it is a trap with a shape. The owner's preferences are
read, never the caller's - a household member driving somebody else's cast
session must not rewrite how it sounds.

### What ReplayGain means for a timeline

One gain for the whole stream, because that is the only thing a timeline
can express: the members render into one continuous stream and there is no
seam at which a gain could change. So it is derived the way album gain is
- from the program as a whole - by weighting each measured member's
integrated loudness by how long it plays, against a -18 LUFS reference.

Three rules fall out of that:

- A member with no stored measurement is carried at the gain the measured
  ones produced, which is what an unanalyzed track in the middle of an
  analyzed album should do.
- A queue where **nothing** is measured levels nothing: the mint asks for
  `gain=off` rather than inventing a number. Since `Library.Analyze` is
  opt-in and most deployments have never run it, this is the common case,
  and it is why the setting's help says "where the files have been
  analyzed" rather than promising leveling.
- Where a true peak is known it beats the target, downward only. Clipping
  is the one failure a listener cannot undo by reaching for the volume, so
  a quiet-but-peaky master is held at the headroom line instead of being
  squared off.

### The connectivity port

`connectivity_plus` is pinned exact behind `ConnectivityPort`, which
answers two values - unmetered or metered - rather than the plugin's list
of transports. Two is what both callers ask.

The platform's own metered flag would be the exact answer and no plugin
exposes it portably (Android has `isActiveNetworkMetered`, iOS has
`NWPathMonitor.isExpensive`, neither is on this plugin's surface). The
transport is the honest stand-in, and it happens to be the question the
settings themselves ask: they say "on wifi only", not "on an unmetered
connection".

Unknown reads as metered. The direction is deliberate: holding a preload
back on a connection that turned out to be free costs one track's
buffering, and getting it wrong the other way spends somebody's data plan.
A plugin that will not answer at all reads as unmetered instead, because
that is what the app did before this port existed - a failure here must
not silently impose a new restriction.

The two switches over it differ in default and in mechanism.
**Preloading** defaults off, is checked at the moment of arming, and is
not remembered as a refusal, so a listener who walks indoors mid-track
gets the gapless crossing. **Downloading** defaults on and is a
*constraint handed to the platform* (`DownloadTask.requiresWiFi`) rather
than a check WaxDeck makes: a download queued on mobile data starts by
itself once the listener is home, where a refusal would need the app
reopened to notice.

### Two new design-system primitives

`WaxSwitch` and `WaxChoice` join `waxdeck_ui`, for the same reason
`WaxSlider` did in P14: settings are the switch-heavy surface and the
package had neither.

`WaxSwitch` announces as a switch rather than as a button, because a
switch's state is the point and `toggled` is what a screen reader reads
out - which is why it does not simply wrap `WaxTappable`.

`WaxChoice` draws its current value rather than hiding behind an icon like
`WaxMenuButton`, because that is what somebody scrolling a section is
reading. It shipped, briefly, focusable and keyboard-operable and
completely deaf to taps: `WaxTappable` contributes semantics, the focus
flag, and the ring and adds *no gesture*, which its own doc says and which
is easy to read as "it handles the tap". The widget tests caught it.

Both take a nullable handler, so a control whose value has not loaded is
drawn and announced disabled rather than looking live and dropping the
choice. `settings_controls_test.dart` presses both paths into each - a
pointer tap and a screen reader's activation - and asserts each fires
exactly once, because two ways in is what that split leaves and two menus
stacking is what it would look like.

**A disabled control was still a tab stop.** `WaxTappable` declared
`focusable: enabled` and handed `Semantics` a focus action regardless, and
supplying that action marks a node focusable whatever the flag says - so
every disabled control in the app advertised itself as somewhere a
keyboard could land and then do nothing. Now gated with the flag beside
it, in `WaxTappable` and `WaxSwitch` both. Found by writing the disabled
case's assertion strictly rather than around the behaviour.

### The app version is generated

About reports the app's version, the server's, and the API number, which
is the whole of what a bug report is asked for. Flutter exposes no version
at runtime without a plugin, so `tools/gen-app-version.dart` emits it from
the pubspec into a checked-in constant, wired into `make generate` and
gated by `make drift-check` like every other generated artifact. Adding a
plugin for one string was the alternative and is worse.

The licenses page is Flutter's own `showLicensePage`. The bundled OFL
texts and the icon set's MIT notice reach it without this screen
collecting them: they are in `waxdeck_ui`'s package LICENSE, which is what
the relicensing change made convey them.

## Consequences

Four deferred entries close: crossfade and ReplayGain feeding timelines,
the wifi-only preload switch, the spoken-word skip intervals, and the
radio-scrobbling off switch.

**What 6.13 asks for and this does not ship**, each recorded in
`docs/deferred-work.md` rather than half-built:

- Smart rewind on resume, sleep-timer extension gestures, and the web
  autoplay-overlay preference. Each needs a mechanism that does not exist
  yet, not a control.
- Trim-silence and voice-boost defaults. The seam is the same one the
  speed defaults now use (`_configuredSpeed`'s `?? defaultSpeed`), so
  these are small - they were left out because a default that silently
  turns silence trimming on for every show is a decision worth its own
  look, where a speed is not.
- Browse defaults (unknown buckets, default sorts), the artwork-glow
  toggle, always-show captions, and language. The first three have no
  reader to wire to; language has no localization behind it, and a picker
  that changes nothing is worse than an absent one.
- Auto-remove finished episodes. The manual action exists on the downloads
  screen; making it automatic wants a sweep with its own timing rules.
- Renaming this device's session. The read surface has the label; there is
  no write endpoint for it.

**The technical-details toggle governs one chip today** - the album
screen's codec label. That is thin and it is honest: `CodecChip` and
`MonoDetailRow` are drawn in four other places and all of them are
bibliographic (a book's ISBN) or admin curation, neither of which the
switch should hide. The player rebuilds in P18 to P20 add the rest.

**The device list stopped naming browsers by their whole user agent.**
`clientHint` stored the header truncated to 128 bytes, so a row read
"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML,
like Gecko) Chrome/151..." - in a list somebody is deciding what to revoke
from, where every browser on earth begins identically. `summarizeClient`
now reduces a browser agent to the two facts that tell one session from
another ("Chrome on Windows") and leaves anything else alone, because a
real client names itself perfectly well ("Symfonium/12.3").

The token table's order *is* its correctness and reads backwards: every
Chromium browser claims to be Chrome, Chrome claims to be Safari, and
Safari claims to be Mozilla, so the most specific marker is tested first
and Safari - the only one claiming nothing else - is last. Same for
platforms: an iPad reports "Mac OS X" beside "iPad", and Android reports
"Linux" beside "Android".

It runs on the read path as well as the write path, so a session stored
before the server learned this reads the same as one stored after. That
is safe because the summary is idempotent by construction - it carries no
browser token, so it falls through the recognizer unchanged - and a test
says so, since the read path depends on it.
