import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/page_exit/page_exit.dart';
import 'package:waxdeck/src/player/page_exit_binder.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// Stands in for the browser: keeps the two callbacks so a test can
/// close the document by calling them.
class _FakeExit implements PageExitPort {
  List<ExitRequest> Function()? onExit;
  List<ExitRequest> Function()? onHidden;
  var disposed = false;

  @override
  void bind({
    required List<ExitRequest> Function() onExit,
    required List<ExitRequest> Function() onHidden,
  }) {
    this.onExit = onExit;
    this.onHidden = onHidden;
  }

  @override
  void dispose() => disposed = true;
}

class _Harness {
  _Harness()
    : engine = FakeEngine(),
      exit = _FakeExit(),
      repo = FakeRepository(items: [testItem(_a)]) {
    container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
        pageExitPortProvider.overrideWithValue(exit),
      ],
    );
    // Registered at construction, not left to `end`: a container that
    // outlives its test keeps a checkpoint timer firing into the rest
    // of the suite, and `end` is the last statement of each of these -
    // so an expectation above it would be exactly the failure that
    // leaks one.
    addTearDown(container.dispose);
  }

  final FakeEngine engine;
  final _FakeExit exit;
  final FakeRepository repo;
  late final ProviderContainer container;

  /// Starts the queue and mounts the binder the way the signed-in scope
  /// does: listened to, so it lives as long as the session rather than
  /// as long as one read.
  Future<void> start() async {
    container.read(nowPlayingProvider.notifier);
    container.read(queueControllerProvider.notifier).playNow([
      _a,
    ], source: _album);
    await pumpEventQueue();
    bind();
  }

  void bind() {
    final keepAlive = container.listen(pageExitBinderProvider, (_, _) {});
    addTearDown(keepAlive.close);
  }

  /// Plays [ms] of media in steps small enough to count as listening,
  /// so the session has a listen worth reporting.
  Future<void> play(int ms) async {
    for (var played = 0; played < ms; played += 2000) {
      engine.advance(const Duration(milliseconds: 2000));
      await pumpEventQueue();
    }
  }

  /// Ends the session the way signing out would, so the assertions
  /// above are not the last thing holding it up. Disposal is the
  /// teardown's, registered at construction.
  Future<void> end() async {
    container.read(queueControllerProvider.notifier).clear();
    await pumpEventQueue();
  }
}

void main() {
  test(
    'a closing document sends the checkpoint and the listen report',
    () async {
      final h = _Harness();
      await h.start();
      // Something actually heard: a session that played nothing has no
      // listen to report, which is a different branch.
      await h.play(10000);
      expect(h.exit.onExit, isNotNull, reason: 'nothing bound to the document');

      final sent = h.exit.onExit!();

      // Both: where the listener stood, and that the session ended.
      // Without the second the server keeps believing the session is
      // live, which is what the resume dock is fed from - so coming back
      // offered the wrong thing at the wrong position.
      expect(sent, hasLength(2));
      expect(sent.first.method, 'PUT');
      expect(sent.first.path, contains('play-state'));
      expect(sent.last.method, 'POST');
      expect(sent.last.path, contains('listens'));
      // Credentialled, both of them. These go out through the browser
      // rather than through the client's own sender, so the header the
      // interceptor would have added has to be on them already - and
      // nothing waits for the answer, so one that went out
      // unauthenticated would be silently lost.
      for (final request in sent) {
        expect(request.headers, contains('X-CSRF-Token'));
      }

      await h.end();
    },
  );

  test('a tab going hidden reports a position and ends nothing', () async {
    // Backgrounding is not leaving. A tab switch that closed the
    // session would end a listen every time somebody checked their
    // mail, and the report was explicit that switching tabs keeps
    // playing.
    final h = _Harness();
    await h.start();
    await h.play(10000);

    final sent = h.exit.onHidden!();

    expect(sent, hasLength(1));
    expect(sent.single.path, contains('play-state'));
    expect(h.container.read(nowPlayingProvider).session, isNotNull);

    await h.end();
  });

  test('a document closing over nothing sends nothing', () async {
    final h = _Harness();
    h.container.read(nowPlayingProvider.notifier);
    h.bind();

    expect(h.exit.onExit!(), isEmpty);
    expect(h.exit.onHidden!(), isEmpty);
  });
}
