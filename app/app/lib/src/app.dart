import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/login_screen.dart';
import 'auth/setup_screen.dart';
import 'library/library_screen.dart';
import 'settings/prefs_controller.dart';

class WaxDeckApp extends ConsumerWidget {
  const WaxDeckApp({super.key});

  static ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFD9A648),
      brightness: brightness,
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dark-first per the UX blueprint; the synced theme preference can
    // lift it. Art-driven dynamic theming lands with the richer player UI.
    return MaterialApp(
      title: 'WaxDeck',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const RootGate(),
    );
  }
}

/// Routes between setup, login, and the library from the session probe: a
/// live session (the web cookie surviving a reload, a restored native
/// token) skips login entirely; anything else, including a failed probe,
/// lands on the sign-in flow.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return switch (auth) {
      AsyncData(:final value) when value.authenticated => const LibraryScreen(),
      AsyncLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _ => const _SignedOutGate(),
    };
  }
}

/// Unauthenticated branch: probe whether first-run setup is needed and
/// show the setup screen while it is; otherwise, or when the probe itself
/// fails, the login form.
class _SignedOutGate extends ConsumerWidget {
  const _SignedOutGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapRequiredProvider);
    return switch (bootstrap) {
      AsyncData(:final value) when value => const SetupScreen(),
      AsyncLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _ => const LoginScreen(),
    };
  }
}
