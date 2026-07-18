import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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
    ThemePref.dark => ThemeMode.dark,
    // OLED maps to dark for now; a true-black theme variant comes later.
    ThemePref.oled => ThemeMode.dark,
    null => ThemeMode.dark,
  };
});
