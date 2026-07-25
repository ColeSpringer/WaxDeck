import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'auth/auth_controller.dart';
import 'settings/prefs_controller.dart';
import 'shell/router.dart';

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
    return MaterialApp.router(
      title: 'WaxDeck',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      // The session probes decide which locations exist at all, so the
      // router does not get to run until they answer. Withholding the
      // child leaves the Router unmounted rather than routing on a
      // guess and correcting a frame later.
      builder: (context, child) => _BootGate(child: child!),
    );
  }
}

/// Holds the first frame while the session probes are outstanding.
///
/// A live session (the web cookie surviving a reload, a restored native
/// token) skips the login screen entirely; a server with no accounts
/// goes to setup. Both answers arrive asynchronously, and neither the
/// library nor the login form is the right thing to show meanwhile.
///
/// It gates the first frame only. Once the router is up it stays up:
/// signing out resolves the first-run probe again, and swapping the
/// router back out for a spinner would tear down the navigator in the
/// middle of the transition. From then on the redirect owns where a
/// visitor lands, and it is re-run when that probe answers.
class _BootGate extends ConsumerStatefulWidget {
  const _BootGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<_BootGate> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    if (_started) return widget.child;

    final auth = ref.watch(authControllerProvider);
    // A failed probe counts as answered: it means signed out.
    var probing = auth.isLoading && !auth.hasValue;
    final signedIn = auth.value?.authenticated ?? false;
    if (!probing && !signedIn) {
      final bootstrap = ref.watch(bootstrapRequiredProvider);
      probing = bootstrap.isLoading && !bootstrap.hasValue;
    }
    if (probing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_started) setState(() => _started = true);
    });
    return widget.child;
  }
}
