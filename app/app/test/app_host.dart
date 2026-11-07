import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

/// A container with the ports the app reaches through a plugin or the
/// network faked, disposed when the test ends.
///
/// Pass a port to use that one in place of its fake, and [extra] for any
/// other override. [extra] must not name a provider this already
/// overrides - Riverpod refuses a second override of one - which is why
/// each port is a parameter. The downloads, settings, sync and mirror
/// providers keep their own test defaults unless given.
///
/// The credential store is in memory because the real one never answers
/// under test: the session would stay loading, where here it resolves to
/// whatever [repo] reports. The default repository is signed out, so a
/// test of the signed-in app passes `FakeRepository(sessionState: ...)`.
///
/// A provider's uncaught error, a listener's throw among them, goes to the
/// zone this was called in, as by default: it fails the test wherever it
/// is raised, the end-of-test disposal included, and
/// `tester.takeException()` does not see it. A test asserting one mounts a
/// `ProviderScope` of its own. [observers] and [retry] go to the container
/// as they are.
ProviderContainer appContainer({
  WaxDeckRepository? repo,
  AudioEnginePort? engine,
  CredentialStorePort? credentials,
  ArtworkStore? artwork,
  DownloadManagerPort? downloads,
  ClientSettingsStore? settings,
  SyncEngine? sync,
  MirrorDatabase? mirror,
  List<Override> extra = const <Override>[],
  List<ProviderObserver>? observers,
  Duration? Function(int retryCount, Object error)? retry,
}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo ?? FakeRepository()),
      audioEngineProvider.overrideWithValue(engine ?? FakeEngine()),
      credentialStoreProvider.overrideWithValue(
        credentials ?? InMemoryCredentialStore(),
      ),
      artworkStoreProvider.overrideWithValue(artwork ?? FakeArtworkStore()),
      if (downloads != null)
        downloadManagerProvider.overrideWithValue(downloads),
      if (settings != null)
        clientSettingsStoreProvider.overrideWithValue(settings),
      if (sync != null) syncEngineProvider.overrideWithValue(sync),
      if (mirror != null) mirrorDatabaseProvider.overrideWithValue(mirror),
      ...extra,
    ],
    observers: observers,
    retry: retry,
  );
  addTearDown(container.dispose);
  return container;
}

/// Mounts [screen] over [container] (a fresh [appContainer] if none is
/// given) and pumps one frame.
///
/// Routed by default, over the app's real route table; [pushed] and [at]
/// are `routedHost`'s. `routed: false` hosts it in `localizedHost`, for a
/// screen that never navigates, where they mean nothing; [theme] is
/// `localizedHost`'s, refused routed.
///
/// The container goes with its tree, as a `ProviderScope`'s does: unmounting
/// the tree, or mounting another container in its place (after a frame that
/// unmounts the first), disposes it, and its timers with it. Mounting the
/// same container again keeps it, and so does [leaveScreen].
Future<void> mountApp(
  WidgetTester tester,
  Widget screen, {
  ProviderContainer? container,
  bool routed = true,
  bool pushed = false,
  String? at,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  assert(
    routed || (!pushed && at == null),
    'pushed and at belong to the routed host',
  );
  assert(!routed || theme == null, 'a theme belongs to the unrouted host');
  await mountHost(
    tester,
    routed
        ? routedHost(screen, pushed: pushed, at: at, locale: locale)
        : localizedHost(screen, locale: locale, theme: theme),
    container: container ?? appContainer(),
  );
}

/// Mounts [host], an app the test builds around its screen, over
/// [container], which the tree then owns as [mountApp]'s does: for a host
/// [mountApp] does not build, such as a router of the test's own.
Future<void> mountHost(
  WidgetTester tester,
  Widget host, {
  required ProviderContainer container,
}) async {
  // One scope at a time: Riverpod's check on a provider moved in a build
  // belongs to the first scope to start, and goes when that one does. Only
  // the harness's own scope over this container carries on into the next
  // mount; a scope mounted by hand never disposes its container, so the
  // frame that unmounts it costs nothing.
  final mounted = _mountedContainer(tester);
  if (mounted != null && (mounted != container || !_owns(tester, container))) {
    await tester.pumpWidget(const SizedBox());
  }
  await tester.pumpWidget(_OwnedScope(container: container, child: host));
}

/// Takes the mounted screen away and keeps [container] in its scope, as
/// leaving a screen in the app does: nothing reads through the scope any
/// more, while what the container holds goes on, still the tree's to
/// dispose. [mountApp] over the same container brings a screen back.
///
/// [container] must be the mounted one; another would take its place.
Future<void> leaveScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  assert(
    _mountedContainer(tester) == container,
    'leaveScreen keeps the mounted container, and this is not it',
  );
  await mountHost(tester, const SizedBox.shrink(), container: container);
}

/// The container the outermost mounted scope holds, whether the harness or
/// the test mounted it, or null with none. A scope nested in it is the
/// screen's own.
ProviderContainer? _mountedContainer(WidgetTester tester) => tester
    .widgetList<UncontrolledProviderScope>(
      find.byType(UncontrolledProviderScope),
    )
    .firstOrNull
    ?.container;

/// Whether the harness's own scope, the first mounted, holds [container].
bool _owns(WidgetTester tester, ProviderContainer container) =>
    tester
        .widgetList<_OwnedScope>(find.byType(_OwnedScope))
        .firstOrNull
        ?.container ==
    container;

/// Hosts [container] and disposes it when this leaves the tree. Keyed by
/// the container, so another one gets a scope of its own: a scope
/// registers with the container it starts with and no other.
class _OwnedScope extends StatefulWidget {
  _OwnedScope({required this.container, required this.child})
    : super(key: ObjectKey(container));

  final ProviderContainer container;
  final Widget child;

  @override
  State<_OwnedScope> createState() => _OwnedScopeState();
}

class _OwnedScopeState extends State<_OwnedScope> {
  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.container,
    child: widget.child,
  );

  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }
}

/// [mountApp], then settled. Returns the container the screen runs over.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget screen, {
  ProviderContainer? container,
  bool routed = true,
  bool pushed = false,
  String? at,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  final over = container ?? appContainer();
  await mountApp(
    tester,
    screen,
    container: over,
    routed: routed,
    pushed: pushed,
    at: at,
    locale: locale,
    theme: theme,
  );
  await tester.pumpAndSettle();
  return over;
}

/// The whole app, [WaxDeckApp] with its own router and shell, mounted over
/// [container] (a fresh [appContainer] if none is given) as [mountApp]
/// mounts a screen, then settled. Returns the container.
///
/// [disableAnimations] sets the app in a copy of the view's own
/// `MediaQuery` with animations off, rebuilt as the view changes, so the
/// window's size class still holds: the deck bar's indicators run as long
/// as something plays, which no `pumpAndSettle` outlasts.
Future<ProviderContainer> pumpWholeApp(
  WidgetTester tester, {
  ProviderContainer? container,
  bool disableAnimations = false,
}) async {
  final over = container ?? appContainer();
  await mountHost(
    tester,
    disableAnimations
        ? Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const WaxDeckApp(),
            ),
          )
        : const WaxDeckApp(),
    container: over,
  );
  await tester.pumpAndSettle();
  return over;
}
