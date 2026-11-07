import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/connect/remote_session.dart';
import 'package:waxdeck/src/desktop/desktop_ports.dart';
import 'package:waxdeck/src/desktop/desktop_ports_io.dart'
    show PluginWindowTitle;
import 'package:waxdeck/src/desktop/tray_binder.dart' show trayPortProvider;
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/now_playing_slot.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/window_title_binder.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'debug_prints.dart';
import 'fakes.dart';
import 'player_host.dart';

const _a = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKA';
const _b = 'tr-01JZX5N8QW3F4V9T2B7KDTRACKB';

const _entry = QueueEntry(queueId: 'q0', pid: _a);

final _station = RadioStation(
  pid: 'rs-1',
  name: 'Prancing Pony FM',
  streamUrl: 'https://pony.example/stream',
  createdAt: DateTime.utc(2026, 7, 25),
);

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

final _copy = l10nFor(const [Locale('en')]);

/// The title for [slot] in English.
String? _titled(NowPlayingSlot slot) => windowTitleOf(slot: slot, copy: _copy);

NowPlayingSlot _item({
  ItemSummary? item,
  bool resolved = true,
  Object? error,
  bool loading = false,
}) => ItemSlot(
  NowPlaying(
    entry: _entry,
    item: resolved ? item ?? testItem(_a) : null,
    error: error,
    loading: loading,
  ),
);

/// What the window was told, in order.
class _Titles implements WindowTitlePort {
  final List<String> shown = <String>[];

  @override
  void show(String title) => shown.add(title);

  String get last => shown.last;
}

/// A slot a test sets by hand, standing in for the derived one.
class _HeldSlot extends Notifier<NowPlayingSlot> {
  @override
  NowPlayingSlot build() => const EmptySlot();

  set slot(NowPlayingSlot value) => state = value;
}

final _held = NotifierProvider<_HeldSlot, NowPlayingSlot>(_HeldSlot.new);

({ProviderContainer container, _Titles titles}) _bound() {
  final titles = _Titles();
  final container = appContainer(
    extra: [
      windowTitlePortProvider.overrideWithValue(titles),
      nowPlayingSlotProvider.overrideWith((ref) => ref.watch(_held)),
    ],
  );
  container.listen(windowTitleBinderProvider, (_, _) {});
  return (container: container, titles: titles);
}

({ProviderContainer container, _Titles titles}) _live() {
  final titles = _Titles();
  final repo = FakeRepository(items: [testItem(_a), testItem(_b)]);
  final container = appContainer(
    repo: repo,
    engine: FakeEngine(mediaDuration: const Duration(minutes: 3)),
    extra: [windowTitlePortProvider.overrideWithValue(titles)],
  );
  container.listen(windowTitleBinderProvider, (_, _) {});
  return (container: container, titles: titles);
}

