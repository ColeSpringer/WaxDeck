import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import 'client_prefs.dart';

/// The caller's synced preferences. Empty while signed out; refetched when
/// the session changes.
class PrefsController extends AsyncNotifier<Prefs> {
  /// The write in flight, so the next one starts from what it stored.
  ///
  /// The endpoint replaces the whole document and the server takes the last
  /// writer, so two overlapping writes each build from the same loaded
  /// value and the second has never heard of the first. Here rather than
  /// per caller because the unit at risk is the document: a pin racing a
  /// theme change loses the theme as quietly as one pin loses another.
  ///
  /// Cleared when the newest write settles, and only by that write: one
  /// queued behind it owns the flag from the moment it queues. Never
  /// clearing it would stop [build] ever issuing a GET again, so a
  /// change made on another device would never land.
  Future<void>? _writing;

  /// The newest document this client knows, and the account it belongs
  /// to: the in-flight change while a write is running, the server's
  /// answer once it lands.
  ///
  /// This provider sits in the user fan-out, so the server's own event
  /// for a write invalidates it, and every rebuild reads back through
  /// `.value` - which is what the radio dial and the pinned shelf
  /// recompute their lists from. Without a held document that rebuild
  /// answers from the last *settled* one, which has never heard of the
  /// writes still in flight, and the optimistic list is replaced by a
  /// stale one under the thumb that made it. Three pins in a row then
  /// settle on the document the first one wrote.
  ///
  /// Held rather than awaited on purpose: `_write` resolves the loaded
  /// value with `await future`, and a [build] that awaited the write
  /// would deadlock against one started before the first fetch landed -
  /// which is precisely the early-tap case [setRadioFavorites] exists
  /// to handle.
  Prefs? _stored;
  String? _storedFor;

  /// The last document the server itself handed back, from a read or a
  /// write. It is what a refused write reverts to: the optimistic copy
  /// claims a change the server would not take, and reverting to the
  /// document as it stood one write ago would re-assert an earlier
  /// change that was refused too. Queued writes re-apply their own on
  /// top when their turn comes, so the revert costs nothing that is
  /// still wanted.
  Prefs? _confirmed;

  /// Bumped every time a write publishes a document, so a read can tell
  /// whether one landed while it was in flight.
  int _writes = 0;

  @override
  Future<Prefs> build() async {
    final session = await ref.watch(authControllerProvider.future);
    if (!session.authenticated) {
      _forget(null);
      return const Prefs();
    }
    // A different account is not a stale document, it is somebody
    // else's: drop it rather than answering this session with it.
    final owner = session.user?.id ?? '';
    if (owner != _storedFor) _forget(owner);

    // Watched before the early return below, not after it: a build that
    // answers from the held document still depends on the repository,
    // and skipping the watch would drop it from this build's dependency
    // set.
    final repository = ref.watch(repositoryProvider);
    final held = _stored;
    if (_writing != null && held != null) return held;
    final before = _writes;
    final fetched = await repository.getPrefs();
    // A write that landed while this read was in flight is newer than
    // what the read was served, whatever order the two answers arrived
    // in. Without this the first write of a session has no held
    // document to answer with, so the read goes out, and a poll racing
    // a PUT is exactly how the document loses an update.
    final landed = _stored;
    if (_writes != before && landed != null) return landed;
    _stored = fetched;
    _confirmed = fetched;
    return fetched;
  }

  /// Drops every document held for the previous session.
  void _forget(String? owner) {
    _stored = null;
    _confirmed = null;
    _storedFor = owner;
  }

