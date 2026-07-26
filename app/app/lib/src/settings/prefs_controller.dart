import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';

/// The caller's synced preferences. Empty while signed out; refetched when
/// the session changes.
class PrefsController extends AsyncNotifier<Prefs> {
  @override
  Future<Prefs> build() async {
    final session = await ref.watch(authControllerProvider.future);
    if (!session.authenticated) return const Prefs();
    return ref.watch(repositoryProvider).getPrefs();
  }

  /// Stores a new theme preference. The endpoint replaces the whole
  /// document, so the update must start from the loaded value: building
  /// it from an empty default while the initial fetch is still in
  /// flight would wipe the stored timezone and locale. An early tap
  /// waits for the load instead.
  Future<void> setTheme(ThemePref theme) async {
    final current = state.value ?? await future;
    final stored = await ref
        .read(repositoryProvider)
        .putPrefs(current.copyWith(theme: theme));
    state = AsyncData(stored);
  }

  /// Stores the shared-stats opt-out. Same replace semantics as
  /// [setTheme].
  Future<void> setSharedStatsOptOut(bool optOut) async {
    final current = state.value ?? await future;
    final stored = await ref
        .read(repositoryProvider)
        .putPrefs(current.copyWith(sharedStatsOptOut: optOut));
    state = AsyncData(stored);
  }

  /// Stores the IANA timezone the calendar stats bucket in. Errors
  /// propagate so the editor can show the server's validation message
  /// (the server is the authority on what names exist).
  Future<void> setTimezone(String timezone) async {
    final current = state.value ?? await future;
    final stored = await ref
        .read(repositoryProvider)
        .putPrefs(current.copyWith(timezone: timezone));
    state = AsyncData(stored);
  }

  /// Clears the stored timezone so stats fall back to the server
  /// default (UTC). PUT replaces the whole preference document and
  /// copyWith cannot null a field, so the document is rebuilt without
  /// it.
  Future<void> clearTimezone() async {
    final current = state.value ?? await future;
    final stored = await ref
        .read(repositoryProvider)
        .putPrefs(
          Prefs(
            locale: current.locale,
            theme: current.theme,
            sharedStatsOptOut: current.sharedStatsOptOut,
          ),
        );
    state = AsyncData(stored);
  }
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
/// [themeModeProvider]) resolves to dark. Density is a per-device client
/// setting and rides the store that lands with the settings phase.
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
    density: WaxDensity.comfortable,
  );
});
