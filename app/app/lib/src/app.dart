import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/login_screen.dart';
import 'library/library_screen.dart';

class WaxDeckApp extends StatelessWidget {
  const WaxDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Dark-first per the UX blueprint; art-driven dynamic theming lands with
    // the richer player UI.
    return MaterialApp(
      title: 'WaxDeck',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD9A648),
          brightness: Brightness.dark,
        ),
      ),
      home: const RootGate(),
    );
  }
}

/// Routes between login and the library from the session probe: a live
/// session (the web cookie surviving a reload, for example) skips login
/// entirely; anything else, including a failed probe, lands on the form.
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
      _ => const LoginScreen(),
    };
  }
}
