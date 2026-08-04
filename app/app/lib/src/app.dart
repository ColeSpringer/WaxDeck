import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'auth/auth_controller.dart';
import 'desktop/mini_window.dart';
import 'settings/client_prefs.dart';
import 'settings/prefs_controller.dart';
import 'shell/router.dart';

class WaxDeckApp extends ConsumerWidget {
  const WaxDeckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The system decides until the synced theme preference says
    // otherwise; OLED is the dark build in true black rather than a
    // third theme. Art-driven accent stays scoped to player subtrees.
    final spec = ref.watch(waxThemeSpecProvider);
    return MaterialApp.router(
      title: 'WaxDeck',
      theme: buildWaxTheme(
        variant: WaxThemeVariant.light,
        density: spec.density,
      ),
      darkTheme: buildWaxTheme(variant: spec.dark, density: spec.density),
      themeMode: spec.mode,
      routerConfig: ref.watch(routerProvider),
      // The session probes decide which locations exist at all, so the
      // router does not get to run until they answer. Withholding the
      // child leaves the Router unmounted rather than routing on a
      // guess and correcting a frame later.
      //
      // The mini window wraps all of it, above the router: what it hides
      // is the whole app, and it keeps that app mounted while it does.
      builder: (context, child) => MiniWindowGate(
        child: _ReducedMotion(child: _BootGate(child: child!)),
      ),
    );
  }
}

/// Applies the in-app reduce-motion override.
///
/// Everything that animates reads `MediaQuery.disableAnimationsOf`
/// through `WaxMotion`, so the override belongs on the query rather than
/// on a second flag every animating widget would have to be taught. Set
/// above the router, which is where the query every screen inherits is
/// established.
///
/// One-way: it can turn animation off and never on. The platform's flag
/// is an accessibility need, and a preference that could clear it would
/// let a shared device's setting overrule the person who set it.
class _ReducedMotion extends ConsumerWidget {
  const _ReducedMotion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(reduceMotionProvider)) return child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child,
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