  /// Replaces the document, one write at a time. [change] runs against the
  /// loaded value after any queued write has landed.
  Future<void> _write(Prefs Function(Prefs current) change) {
    // Published here, synchronously with the call, and not only from
    // the body below. The body is deferred, and an invalidation can
    // arrive before it has started - the server's echo of the previous
    // write is one, and so is a second tap, because reading a dirty
    // provider rebuilds it. Every such rebuild recomputes the dial and
    // the pinned shelf from `.value`, so a document that does not yet
    // hold this change replaces the optimistic list with a stale one,
    // and the next toggle is computed from that. Three taps in a row
    // then settle on the first one.
    //
    // Skipped while nothing is loaded: there is no document to change
    // yet, and the body's `await future` is what waits for one.
    final loaded = state.value;
    if (loaded != null) _publish(change(loaded));

    // The account this write belongs to. Null before the first load has
    // settled, which is the early-tap case: such a write has no account
    // yet and adopts whichever one the load lands on, rather than
    // reading "not the same" and dropping itself.
    var owner = _storedFor;
    final queued = _writing;
    var failed = false;
    late final Future<void> mine;
    mine = Future<void>(() async {
      try {
        if (queued != null) {
          try {
            await queued;
          } on Object {
            // A failure ahead in the queue is that caller's to report; this
            // one still starts from whatever the server ended up holding.
          }
        }
        // Applied again, to the document this write's turn actually
        // starts from: the optimistic copy above was for whoever
        // rebuilt in the meantime, and a queued write's base is what
        // the one ahead of it stored.
        final current = state.value ?? await future;
        owner ??= _storedFor;
        // A queued write can wait out a sign-out: without this fence it
        // resumes against the next account's document, applies a change
        // nobody there made, and PUTs it into their prefs.
        if (_storedFor != owner) return;
        final next = change(current);
        // Published only while this is still the newest write. One
        // queued behind it has already published something later, and
        // republishing this one would rewind every list recomputed from
        // the document - three taps in a run would each be undone and
        // redone, and a fourth landing in that window would compute
        // from the rewound list, which is the lost write this whole
        // path exists to close.
        _publishIfNewest(mine, next);
        try {
          final stored = await ref.read(repositoryProvider).putPrefs(next);
          _confirmed = stored;
          if (_storedFor != owner) return;
          _publishIfNewest(mine, stored);
        } on Object {
          // The write did not land, so the document must stop claiming
          // it did - both the copy held for readers and the state every
          // list is recomputed from.
          failed = true;
          final confirmed = _confirmed;
          if (_storedFor == owner && confirmed != null) {
            _publishIfNewest(mine, confirmed);
          }
          rethrow;
        }
      } finally {
        if (identical(_writing, mine)) {
          _writing = null;
          // A failed write leaves this client unsure what the document
          // holds, and any invalidation that arrived while it ran was
          // answered from the held copy without a read. Ask once now
          // that nothing is in flight, so a change made elsewhere is
          // not lost with the failure.
          if (failed) {
            _stored = null;
            ref.invalidateSelf();
          }
        }
      }
    });
    _writing = mine;
    return mine;
  }

  /// [_publish], but only while [mine] is still the newest write. An
  /// older write's answer is not news: the newer one has already
  /// published something built on top of it.
  void _publishIfNewest(Future<void> mine, Prefs document) {
    if (!identical(_writing, mine)) {
      // Nothing at all, not even to the held copy: [build] answers from
      // that while a write is in flight, so recording an older document
      // there would rewind every reader through the rebuild instead of
      // through the state. What the write behind this one builds on is
      // `state.value`, and what a refusal reverts to is `_confirmed`;
      // neither needs this one.
      return;
    }
    _publish(document);
  }

  /// Makes [document] what this client knows, for readers and for the
  /// next write alike.
  void _publish(Prefs document) {
    _stored = document;
    _writes++;
    state = AsyncData(document);
  }

  /// Stores the shared-stats opt-out.
  ///
  /// The endpoint replaces the whole document, so every update here
  /// starts from the loaded value: building one from an empty default
  /// while the initial fetch is still in flight would wipe the stored
  /// timezone and locale. An early tap waits for the load instead.
  ///
  /// There is deliberately no writer for `theme`. It is a per-device
  /// setting now (`ThemeSetting`), and the wire field is deprecated -
  /// still read once, on a device that has none of its own, so a choice
  /// made before the move is not silently reset.
  Future<void> setSharedStatsOptOut(bool optOut) =>
      _write((current) => current.copyWith(sharedStatsOptOut: optOut));

