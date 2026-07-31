import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
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
  Future<void>? _writing;

  @override
  Future<Prefs> build() async {
    final session = await ref.watch(authControllerProvider.future);
    if (!session.authenticated) return const Prefs();
    return ref.watch(repositoryProvider).getPrefs();
  }

  /// Replaces the document, one write at a time. [change] runs against the
  /// loaded value after any queued write has landed.
  Future<void> _write(Prefs Function(Prefs current) change) {
    final queued = _writing;
    final mine = Future<void>(() async {
      if (queued != null) {
        try {
          await queued;
        } on Object {
          // A failure ahead in the queue is that caller's to report; this
          // one still starts from whatever the server ended up holding.
        }
      }
      final current = state.value ?? await future;
      final stored = await ref
          .read(repositoryProvider)
          .putPrefs(change(current));
      state = AsyncData(stored);
    });
    _writing = mine;
    return mine;
  }

  /// Stores a new theme preference. The endpoint replaces the whole
  /// document, so the update must start from the loaded value: building
  /// it from an empty default while the initial fetch is still in
  /// flight would wipe the stored timezone and locale. An early tap
  /// waits for the load instead.
  Future<void> setTheme(ThemePref theme) =>
      _write((current) => current.copyWith(theme: theme));

  /// Stores the shared-stats opt-out. Same replace semantics as
  /// [setTheme].
  Future<void> setSharedStatsOptOut(bool optOut) =>
      _write((current) => current.copyWith(sharedStatsOptOut: optOut));

  /// Stores the IANA timezone the calendar stats bucket in. Errors
  /// propagate so the editor can show the server's validation message
  /// (the server is the authority on what names exist).
  Future<void> setTimezone(String timezone) =>
      _write((current) => current.copyWith(timezone: timezone));

  /// Clears the stored timezone so stats fall back to the server
  /// default (UTC). PUT replaces the whole preference document and
  /// copyWith cannot null a field, so the document is rebuilt without
  /// it.
  Future<void> clearTimezone() => _write(
    (current) => Prefs(
      locale: current.locale,
      theme: current.theme,
      sharedStatsOptOut: current.sharedStatsOptOut,
      radioFavorites: current.radioFavorites,
      crossfadeSeconds: current.crossfadeSeconds,
      replayGain: current.replayGain,
      radioScrobbleOptOut: current.radioScrobbleOptOut,
    ),
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

  /// Stores the pinned radio stations, in dial order.
  ///
  /// Same replace semantics as [setTheme], and the same reason for starting
  /// from the loaded document: a pin made before the first fetch lands
  /// would otherwise write a document holding one list and no timezone.
  ///
  /// An empty list is a value, not a "keep": [Prefs.copyWith] treats only
  /// null that way, so unpinning the last station carries through. The
  /// server then drops the field, and nothing reads a default set of pins
  /// out of an absent list.
  Future<void> setRadioFavorites(List<String> pids) =>
      _write((current) => current.copyWith(radioFavorites: pids));
}

final prefsControllerProvider = AsyncNotifierProvider<PrefsController, Prefs>(
  PrefsController.new,
);

/// Material theme mode derived from the synced preference. Dark-first per
/// the UX blueprint while nothing is stored or loaded yet.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final prefs = ref.watch(prefsControllerProvider).value;
  return switch (prefs?.theme) {
    ThemePref.system => ThemeMode.system,
    ThemePref.light => ThemeMode.light,
    ThemePref.dark || ThemePref.oled => ThemeMode.dark,
    null => ThemeMode.dark,
  };
});

/// What the design system needs to build the app's themes.
///
/// OLED is a parameter of the dark build rather than a third theme, so a
/// visitor who asked for true black gets it wherever the platform (or
/// [themeModeProvider]) resolves to dark. Density comes from the other
/// side of the settings line: it describes the screen in front of the
/// listener, so it is per-device (ADR-0027) where the theme is the
/// account's.
class WaxThemeSpec {
  const WaxThemeSpec({
    required this.mode,
    required this.oled,
    required this.density,
  });

  final ThemeMode mode;
  final bool oled;
  final WaxDensity density;

  WaxThemeVariant get dark =>
      oled ? WaxThemeVariant.oled : WaxThemeVariant.dark;

  @override
  bool operator ==(Object other) =>
      other is WaxThemeSpec &&
      other.mode == mode &&
      other.oled == oled &&
      other.density == density;

  @override
  int get hashCode => Object.hash(mode, oled, density);
}

final waxThemeSpecProvider = Provider<WaxThemeSpec>((ref) {
  final prefs = ref.watch(prefsControllerProvider).value;
  return WaxThemeSpec(
    mode: ref.watch(themeModeProvider),
    oled: prefs?.theme == ThemePref.oled,
    density: ref.watch(densityProvider),
  );
});
