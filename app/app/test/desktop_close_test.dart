import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/desktop/desktop_ports.dart';
import 'package:waxdeck/src/desktop/mini_window.dart';
import 'package:waxdeck/src/desktop/tray_binder.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// A window layer that records what it was asked for and hands back the
/// close handler, so a test can close the window without one.
///
/// [quit] records and nothing more, which is the port's own division:
/// the real one routes a quit into the platform's close, and what that
/// close runs is [onClose] - so a test that wants the finalize calls
/// [onClose] and a test that wants the route asserts the quit.
class _FakeWindow implements MiniWindowPort {
  final List<String> calls = <String>[];
  Future<void> Function()? onClose;

  @override
  Future<MiniWindowCapabilities> probe() async => MiniWindowCapabilities.none;

  @override
  Future<void> enter(MiniWindowCapabilities capabilities) async {}

  @override
  Future<void> leave() async {}

  @override
  Future<void> show() async {}

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> quit() async => calls.add('quit');

  @override
  Future<void> bindClose(Future<void> Function() handler) async {
    calls.add('bindClose');
    onClose = handler;
  }

  @override
  Future<void> unbindClose() async {
    calls.add('unbindClose');
    onClose = null;
  }
}

/// A queue store that records the writes, so the flush half of a
/// shutdown is a fact rather than an assumption. Without one the real
/// store is built, which asks for a platform binding no unit test has -
/// and the shutdown's own catch would swallow that.
class _RecordingQueueStore implements QueueStore {
  StoredQueue? saved;
  int saves = 0;

  @override
  Future<StoredQueue?> load() async => saved;

  @override
  Future<void> save(StoredQueue queue) async {
    saved = queue;
    saves++;
  }

  @override
  Future<void> clear() async => saved = null;
}

/// A tray that installs and remembers nothing, so the binder under test
/// is the close wiring rather than the icon.
class _FakeTray implements TrayPort {
  TrayActions? actions;

  @override
  Future<bool> install(TrayActions actions) async {
    this.actions = actions;
    return true;
  }

  @override
  Future<void> update(TrayFace face) async {}

  @override
  Future<void> remove() async {}
}

class _Harness {
  _Harness()
    : repo = FakeRepository(items: [testItem(_a)]),
      engine = FakeEngine(),
      window = _FakeWindow(),
      tray = _FakeTray(),
      store = _RecordingQueueStore() {
    container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
        miniWindowPortProvider.overrideWithValue(window),
        trayPortProvider.overrideWithValue(tray),
        queueStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakeRepository repo;
  final FakeEngine engine;
  final _FakeWindow window;
  final _FakeTray tray;
  final _RecordingQueueStore store;
  late final ProviderContainer container;

  /// Plays a track and mounts the binder the way the signed-in scope
  /// does. Listened to rather than read, because it is autoDispose and
  /// the app holds it for the session - a bare read would dispose it
  /// before the close it just bound.
  Future<void> start() async {
    container.read(nowPlayingProvider.notifier);
    container.read(queueControllerProvider.notifier).playNow([
      _a,
    ], source: _album);
    await pumpEventQueue();
    expect(container.read(nowPlayingProvider).session, isNotNull);

    final binder = container.listen(trayBinderProvider, (_, _) {});
    addTearDown(binder.close);
    await pumpEventQueue();
    expect(window.onClose, isNotNull, reason: 'the close was never bound');
  }
}

void main() {
  test(
    'closing the window finalizes and writes the queue before the app goes',
    () async {
      final h = _Harness();
      await h.start();
      // Written by the finalize rather than by the debounce that was
      // already going to write it.
      h.store.saves = 0;

      // Held open, because what this is about is the waiting. The
      // handler's own future is what the window layer holds its budget
      // against and destroys after, so a close that returns while the
      // checkpoint is still in flight kills the process with it - the
      // stale resume position the whole path exists to prevent.
      final checkpoint = Completer<void>();
      h.repo.putPlayStateGate = checkpoint;

      var closed = false;
      final closing = h.window.onClose!().then((_) => closed = true);
      await pumpEventQueue();

      expect(
        closed,
        isFalse,
        reason: 'the close returned before the checkpoint landed',
      );
      expect(h.repo.playPositions[_a], isNull);

      checkpoint.complete();
      await closing;

      // The session let go and its position written, rather than the
      // window vanishing while the tray kept the process and the music
      // alive behind it.
      expect(h.container.read(nowPlayingProvider).session, isNull);
      expect(h.repo.playPositions[_a], isNotNull);
      // And the queue on the disk, which is the half a server that had
      // stopped answering used to eat: the two run together, so an
      // unreachable server cannot spend the close's budget before the
      // local write gets its turn.
      expect(
        h.store.saves,
        greaterThan(0),
        reason: 'the queue the next launch offers was never written',
      );
    },
  );

  test(
    'the tray Quit closes the window rather than finalizing itself',
    () async {
      // One path out, so there is one budget and one destroy. Quitting
      // from the tray asks the window to close; the close is what runs
      // the finalize.
      final h = _Harness();
      await h.start();

      h.tray.actions!.onQuit();
      await pumpEventQueue();

      expect(h.window.calls, contains('quit'));
      // Not finalized behind the window's back: that is the close's job,
      // and the fake window is not a compositor.
      expect(h.container.read(nowPlayingProvider).session, isNotNull);
    },
  );

  test('signing out lets go of the close it bound', () async {
    // The binder is scoped to the signed-in session and the handler it
    // bound holds a ref into it. Left bound, a close after signing out
    // would finalize a session that no longer exists.
    final h = _Harness();
    await h.start();

    // What signing out does to an autoDispose provider nothing is
    // listening to any more.
    h.container.invalidate(trayBinderProvider);
    await pumpEventQueue();

    expect(h.window.calls, contains('unbindClose'));
  });
}