  /// Stores the IANA timezone the calendar stats bucket in. Errors
  /// propagate so the editor can show the server's validation message
  /// (the server is the authority on what names exist).
  Future<void> setTimezone(String timezone) =>
      _write((current) => current.copyWith(timezone: timezone));

  /// Stores the BCP 47 tag the interface draws in. Same replace
  /// semantics as [setSharedStatsOptOut].
  Future<void> setLocale(String tag) =>
      _write((current) => current.copyWith(locale: tag));

  /// Clears the stored locale so the interface follows the system again.
  Future<void> clearLocale() => _write((c) => _cleared(c, locale: true));

  /// Clears the stored timezone so stats fall back to the server
  /// default (UTC).
  Future<void> clearTimezone() => _write((c) => _cleared(c, timezone: true));

  /// [current] with the named fields dropped.
  ///
  /// PUT replaces the whole document and [Prefs.copyWith] treats null as
  /// "keep", so a field can only be cleared by rebuilding around it. One
  /// literal, not one per clearable field: a preference added to Prefs
  /// but forgotten here deletes itself the next time anyone clears
  /// anything.
  static Prefs _cleared(
    Prefs current, {
    bool locale = false,
    bool timezone = false,
  }) => Prefs(
    timezone: timezone ? null : current.timezone,
    locale: locale ? null : current.locale,
    theme: current.theme,
    sharedStatsOptOut: current.sharedStatsOptOut,
    radioFavorites: current.radioFavorites,
    pinned: current.pinned,
    crossfadeSeconds: current.crossfadeSeconds,
    replayGain: current.replayGain,
    radioScrobbleOptOut: current.radioScrobbleOptOut,
    identifyOptOut: current.identifyOptOut,
    browseShowUnknown: current.browseShowUnknown,
    browseSorts: current.browseSorts,
    autoplay: current.autoplay,
  );

  /// Stores the crossfade a server-rendered queue is joined with.
  ///
  /// Zero is off, and it has to survive: [Prefs.copyWith] keeps the
  /// current value for null and zero is a value, so turning a crossfade
  /// back off carries through where clearing it would not.
  Future<void> setCrossfadeSeconds(double seconds) =>
      _write((current) => current.copyWith(crossfadeSeconds: seconds));

  /// Stores whether a server-rendered queue is levelled.
  Future<void> setReplayGain(bool on) =>
      _write((current) => current.copyWith(replayGain: on));

  /// Stores whether radio stays off this account's scrobblers.
  Future<void> setRadioScrobbleOptOut(bool optOut) =>
      _write((current) => current.copyWith(radioScrobbleOptOut: optOut));

  /// Stores whether this account's submissions skip identification by
  /// default. The sheets seed their switch from it and send the answer
  /// explicitly, so a preference changed mid-upload never moves one.
  Future<void> setIdentifyOptOut(bool optOut) =>
      _write((current) => current.copyWith(identifyOptOut: optOut));

  /// Stores the pinned radio stations, in dial order.
  ///
  /// Same replace semantics as [setSharedStatsOptOut], and the same
  /// reason for starting
  /// from the loaded document: a pin made before the first fetch lands
  /// would otherwise write a document holding one list and no timezone.
  ///
  /// An empty list is a value, not a "keep": [Prefs.copyWith] treats only
  /// null that way, so unpinning the last station carries through. The
  /// server then drops the field, and nothing reads a default set of pins
  /// out of an absent list.
  Future<void> setRadioFavorites(List<String> pids) =>
      _write((current) => current.copyWith(radioFavorites: pids));

  /// Stores what is pinned to home, in shelf order. Same replace
  /// semantics and the same empty-list-is-a-value rule as
  /// [setRadioFavorites].
  Future<void> setPinned(List<String> pids) =>
      _write((current) => current.copyWith(pinned: pids));

