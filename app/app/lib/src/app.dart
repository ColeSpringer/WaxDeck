import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/login_screen.dart';
import 'auth/setup_screen.dart';
import 'library/library_screen.dart';
import 'metadata/metadata_screen.dart';
import 'prototype/editing_prototype_screen.dart';
import 'settings/prefs_controller.dart';
import 'sync/sync_providers.dart';

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
      // Deep-linkable prototypes and tools live behind explicit routes;
      // everything else stays on the home gate.
      onGenerateRoute: (settings) => switch (settings.name) {
        EditingPrototypeScreen.routeName => MaterialPageRoute(
          settings: settings,
          builder: (_) => const EditingPrototypeScreen(),
        ),
        final String name when name.startsWith(MetadataScreen.routePrefix) =>
          MaterialPageRoute(
            settings: settings,
            builder: (_) => MetadataScreen(
              pid: name.substring(MetadataScreen.routePrefix.length),
            ),
          ),
        _ => null,
      },
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
    final authenticated = switch (auth) {
      AsyncData(:final value) => value.authenticated,
      _ => false,
    };
    if (authenticated) {
      // Bind the sync machinery to the signed-in lifetime: the engine
      // (or the web invalidation listener) starts here and stops when
      // this subtree goes away on sign-out.
      ref.watch(syncBinderProvider);
      return const LibraryScreen();
    }
    return switch (auth) {
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