void main() {
  group('the title for each slot', () {
    test('an item is its title and artist', () {
      expect(_titled(_item()), 'Prancing Pony Blues · The Bree Trio');
    });

    test('an item with no artist is its title alone', () {
      expect(
        _titled(_item(item: testItem(_a, artist: null))),
        'Prancing Pony Blues',
      );
      expect(
        _titled(_item(item: testItem(_a, artist: ''))),
        'Prancing Pony Blues',
      );
    });

    test('an item whose start failed is still named', () {
      expect(
        _titled(_item(error: Exception('would not open'))),
        'Prancing Pony Blues · The Bree Trio',
      );
    });

    test('an item still resolving has no title of its own', () {
      expect(_titled(_item(resolved: false, loading: true)), isNull);
    });

    test('a station is its name and the song it announces', () {
      expect(
        _titled(
          StationSlot(
            RadioPlayback(station: _station, nowPlaying: 'Bag End Blues'),
          ),
        ),
        'Prancing Pony FM · Bag End Blues',
      );
    });

    test('a station announcing nothing is its name alone', () {
      expect(
        _titled(StationSlot(RadioPlayback(station: _station))),
        'Prancing Pony FM',
      );
      expect(
        _titled(StationSlot(RadioPlayback(station: _station, nowPlaying: ''))),
        'Prancing Pony FM',
      );
    });

    test('a parked entry, a remote session, an offer and nothing are the '
        'default', () {
      expect(_titled(const ParkedSlot(ParkedEntry(entry: _entry))), isNull);
      expect(
        _titled(
          RemoteSlot(
            RemoteSession(
              session: PlaybackSessionInfo(
                id: 'ps-kitchen',
                endpointId: 'pe-kitchen',
                endpointName: 'Kitchen speaker',
                mine: true,
                authority: 'remote',
                playing: true,
                index: 0,
                positionMs: 0,
                positionAt: DateTime.utc(2026, 7, 25),
                rate: 1,
                queueVersion: 1,
                entries: const [],
              ),
              entries: const [],
            ),
          ),
        ),
        isNull,
      );
      expect(
        _titled(
          OfferSlot(
            RestorableQueue(
              queue: QueueState.empty.copyWith(
                entries: const [_entry],
                sourceOrder: const ['q0'],
              ),
              savedAt: DateTime.utc(2026, 7, 25),
            ),
          ),
        ),
        isNull,
      );
      expect(_titled(const EmptySlot()), isNull);
    });
  });

  group('the binder', () {
    test('says WaxDeck from the start, then follows the slot', () {
      final h = _bound();
      expect(h.titles.shown, ['WaxDeck']);

      h.container.read(_held.notifier).slot = _item();
      h.container.read(nowPlayingSlotProvider);
      expect(h.titles.last, 'Prancing Pony Blues · The Bree Trio');

      h.container.read(_held.notifier).slot = const EmptySlot();
      h.container.read(nowPlayingSlotProvider);
      expect(h.titles.last, 'WaxDeck');
    });

    test(
      'holds the title across a resolve instead of flashing the default',
      () {
        final h = _bound();
        h.container.read(_held.notifier).slot = _item();
        h.container.read(nowPlayingSlotProvider);
        final before = h.titles.shown.length;

        h.container.read(_held.notifier).slot = _item(
          resolved: false,
          loading: true,
        );
        h.container.read(nowPlayingSlotProvider);
        expect(h.titles.shown, hasLength(before));

        h.container.read(_held.notifier).slot = _item(
          item: testItem(_b, title: 'Bag End Blues', artist: 'Gaffer Gamgee'),
        );
        h.container.read(nowPlayingSlotProvider);
        expect(h.titles.last, 'Bag End Blues · Gaffer Gamgee');
      },
    );

    test('a start that failed before its item resolved reads the default', () {
      final h = _bound();
      h.container.read(_held.notifier).slot = _item();
      h.container.read(nowPlayingSlotProvider);
      expect(h.titles.last, isNot('WaxDeck'));

      h.container.read(_held.notifier).slot = _item(
        resolved: false,
        error: Exception('would not open'),
      );
      h.container.read(nowPlayingSlotProvider);
      expect(h.titles.last, 'WaxDeck');
    });

    test('goes back to the default when the slot is not the item playing', () {
      final h = _bound();
      h.container.read(_held.notifier).slot = _item();
      h.container.read(nowPlayingSlotProvider);

      h.container.read(_held.notifier).slot = const ParkedSlot(
        ParkedEntry(entry: _entry),
      );
      h.container.read(nowPlayingSlotProvider);
      expect(h.titles.last, 'WaxDeck');
    });

    test('says WaxDeck when it goes out of scope', () {
      final h = _bound();
      h.container.read(_held.notifier).slot = _item();
      h.container.read(nowPlayingSlotProvider);
      expect(h.titles.last, isNot('WaxDeck'));

      h.container.dispose();
      expect(h.titles.last, 'WaxDeck');
    });

    test('names a track, keeps it through a pause, then a station, then '
        'the default', () async {
      final h = _live();
      expect(h.titles.last, 'WaxDeck');

      h.container.read(nowPlayingProvider.notifier).play([
        testItem(_a),
        testItem(_b),
      ], source: _album);
      await pumpEventQueue();
      expect(h.titles.last, 'Prancing Pony Blues · The Bree Trio');

      final shown = h.titles.shown.length;
      h.container.read(nowPlayingProvider.notifier).togglePlayback();
      await pumpEventQueue();
      expect(h.titles.last, 'Prancing Pony Blues · The Bree Trio');
      expect(h.titles.shown, hasLength(shown));

      final radio = h.container.read(radioPlaybackProvider.notifier);
      await radio.play(_station);
      await pumpEventQueue();
      expect(h.titles.last, 'Prancing Pony FM');

      await radio.stop();
      await pumpEventQueue();
      expect(h.titles.last, 'WaxDeck');
    });

    test('goes back to the default when the queue is cleared', () async {
      final h = _live();
      h.container.read(nowPlayingProvider.notifier).play([
        testItem(_a),
      ], source: _album);
      await pumpEventQueue();
      expect(h.titles.last, isNot('WaxDeck'));

      h.container.read(queueControllerProvider.notifier).clear();
      await pumpEventQueue();
      expect(h.titles.last, 'WaxDeck');
    });
  });

  group('the desktop title bar', () {
    testWidgets('asks the window for a title once however often it is told', (
      tester,
    ) async {
      final asked = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'setTitle') {
            asked.add((call.arguments as Map)['title'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
      final port = PluginWindowTitle();

      port.show('WaxDeck');
      port.show('WaxDeck');
      port.show('Prancing Pony FM');
      port.show('Prancing Pony FM');
      port.show('WaxDeck');
      await tester.pump();

      expect(asked, ['WaxDeck', 'Prancing Pony FM', 'WaxDeck']);
    });

    testWidgets('a write the window refused is made again on the next ask', (
      tester,
    ) async {
      final asked = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method != 'setTitle') return null;
          asked.add((call.arguments as Map)['title'] as String);
          if (asked.length == 1) {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
      final port = PluginWindowTitle();

      final printed = await captureDebugPrints(() async {
        port.show('Prancing Pony FM');
        await tester.pump();
        port.show('Prancing Pony FM');
        await tester.pump();
        port.show('Prancing Pony FM');
        await tester.pump();
      });

      expect(asked, ['Prancing Pony FM', 'Prancing Pony FM']);
      expect(printed, hasLength(1), reason: 'the refusal is said once');
    });
  });

  group('the app', () {
    testWidgets('never writes its own title over the item playing', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            calls.add((call.arguments as Map)['label'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final titles = _Titles();
      final container = playbackContainer(
        repo: FakeRepository(
          sessionState: const SessionState(
            authenticated: true,
            user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
          ),
          items: [testItem(_a)],
        ),
        engine: FakeEngine(),
        extra: [
          windowTitlePortProvider.overrideWithValue(titles),
          desktopProvider.overrideWithValue(true),
          trayPortProvider.overrideWithValue(const NoTray()),
        ],
      );
      await pumpWholeApp(tester, container: container);

      final harness = PlayerHarness(container)..play([testItem(_a)]);
      await tester.pumpAndSettle();
      expect(titles.last, 'Prancing Pony Blues · The Bree Trio');

      // The theme and the language are what rebuild the app. Flutter's own
      // title fires on boot and again only when its title or color moves,
      // so a color derived from the theme is a title write waiting for
      // the day a theme changes it.
      expect(calls, ['WaxDeck'], reason: 'the probe saw the boot write');
      final fired = calls.length;
      container.read(themeSettingProvider.notifier).set(ThemePref.light);
      container.read(densityProvider.notifier).set(WaxDensity.compact);
      await tester.pumpAndSettle();
      container.read(themeSettingProvider.notifier).set(ThemePref.oled);
      tester.platformDispatcher.localesTestValue = const [Locale('es')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpAndSettle();

      expect(calls, hasLength(fired));
      expect(titles.last, 'Prancing Pony Blues · The Bree Trio');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).color,
        WaxColors.light.accent,
        reason: 'pinned, not taken from whichever theme is built',
      );

      await harness.endPlayback(tester);
      expect(titles.last, 'WaxDeck');
      // The app's own queue-save debounce, which the test outlives.
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