  /// Stores whether a browse index draws the bucket for the items a
  /// dimension is absent from.
  Future<void> setBrowseShowUnknown(bool show) =>
      _write((current) => current.copyWith(browseShowUnknown: show));

  /// Merged rather than replaced: a build that draws five dimensions
  /// must not drop a sixth one's stored order on the way past.
  Future<void> setBrowseSort(String dimension, FacetSort sort) => _write(
    (current) => current.copyWith(
      browseSorts: <String, String>{
        ...?current.browseSorts,
        dimension: sort.wireName,
      },
    ),
  );

  /// Stores whether playback may start with no gesture behind it.
  Future<void> setAutoplay(bool allowed) =>
      _write((current) => current.copyWith(autoplay: allowed));
}

final prefsControllerProvider = AsyncNotifierProvider<PrefsController, Prefs>(
  PrefsController.new,
);

/// The UI locale override from the synced preference; null follows the
/// system. Signed out, prefs are the empty document, so the system
/// decides - same rule as the theme.
final localeOverrideProvider = Provider<Locale?>((ref) {
  final tag = ref.watch(prefsControllerProvider).value?.locale;
  if (tag == null || tag.isEmpty) return null;
  // A tag this build cannot draw answers null, which is the system too:
  // pinning one would resolve it alone, ignore the device's own
  // languages, and land on English while the picker said the system was
  // deciding. See [supportedLocaleFor].
  return supportedLocaleFor(tag);
});

/// Material theme mode derived from this device's preference. The unset
/// state follows the platform: someone who never chose a theme has told
/// the OS what they like, not this app, and dark-on-a-light-desktop was
/// read as a bug. A stored choice is untouched.
///
/// Per device rather than per account since [ThemeSetting]: a theme
/// describes the screen being looked at, so a `light` chosen on the web
/// no longer follows the phone. The account's field is still on the wire
/// and deprecated, read exactly once by that setting's adoption.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(themeSettingProvider)) {
    ThemePref.system => ThemeMode.system,
    ThemePref.light => ThemeMode.light,
    ThemePref.dark || ThemePref.oled => ThemeMode.dark,
  };
});

/// What the design system needs to build the app's themes.
///
/// OLED is a parameter of the dark build rather than a third theme, so a
/// visitor who asked for true black gets it wherever the platform (or
/// [themeModeProvider]) resolves to dark. Every field here is per-device
/// now, the theme included: each describes the screen in front of the
/// listener rather than the account behind it.
class WaxThemeSpec {
  const WaxThemeSpec({
    required this.mode,
    required this.oled,
    required this.density,
    required this.artworkGlow,
    required this.captions,
  });

  final ThemeMode mode;
  final bool oled;
  final WaxDensity density;

  /// Whether the built theme carries the artwork glow. Per device like
  /// [density], and part of the spec rather than applied further down
  /// because it is a token the theme is built from.
  final bool artworkGlow;

  /// When cards draw their captions. Already resolved against what this
  /// device can hover, so the theme takes it as given.
  final WaxCaptionMode captions;

  WaxThemeVariant get dark =>
      oled ? WaxThemeVariant.oled : WaxThemeVariant.dark;

  // Every field, or the theme is rebuilt from a spec that compares equal
  // to the old one and the change never reaches the screen.
  @override
  bool operator ==(Object other) =>
      other is WaxThemeSpec &&
      other.mode == mode &&
      other.oled == oled &&
      other.density == density &&
      other.artworkGlow == artworkGlow &&
      other.captions == captions;

  @override
  int get hashCode => Object.hash(mode, oled, density, artworkGlow, captions);
}

final waxThemeSpecProvider = Provider<WaxThemeSpec>((ref) {
  return WaxThemeSpec(
    mode: ref.watch(themeModeProvider),
    oled: ref.watch(themeSettingProvider) == ThemePref.oled,
    density: ref.watch(densityProvider),
    artworkGlow: ref.watch(artworkGlowProvider),
    captions: ref.watch(cardCaptionsEffectiveProvider),
  );
});
