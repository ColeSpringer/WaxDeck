import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/owed_revoke.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'app_host.dart';
import 'fakes.dart';

/// A build that finds another account's session where one shows hands it
/// to a session read. That read is the truth at the swap; when the server
/// does not answer it, the build's own answer, a moment older, is, unless
/// a revoke is owed.

const _anns = SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
    username: 'ann',
    roles: ['user'],
  ),
);
const _bens = SessionState(
  authenticated: true,
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDACCBEN',
    username: 'ben',
    roles: ['user'],
  ),
);

class _CountedArtwork extends FakeArtworkStore {
  var wipes = 0;

  @override
  Future<void> forgetEverything() {
    wipes++;
    return super.forgetEverything();
  }
}

const _down = WaxDeckApiException(code: 'transport', message: 'down');

/// A server that answers the next [answered] session reads and then is out
/// of reach, revokes included; [lastAnswered] runs as it gives the last.
class _Fading extends FakeRepository {
  _Fading() : super(sessionState: _anns);

  int? answered;
  void Function()? lastAnswered;

  @override
  Future<SessionState> getSession() async {
    final left = answered;
    if (left != null) {
      if (left == 0) throw _down;
      answered = left - 1;
      if (left == 1) lastAnswered?.call();
    }
    return super.getSession();
  }

  @override
  Future<void> logout() async {
    if (answered == 0) throw _down;
    await super.logout();
  }
}

/// The page's storage, which every tab of the browser shares.
class _Storage implements BrowserStorage {
  final values = <String, String>{};

  @override
  String? getItem(String key) => values[key];

  @override
  void setItem(String key, String value) => values[key] = value;

  @override
  void removeItem(String key) => values.remove(key);
}

void main() {
  test('a build that hands another account\'s session to a session read the '
      'server does not answer sees the account showing out all the same, on '
      'the build\'s own answer', () async {
    final server = _Fading();
    final artwork = _CountedArtwork();
    final container = appContainer(
      repo: server,
      artwork: artwork,
      settings: MemoryClientSettingsStore(),
      extra: [queueSaveDebounceProvider.overrideWithValue(Duration.zero)],
    );
    await container.read(authControllerProvider.future);
    final shown = <String>[];
    final watch = container.listen(
      authControllerProvider,
      (_, next) => shown.add(next.value?.user?.username ?? 'out'),
    );
    addTearDown(watch.close);

    // The build's own read answers Ben; the read it hands over to does not.
    server
      ..sessionState = _bens
      ..answered = 1;
    container.invalidate(authControllerProvider);
    final built = await container.read(authControllerProvider.future);
    expect(built.user?.username, 'ann');
    await pumpEventQueue();

    expect(artwork.wipes, 1);
    expect(shown, containsAllInOrder(['out', 'ben']));
    expect(shown.last, 'ben');
    expect(container.read(playbackHeldProvider), isFalse);
  });

  test('a build that hands another account\'s session to a session read the '
      'server does not answer, a revoke owed since, sees the account '
      'showing out and shows nobody', () async {
    final server = _Fading();
    final artwork = _CountedArtwork();
    final storage = _Storage();
    final container = appContainer(
      repo: server,
      artwork: artwork,
      settings: MemoryClientSettingsStore(),
      extra: [
        owedRevokeProvider.overrideWithValue(OwedRevoke(storage)),
        queueSaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    await container.read(authControllerProvider.future);
    final shown = <String>[];
    final watch = container.listen(
      authControllerProvider,
      (_, next) => shown.add(next.value?.user?.username ?? 'out'),
    );
    addTearDown(watch.close);

    // The build's own read answers Ben; Ben's own tab then signs out with
    // the server out of reach, before the read the build hands over to.
    server
      ..sessionState = _bens
      ..answered = 1
      ..lastAnswered = () => OwedRevoke(storage).owe();
    container.invalidate(authControllerProvider);
    final built = await container.read(authControllerProvider.future);
    expect(built.user?.username, 'ann');
    await pumpEventQueue();

    expect(artwork.wipes, 1);
    expect(shown, isNot(contains('ben')));
    expect(shown.last, 'out');
    expect(OwedRevoke(storage).owed, isTrue);
  });
}
