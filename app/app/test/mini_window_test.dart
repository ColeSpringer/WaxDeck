import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/desktop/desktop_ports.dart';
import 'package:waxdeck/src/desktop/mini_window.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/timeline_scope.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/shell/commands.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'player_host.dart';

/// A window layer that answers whatever a compositor was going to, and
/// records what it was asked for.
class _FakeWindow implements MiniWindowPort {
  _FakeWindow(this.capabilities);

  MiniWindowCapabilities capabilities;
  final List<String> calls = <String>[];
  MiniWindowCapabilities? entered;

  @override
  Future<MiniWindowCapabilities> probe() async {
    calls.add('probe');
    return capabilities;
  }

  @override
  Future<void> enter(MiniWindowCapabilities capabilities) async {
    calls.add('enter');
    entered = capabilities;
  }

  @override
  Future<void> leave() async => calls.add('leave');

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<void> quit() async => calls.add('quit');

  /// What the app asked to run when the window is closed, so a test can
  /// close the window by calling it.
  Future<void> Function()? onClose;

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

ProviderContainer _container(_FakeWindow window) =>
    appContainer(extra: [miniWindowPortProvider.overrideWithValue(window)]);

void main() {
  group('the mini window', () {
    testWidgets('names an entry still resolving as loading', (tester) async {
      final window = _FakeWindow(
        const MiniWindowCapabilities(
          available: true,
          frameless: true,
          alwaysOnTop: true,
        ),
      );
      final repo = FakeRepository(items: [testItem('tr-A')]);
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(),
        extra: [miniWindowPortProvider.overrideWithValue(window)],
      );
      container.read(miniWindowProvider);
      await tester.pump();
      await container.read(miniWindowProvider.notifier).enter();

      final gate = repo.getItemGate = Completer<void>();
      unawaited(
        container.read(nowPlayingProvider.notifier).playPids([
          'tr-A',
        ], source: QueueSource.none),
      );
      await mountApp(
        tester,
        const MiniWindowGate(child: SizedBox()),
        container: container,
        routed: false,
        theme: buildWaxTheme(),
      );
      await tester.pump();
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('Nothing is playing'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
    });

    testWidgets('offers no stepping and no play through a queue radio '
        'parked', (tester) async {
      final window = _FakeWindow(
        const MiniWindowCapabilities(
          available: true,
          frameless: true,
          alwaysOnTop: true,
        ),
      );
      final repo = FakeRepository(items: [testItem('tr-A'), testItem('tr-B')]);
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(),
        extra: [miniWindowPortProvider.overrideWithValue(window)],
      );
      container.read(miniWindowProvider);
      await tester.pump();
      await container.read(miniWindowProvider.notifier).enter();
      await container.read(nowPlayingProvider.notifier).playPids([
        'tr-A',
        'tr-B',
      ], source: QueueSource.none);
      await pumpApp(
        tester,
        const MiniWindowGate(child: SizedBox()),
        container: container,
        routed: false,
        theme: buildWaxTheme(),
      );
      DeckBarActions actions() =>
          tester.widget<MiniPlayer>(find.byType(MiniPlayer)).actions;
      expect(actions().onNext, isNotNull);
      expect(actions().onPrevious, isNotNull);
      expect(actions().onPlayPause, isNotNull);

      final radio = container.read(radioPlaybackProvider.notifier);
      await radio.play(
        RadioStation(
          pid: 'ra-1',
          name: 'Coastal FM',
          streamUrl: 'https://radio.example/stream',
          createdAt: DateTime.utc(2026, 7, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(actions().onPlayPause, isNotNull, reason: 'it stops the station');
      await radio.stop();
      await tester.pumpAndSettle();

      expect(find.text('Nothing is playing'), findsOneWidget);
      expect(actions().onNext, isNull);
      expect(actions().onPrevious, isNull);
      // As the keyboard has it: the way back is the deck's offer, and a
      // live Play here would answer a press with nothing.
      expect(actions().onPlayPause, isNull);
      container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
    });

    testWidgets('spans a book\'s chapter or the whole book, as the deck '
        'does', (tester) async {
      const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDMINI01';
      final window = _FakeWindow(
        const MiniWindowCapabilities(
          available: true,
          frameless: true,
          alwaysOnTop: true,
        ),
      );
      final repo = FakeRepository()
        ..books[bookPid] = testBook(
          bookPid,
          durationMs: 3600000,
          chapters: const [
            ChapterMark(index: 0, title: 'An Unexpected Party', startMs: 0),
            ChapterMark(index: 1, title: 'Roast Mutton', startMs: 1800000),
          ],
        );
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
        extra: [miniWindowPortProvider.overrideWithValue(window)],
      );
      container.read(miniWindowProvider);
      await tester.pump();
      await container.read(miniWindowProvider.notifier).enter();
      PlayerHarness(container).play([
        testItem(bookPid, mediaType: MediaType.audiobook),
      ], positionMs: 2700000);
      await pumpApp(
        tester,
        const MiniWindowGate(child: SizedBox()),
        container: container,
        routed: false,
        theme: buildWaxTheme(),
      );
      NowPlayingData drawn() =>
          tester.widget<MiniPlayer>(find.byType(MiniPlayer)).now;
      expect(drawn().duration, const Duration(minutes: 30));
      expect(drawn().position, const Duration(minutes: 15));

      container.read(bookTimelineScopeProvider.notifier).toggle();
      await tester.pumpAndSettle();
      expect(drawn().duration, const Duration(hours: 1));
      expect(drawn().position, const Duration(minutes: 45));
      container.read(queueControllerProvider.notifier).clear();
      await tester.pumpAndSettle();
    });

    test('is not offered where the platform has no window', () async {
      final window = _FakeWindow(MiniWindowCapabilities.none);
      final container = _container(window);
      container.read(miniWindowProvider);
      await container.pump();

      expect(container.read(miniWindowProvider).available, isFalse);
      await container.read(miniWindowProvider.notifier).enter();
      expect(container.read(miniWindowProvider).showing, isFalse);
      expect(window.calls, <String>['probe']);
    });

    test(
      'enters and leaves, and the app follows before the compositor does',
      () async {
        final window = _FakeWindow(
          const MiniWindowCapabilities(
            available: true,
            frameless: true,
            alwaysOnTop: true,
          ),
        );
        final container = _container(window);
        container.read(miniWindowProvider);
        await container.pump();

        await container.read(miniWindowProvider.notifier).enter();
        expect(container.read(miniWindowProvider).showing, isTrue);
        expect(window.entered!.frameless, isTrue);
        expect(window.entered!.alwaysOnTop, isTrue);

        await container.read(miniWindowProvider.notifier).leave();
        expect(container.read(miniWindowProvider).showing, isFalse);
        expect(window.calls, <String>['probe', 'enter', 'leave']);
      },
    );

    test('asks a Wayland session for only what it will give', () async {
      // The port is what reads the session type; what this pins is that
      // whatever it answers is what the app asks for, rather than the
      // app asking for everything and being refused mid-flight.
      final window = _FakeWindow(const MiniWindowCapabilities(available: true));
      final container = _container(window);
      container.read(miniWindowProvider);
      await container.pump();

      await container.read(miniWindowProvider.notifier).enter();
      expect(container.read(miniWindowProvider).showing, isTrue);
      expect(window.entered!.frameless, isFalse);
      expect(window.entered!.alwaysOnTop, isFalse);
    });

    test('a container torn down while small puts the window back', () async {
      final window = _FakeWindow(const MiniWindowCapabilities(available: true));
      final container = _container(window);
      container.read(miniWindowProvider);
      await container.pump();
      await container.read(miniWindowProvider.notifier).enter();

      container.dispose();
      expect(window.calls, contains('leave'));
    });
  });

  group('its command', () {
    test('is absent from the registry where there is no window', () async {
      final container = _container(_FakeWindow(MiniWindowCapabilities.none));
      container.read(commandRegistryProvider);
      await container.pump();

      // Absent rather than disabled: a chord that can never work here
      // must not be bound, offered in the palette, or taught by the
      // reference sheet.
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        isNot(contains('mini-window')),
      );
    });

    test('the probe resolving does not freeze the registry', () async {
      // Riverpod runs disposal callbacks before a recompute, on the same
      // notifier: a latched "closed" flag would make every scoped
      // command after launch a no-op.
      final container = _container(
        _FakeWindow(const MiniWindowCapabilities(available: true)),
      );
      // `CommandShortcuts` holds this for the session; without a
      // listener the registry is disposed between reads.
      container.listen(commandRegistryProvider, (_, _) {});
      final registry = container.read(commandRegistryProvider.notifier);
      await container.pump();
      // The probe has answered, so the registry has recomputed.
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        contains('mini-window'),
      );

      final token = Object();
      registry.register(token, <WaxCommand>[
        WaxCommand(
          id: 'scoped-thing',
          label: 'Scoped thing',
          section: WaxCommandSection.app,
          run: (_, _) {},
        ),
      ]);
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        contains('scoped-thing'),
      );

      registry.unregister(token);
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        isNot(contains('scoped-thing')),
      );
    });

    test('appears once the probe says there is one', () async {
      final container = _container(
        _FakeWindow(const MiniWindowCapabilities(available: true)),
      );
      container.read(commandRegistryProvider);
      await container.pump();

      final command = container
          .read(commandRegistryProvider)
          .firstWhere((c) => c.id == 'mini-window');
      expect(command.section, WaxCommandSection.view);
      // Both spellings of the chord, so a keyboard moved between
      // machines finds what it expects.
      expect(command.activators, hasLength(2));
    });
  });
}
