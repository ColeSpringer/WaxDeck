import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_store.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/books/book_screen.dart';
import 'package:waxdeck/src/connect/connect_bus.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/music/index_screen.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/player/entity_play_state_controller.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/player/play_state_controller.dart';
import 'package:waxdeck/src/playlists/playlists_controller.dart';
import 'package:waxdeck/src/podcasts/podcast_shelves.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/shell/lifecycle_banners.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/sync/catalog_cursor.dart';
import 'package:waxdeck/src/sync/live_invalidations.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/uploads/share_intake.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

/// The art endpoint as `NetworkImage` reaches it: a picture for each
/// path in [covers], 404 for any other. Records what was asked.
class _ArtServer implements HttpClient {
  final covers = <String, Uint8List>{};

  /// Each request's path and query, in order.
  final asked = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl) {
      final uri = invocation.positionalArguments.first as Uri;
      asked.add('${uri.path}?${uri.query}');
      return Future<HttpClientRequest>.value(_ArtRequest(covers[uri.path]));
    }
    return super.noSuchMethod(invocation);
  }
}

class _ArtRequest implements HttpClientRequest {
  _ArtRequest(this.cover);

  final Uint8List? cover;

  @override
  HttpHeaders get headers => _NoHeaders();

  @override
  Future<HttpClientResponse> close() async => _ArtResponse(cover);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ArtResponse extends Stream<List<int>> implements HttpClientResponse {
  _ArtResponse(this.cover);

  final Uint8List? cover;

  @override
  int get statusCode => cover == null ? HttpStatus.notFound : HttpStatus.ok;

  @override
  int get contentLength => cover?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(cover ?? Uint8List(0)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A small picture, drawn rather than stored.
Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 64, 64),
    ui.Paint()..color = const ui.Color(0xFF2E6F9E),
  );
  final image = await recorder.endRecording().toImage(64, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A channel whose connect resolves only when the test says so, which
/// is what a sign-out racing a slow handshake looks like.
class _GatedChannel extends EventsChannel {
  _GatedChannel({
    required this.gate,
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://gated', authToken: null);

  final Completer<void> gate;

  /// Whether the socket is open: connected and not closed since.
  bool up = false;

  @override
  Future<void> connect() => gate.future.then((_) => up = true);

  @override
  Future<void> close() async => up = false;
}

/// Counts what the user fan-out and the entity fan-out cost.
class _CountingRepository extends FakeRepository {
  int prefsReads = 0;
  int entityReads = 0;

  @override
  Future<Prefs> getPrefs() {
    prefsReads++;
    return super.getPrefs();
  }

  @override
  Future<EntityPlayState> getEntityPlayState(String pid) {
    entityReads++;
    return super.getEntityPlayState(pid);
  }

  /// When set, a batch read answers the states as they were when it was
  /// asked, but only once this completes: a read still out while the
  /// stream reports what happened after it.
  Completer<void>? statesGate;

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) async {
    final read = await super.listPlayStates(pids);
    await statesGate?.future;
    return read;
  }
}

/// A session without a sync engine, which is the web build's: the binder
/// hears the user stream through [bus], fed by hand here rather than by
/// the walk an invalidation frame starts.
Future<
  ({ProviderContainer container, ServerEventBus bus, _CountingRepository repo})
>
_bindWeb() async {
  final repo = _CountingRepository()
    ..sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-1', username: 'admin'),
    )
    ..libraryItems.add(testItem('tr-A'))
    // Heard through once and part way through again, which is what puts
    // a track on the resume shelf.
    ..playPositions['tr-A'] = 1000
    ..playStateLastPlayedAt['tr-A'] = DateTime.utc(2026, 9, 30);
  final bus = ServerEventBus();
  final container = appContainer(
    repo: repo,
    extra: [serverEventBusProvider.overrideWithValue(bus)],
  );
  container
    ..listen(syncBinderProvider, (_, _) {})
    ..listen(prefsControllerProvider, (_, _) {})
    ..listen(continueListeningShelfProvider, (_, _) {});
  await container.read(prefsControllerProvider.future);
  final resume = await container.read(continueListeningShelfProvider.future);
  expect(resume.items.map((item) => item.pid), <String>['tr-A']);
  return (container: container, bus: bus, repo: repo);
}

ServerSyncEvent _report(
  int positionMs, {
  bool finished = false,
  int minute = 0,
}) => ServerSyncEvent(
  kind: 'play-state',
  pid: 'tr-A',
  playState: PlayState(
    pid: 'tr-A',
    positionMs: positionMs,
    played: finished,
    finished: finished,
    playCount: finished ? 1 : 0,
    starred: false,
    updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
  ),
);

/// A server whose shelves refuse while [down], as one out of reach does.
class _RefusingRepository extends FakeRepository {
  bool down = false;

  /// Every read of the caller's playlists answered.
  var playlistReads = 0;

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) async {
    if (down) {
      throw const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
    }
    playlistReads++;
    return super.listPlaylists(
      cursor: cursor,
      limit: limit,
      containsItem: containsItem,
    );
  }

  @override
  Future<ItemPage> browse(
    DiscoveryList list, {
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
    int? seed,
  }) async {
    if (down) {
      throw const WaxDeckApiException(
        code: 'transport',
        message: 'connection refused',
      );
    }
    return super.browse(
      list,
      mediaType: mediaType,
      facet: facet,
      facetKey: facetKey,
      cursor: cursor,
      limit: limit,
      seed: seed,
    );
  }
}

/// Browser storage as a test holds it, and breaks it.
class _CursorStorage implements BrowserStorage {
  final values = <String, String>{};

  /// Every call throws while set, as a denied `localStorage` does.
  var broken = false;

  void _check() {
    if (broken) throw StateError('storage denied');
  }

  @override
  String? getItem(String key) {
    _check();
    return values[key];
  }

  @override
  void setItem(String key, String value) {
    _check();
    values[key] = value;
  }

  @override
  void removeItem(String key) {
    _check();
    values.remove(key);
  }
}

void main() {
  group('the binder over a hand-fed bus', () {
    testWidgets('a user pass reads again where a book was left off', (
      tester,
    ) async {
      final b = await _bindWeb();
      final resume = bookResumeProvider('bk-1');
      b.repo.bookResumes['bk-1'] = const BookResume(positionMs: 1000);
      b.container.listen(resume, (_, _) {});
      expect((await b.container.read(resume.future)).positionMs, 1000);
      // Another device went on with the book.
      b.repo.bookResumes['bk-1'] = const BookResume(positionMs: 90000);
      b.bus.add(const ServerSyncEvent(kind: 'play-state', pid: 'bk-1'));
      await tester.pump(const Duration(seconds: 6));
      expect(b.container.read(resume).value?.positionMs, 90000);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that only moves the position refetches no shelf '
        'and moves the ring without a read', (tester) async {
      final b = await _bindWeb();
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);
      // The first report of an item can put it on a shelf, so it hints.
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final (browses, batches, prefs) = (
        b.repo.browseCalls.length,
        b.repo.playStateBatches.length,
        b.repo.prefsReads,
      );

      b.bus.add(_report(90000, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.browseCalls.length, browses);
      expect(b.repo.prefsReads, prefs, reason: 'no user pass at all');
      expect(b.container.read(ring).value?['tr-A']?.positionMs, 90000);
      expect(
        b.repo.playStateBatches.length,
        batches,
        reason: 'the report is the state; reading it back is a round trip',
      );
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that only moves the position reorders what is '
        'ordered by progress, and nothing else', (tester) async {
      // Up next is the episodes most recently progressed first. No
      // playlist rule reads a position, and an unseeded random list is
      // drawn afresh on every read, so an open one would reshuffle with
      // every checkpoint.
      final b = await _bindWeb();
      final playlist = await b.repo.createPlaylist(
        name: 'In progress',
        kind: 'smart',
      );
      final detail = playlistDetailProvider(playlist.pid);
      b.container
        ..listen(upNextEpisodesProvider, (_, _) {})
        ..listen(detail, (_, _) {});
      await b.container.read(upNextEpisodesProvider.future);
      await b.container.read(detail.future);
      int detailReads() =>
          b.repo.playlistItemPageCalls.where((p) => p == playlist.pid).length;
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final (upNext, details, browses, prefs) = (
        b.repo.subscribedEpisodeCalls.length,
        detailReads(),
        b.repo.browseCalls.length,
        b.repo.prefsReads,
      );

      b.bus.add(_report(90000, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.subscribedEpisodeCalls.length, upNext + 1);
      expect(detailReads(), details, reason: 'no rule reads a position');
      expect(b.repo.browseCalls.length, browses, reason: 'no shelf moved');
      expect(b.repo.prefsReads, prefs, reason: 'no user pass at all');
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that moves more than the position moves the rings '
        'at once, not at the end of the window', (tester) async {
      final b = await _bindWeb();
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);
      // A first sighting opens the user pacer's window.
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 1));

      // Finished elsewhere inside that window: the pass it asks for waits
      // for the window's end, but the report already is the state.
      b.bus.add(_report(214000, finished: true, minute: 2));
      await tester.pump();

      expect(b.container.read(ring).value?['tr-A']?.finished, isTrue);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that lands while a window is on its first read is '
        'in the window when the read lands', (tester) async {
      // The read was asked before the report and answers what was there
      // then; the window's echo had nothing to write into yet.
      final b = await _bindWeb();
      b.repo
        ..playPositions['tr-A'] = 30000
        ..playStateUpdatedAt['tr-A'] = DateTime.utc(2026, 10, 1, 12, 1);
      final gate = Completer<void>();
      b.repo.statesGate = gate;
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await tester.pump();

      b.bus.add(_report(90000, minute: 2));
      await tester.pump();
      b.repo.statesGate = null;
      gate.complete();
      await tester.pump();

      expect((await b.container.read(ring.future))['tr-A']?.positionMs, 90000);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report older than a window\'s own read leaves it', (
      tester,
    ) async {
      final b = await _bindWeb();
      b.repo
        ..playPositions['tr-A'] = 120000
        ..playStateUpdatedAt['tr-A'] = DateTime.utc(2026, 10, 1, 12, 5);
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);

      // Stamped before what the read brought back: a report the stream
      // carried late.
      b.bus.add(_report(30000, minute: 2));
      await tester.pump();

      expect(b.container.read(ring).value?['tr-A']?.positionMs, 120000);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report reaches a window off screen without reading it '
        'back', (tester) async {
      final b = await _bindWeb();
      final ring = playProgressProvider(playPidsKey(<String>['tr-A']));
      final sub = b.container.listen(ring, (_, _) {});
      await b.container.read(ring.future);
      // Its screen is off stage, so its listener is paused, and a pass
      // marked it stale meanwhile.
      sub.pause();
      b.container.invalidate(ring);
      final batches = b.repo.playStateBatches.length;

      b.bus.add(_report(90000, minute: 2));
      await tester.pump();

      expect(
        b.repo.playStateBatches.length,
        batches,
        reason: 'nothing on screen asked for it',
      );
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('another device\'s star reaches the item at once, not at the '
        'end of the window', (tester) async {
      final b = await _bindWeb();
      final item = playStateControllerProvider('tr-A');
      b.container.listen(item, (_, _) {});
      await b.container.read(item.future);
      // The client's own first report opens the user pass's window.
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(milliseconds: 500));
      final reads = b.repo.playStateReads.length;

      final starred = _report(1000, minute: 2);
      b.bus.add(
        ServerSyncEvent(
          kind: starred.kind,
          pid: starred.pid,
          playState: PlayState(
            pid: 'tr-A',
            positionMs: 1000,
            played: false,
            finished: false,
            playCount: 0,
            starred: true,
            updatedAt: DateTime.utc(2026, 10, 1, 12, 2),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(b.repo.playStateReads.length, greaterThan(reads));
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that finishes the item refetches the shelves', (
      tester,
    ) async {
      final b = await _bindWeb();
      b.bus.add(_report(1000, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final (browses, prefs) = (b.repo.browseCalls.length, b.repo.prefsReads);

      b.bus.add(_report(214000, finished: true, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.browseCalls.length, greaterThan(browses));
      expect(b.repo.prefsReads, prefs + 1);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('a report that starts an item from the top refetches the '
        'shelves', (tester) async {
      // Only the position moved, but past zero: that is what puts an item
      // on a resume shelf.
      final b = await _bindWeb();
      b.bus.add(_report(0, minute: 1));
      await tester.pump(const Duration(seconds: 6));
      final prefs = b.repo.prefsReads;

      b.bus.add(_report(5000, minute: 2));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.prefsReads, prefs + 1);
      b.container.dispose();
      await tester.pump();
    });

    testWidgets('an entity-state marker refreshes only the entity families', (
      tester,
    ) async {
      final b = await _bindWeb();
      final star = entityPlayStateControllerProvider('ar-1');
      b.container.listen(star, (_, _) {});
      await b.container.read(star.future);
      final (browses, prefs, entities) = (
        b.repo.browseCalls.length,
        b.repo.prefsReads,
        b.repo.entityReads,
      );

      b.bus.add(const ServerSyncEvent(kind: 'entity-state', pid: 'ar-1'));
      await tester.pump(const Duration(seconds: 6));

      expect(b.repo.entityReads, entities + 1);
      expect(b.repo.browseCalls.length, browses);
      expect(b.repo.prefsReads, prefs);
      b.container.dispose();
      await tester.pump();
    });
  });

  test('a connect that resolves after stop() reports nothing', () async {
    final gate = Completer<void>();
    var caughtUp = 0;
    var reportedConnected = 0;
    late _GatedChannel channel;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              channel = _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              ),
      onCatalog: () => caughtUp++,
      onUser: () => caughtUp++,
    );
    live.onConnectionChanged = (_) => reportedConnected++;

    live.start();
    // The session ends while the handshake is still in flight; the
    // socket then comes up for nobody.
    live.stop();
    gate.complete();
    await gate.future;
    await Future<void>.delayed(Duration.zero);

    expect(caughtUp, 0, reason: 'no refresh lands on a dead session');
    expect(reportedConnected, 0, reason: 'and no banner state changes');
    expect(channel.up, isFalse, reason: 'the socket that came up is closed');
  });

  test('a connect that resolves while running catches up once', () async {
    final gate = Completer<void>();
    var catalog = 0;
    var user = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) =>
              _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              ),
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    addTearDown(live.stop);

    live.start();
    gate.complete();
    await gate.future;
    await Future<void>.delayed(Duration.zero);

    expect(catalog, 1, reason: 'the may-have-missed-changes refresh');
    expect(user, 1);
  });

  test('a throw from the connected body is not a dropped socket', () async {
    final gate = Completer<void>();
    var factoryCalls = 0;
    var wentDown = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            factoryCalls++;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      // The catch-up refresh breaks, the way a fan-out bug would.
      onCatalog: () => throw StateError('fan-out bug'),
      onUser: () {},
    );
    live.onConnectionChanged = (connected) {
      if (!connected) wentDown++;
    };
    addTearDown(live.stop);

    // The connect wiring happens inside start(), so the guarded zone
    // has to hold it: an unlistened future's error reports to the zone
    // its callbacks were registered in.
    final surfaced = <Object>[];
    runZonedGuarded(live.start, (error, _) => surfaced.add(error));
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(surfaced, [isA<StateError>()], reason: 'the bug is heard as itself');
    expect(wentDown, 0, reason: 'a healthy socket is not reported down');
    expect(factoryCalls, 1, reason: 'and no reconnect is scheduled');
  });

  test('an invalidation frame routes to its topic', () {
    // The frame path is the onFrame callback the listener hands its
    // channel; capturing it is how a test speaks as the server.
    late void Function(String) deliver;
    var user = 0;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: Completer<void>(),
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => fail('catalog was not the topic'),
      onUser: () => user++,
    );
    addTearDown(live.stop);

    live.start();
    deliver(
      jsonEncode(const <String, Object?>{
        'type': 'invalidate',
        'topic': 'user',
      }),
    );
    expect(user, 1);
  });

  group('a catalog invalidation', () {
    late void Function(String) deliver;

    /// What the listener did, in order.
    late List<Object> heard;
    late LiveInvalidations live;

    setUp(() {
      heard = [];
      live =
          LiveInvalidations(
              channelFactory:
                  ({required onFrame, required onDone, required subscribe}) {
                    deliver = onFrame;
                    return _GatedChannel(
                      gate: Completer<void>(),
                      onFrame: onFrame,
                      onDone: onDone,
                      subscribe: subscribe,
                    );
                  },
              onCatalog: () => heard.add('catalog'),
              onUser: () => heard.add('user'),
            )
            ..onCatalogNamed = ((names) {
              heard.add(names.unnamed ? 'unnamed' : names.pids);
            })
            ..start();
      addTearDown(live.stop);
    });

    void say(Object? pids, {Object? unnamed}) => deliver(
      jsonEncode({
        'type': 'invalidate',
        'topic': 'catalog',
        'pids': ?pids,
        'unnamed': ?unnamed,
      }),
    );

    test('that names what moved hands the names on, then refreshes', () {
      say(['al-AAA', 'tr-BBB']);
      expect(heard, [
        ['al-AAA', 'tr-BBB'],
        'catalog',
      ]);
    });

    test('that names nothing only refreshes', () {
      say(null);
      expect(heard, ['catalog']);
    });

    test('whose names do not read as names is a plain one', () {
      say('al-AAA');
      say(['al-AAA', 7]);
      say(<String>[]);
      say({'al-AAA': true});
      expect(heard, ['catalog', 'catalog', 'catalog', 'catalog']);
    });

    test('that left entities unnamed says so, then refreshes', () {
      say(null, unnamed: true);
      expect(heard, ['unnamed', 'catalog']);
    });

    test('whose marker does not read as one is a plain one', () {
      say(null, unnamed: false);
      say(null, unnamed: 'true');
      say(null, unnamed: 1);
      expect(heard, ['catalog', 'catalog', 'catalog']);
    });

    test('that carries the marker beside names is unnamed: they are not '
        'all of them', () {
      say(['al-AAA'], unnamed: true);
      expect(heard, ['unnamed', 'catalog']);
    });

    test('refreshes though the names\' listener throws, which is heard as '
        'itself', () {
      final surfaced = <Object>[];
      runZonedGuarded(() {
        live.onCatalogNamed = (_) => throw StateError('the listener broke');
        say(['al-AAA']);
        say(null, unnamed: true);
      }, (error, _) => surfaced.add(error));
      expect(heard, ['catalog', 'catalog']);
      expect(surfaced, [isA<StateError>(), isA<StateError>()]);
    });

    test('says nothing of names for another topic', () {
      deliver(
        jsonEncode({
          'type': 'invalidate',
          'topic': 'user',
          'pids': ['al-AAA'],
        }),
      );
      deliver(
        jsonEncode({'type': 'invalidate', 'topic': 'user', 'unnamed': true}),
      );
      expect(heard, ['user', 'user']);
    });
  });

  group('a resync', () {
    late void Function(String) deliver;

    /// What the listener did, in order.
    late List<String> heard;

    setUp(() {
      heard = [];
      final live =
          LiveInvalidations(
              channelFactory:
                  ({required onFrame, required onDone, required subscribe}) {
                    deliver = onFrame;
                    return _GatedChannel(
                      gate: Completer<void>(),
                      onFrame: onFrame,
                      onDone: onDone,
                      subscribe: subscribe,
                    );
                  },
              onCatalog: () => heard.add('catalog'),
              onUser: () => heard.add('user'),
            )
            ..onCatalogNamed = ((names) {
              heard.add(names.unnamed ? 'unnamed' : 'named');
            })
            ..start();
      addTearDown(live.stop);
    });

    void say(String? topic) =>
        deliver(jsonEncode({'type': 'resync', 'topic': ?topic}));

    // A replaced or repaired catalog can change any cover.
    test('that covers the catalog says entities went unnamed before the '
        'refresh it prompts', () {
      say('catalog');
      expect(heard, ['unnamed', 'catalog']);

      heard.clear();
      say(null);
      expect(heard, ['unnamed', 'catalog', 'user']);
    });

    test('of the user topic says nothing of names', () {
      say('user');
      expect(heard, ['user']);
    });

    test('of a topic this build does not know says nothing of names', () {
      say('lyrics');
      expect(heard, ['catalog', 'user']);
    });
  });

  test('a resync naming an unknown topic still refreshes everything', () async {
    final gate = Completer<void>()..complete();
    var catalog = 0, user = 0, radio = 0;
    late void Function(String) deliver;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    live.onRadio = () => radio++;
    live.start();
    addTearDown(live.stop);
    await gate.future;
    await Future<void>.delayed(Duration.zero);
    catalog = 0;
    user = 0;

    // Continuity recovery must not narrow as cursorless topics are added.
    deliver(jsonEncode({'type': 'resync', 'topic': 'radio'}));

    expect(catalog, 1);
    expect(user, 1);
    expect(radio, 0, reason: 'a resync is not a nudge');
  });

  test('a radio frame nudges only the radio listener', () async {
    final gate = Completer<void>()..complete();
    var catalog = 0, user = 0, player = 0, radio = 0;
    late void Function(String) deliver;
    final live = LiveInvalidations(
      channelFactory:
          ({required onFrame, required onDone, required subscribe}) {
            deliver = onFrame;
            return _GatedChannel(
              gate: gate,
              onFrame: onFrame,
              onDone: onDone,
              subscribe: subscribe,
            );
          },
      onCatalog: () => catalog++,
      onUser: () => user++,
    );
    live.onPlayer = () => player++;
    live.onRadio = () => radio++;
    live.start();
    addTearDown(live.stop);
    await gate.future;
    await Future<void>.delayed(Duration.zero);
    // The connect itself catches up once; only the frame is under test.
    catalog = 0;
    user = 0;

    deliver(jsonEncode({'type': 'invalidate', 'topic': 'radio'}));

    expect(radio, 1);
    expect(player, 0, reason: 'a radio frame is not a player frame');
    expect(catalog, 0);
    expect(user, 0, reason: 'and pulls no mirrored stream');
  });

  test(
    'a catch-up refreshes through its own callback when there is one',
    () async {
      // A user invalidation names no kind, so the web build walks the
      // stream to learn which surfaces moved; a (re)connect or a resync
      // may have lost changes the walk can no longer report.
      final gate = Completer<void>()..complete();
      var user = 0, catchUp = 0;
      late void Function(String) deliver;
      final live = LiveInvalidations(
        channelFactory:
            ({required onFrame, required onDone, required subscribe}) {
              deliver = onFrame;
              return _GatedChannel(
                gate: gate,
                onFrame: onFrame,
                onDone: onDone,
                subscribe: subscribe,
              );
            },
        onCatalog: () {},
        onUser: () => user++,
        onUserCatchUp: () => catchUp++,
      );
      live.start();
      addTearDown(live.stop);
      await gate.future;
      await Future<void>.delayed(Duration.zero);
      expect(catchUp, 1, reason: 'the connect catches up');
      expect(user, 0);

      deliver(jsonEncode({'type': 'invalidate', 'topic': 'user'}));
      deliver(jsonEncode({'type': 'resync', 'topic': 'user'}));

      expect(user, 1);
      expect(catchUp, 2);
    },
  );

  group('the session the socket rides', () {
    testWidgets('a socket the server closes as ended asks for the session '
        'at once', (tester) async {
      final link = FakeLink();
      var doubts = 0;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      )..onSessionInDoubt = () async => ++doubts > 0;
      live.start();
      await tester.pump();
      expect(doubts, 0, reason: 'a first connect rides the session just read');

      link.reachable = false;
      link.attempts.last.drop(sessionEndedCloseCode);

      expect(doubts, 1, reason: 'the server said the session ended');
      live.stop();
    });

    testWidgets('a drop asks for nothing; each failed attempt asks once, and '
        'the return once', (tester) async {
      final link = FakeLink();
      var doubts = 0;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      )..onSessionInDoubt = () async => ++doubts > 0;
      live.start();
      await tester.pump();

      // The network goes, as the browser reports it, and the attempts to
      // come back fail with it.
      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump();
      expect(doubts, 0, reason: 'a drop says nothing about the session');

      await tester.pump(const Duration(seconds: 1));
      expect(link.attempts, hasLength(2));
      expect(
        doubts,
        1,
        reason: 'an upgrade refused for want of a session fails like this',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(3));
      expect(doubts, 2, reason: 'once per attempt, as the backoff spaces them');

      link.reachable = true;
      await tester.pump(const Duration(seconds: 4));
      expect(link.attempts, hasLength(4));
      expect(doubts, 3, reason: 'another account may own the cookie now');

      await tester.pump(const Duration(minutes: 1));
      expect(doubts, 3, reason: 'a socket that is up asks no more');
      live.stop();
    });

    testWidgets('the network back while it waits to reconnect connects now, '
        'and starts the backoff over', (tester) async {
      final link = FakeLink();
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      );
      live.start();
      await tester.pump();

      // Down a while: the next attempt is four seconds off.
      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(3));

      live.networkBack();
      await tester.pump();
      expect(link.attempts, hasLength(4), reason: 'at once');
      await tester.pump(const Duration(seconds: 1));
      expect(link.attempts, hasLength(5), reason: 'a second after, not eight');

      link.reachable = true;
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(6));
      live.networkBack();
      await tester.pump(const Duration(minutes: 1));
      expect(link.attempts, hasLength(6), reason: 'a socket that is up stays');
      live.stop();
    });

    testWidgets('the network back says whether the socket stood up through '
        'it', (tester) async {
      final link = FakeLink();
      final reads = <Completer<bool>>[];
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      )..onSessionInDoubt = () => (reads..add(Completer<bool>())).last.future;
      live.start();
      await tester.pump();
      expect(live.networkBack(), isTrue, reason: 'nothing comes to catch up');

      link.reachable = false;
      link.attempts.last.drop(1006);
      await tester.pump();
      expect(live.networkBack(), isFalse, reason: 'it tries now');
      await tester.pump();
      expect(link.attempts, hasLength(2));

      link.reachable = true;
      expect(live.networkBack(), isFalse, reason: 'it tries now');
      await tester.pump();
      expect(link.attempts, hasLength(3));
      expect(
        live.networkBack(),
        isFalse,
        reason: 'up, its catch-up waits on the session',
      );
      reads.last.complete(true);
      await tester.pump();
      expect(live.networkBack(), isTrue);
      live.stop();
    });

    testWidgets('started again after a stop, its first failed connect waits '
        'a second, not the delay the outage had grown to', (tester) async {
      final link = FakeLink()..reachable = false;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
      );
      live.start();
      await tester.pump();
      // Down a while: the waits between attempts grow to four seconds, and
      // the one after the third failure would be eight.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(link.attempts, hasLength(3));

      live.stop();
      live.start();
      await tester.pump();
      expect(link.attempts, hasLength(4));

      await tester.pump(const Duration(seconds: 1));
      expect(link.attempts, hasLength(5), reason: 'a second after, not eight');
      live.stop();
    });

    group('a return', () {
      late FakeLink link;
      late Completer<bool> answer;
      late LiveInvalidations live;

      /// What the listener did, in order.
      late List<String> heard;

      setUp(() {
        link = FakeLink();
        heard = [];
        live =
            LiveInvalidations(
                channelFactory: link.factory,
                onCatalog: () => heard.add('catalog'),
                onUser: () => heard.add('user'),
              )
              ..onSessionInDoubt = (() => answer.future)
              ..onConnected = (() => heard.add('connected'))
              ..onPlayer = (() => heard.add('player'))
              ..onRadio = (() => heard.add('radio'))
              ..onControlFrame = (frame) => heard.add('${frame['type']}');
      });

      tearDown(() => live.stop());

      const caughtUp = ['connected', 'catalog', 'user'];

      void say(Map<String, Object?> frame) =>
          link.attempts.last.onFrame(jsonEncode(frame));

      /// What the socket says while its session is read: something of
      /// every kind a catch-up does not read again, and one it does.
      void sayMeanwhile() {
        say(const {'type': 'invalidate', 'topic': 'player'});
        say(const {'type': 'invalidate', 'topic': 'radio'});
        say(const {'type': 'session', 'session': <String, Object?>{}});
        say(const {'type': 'invalidate', 'topic': 'catalog'});
      }

      const saidMeanwhile = ['player', 'radio', 'session', 'catalog'];

      /// Up and caught up, then dropped and back a second later with the
      /// session read out.
      Future<void> back(
        WidgetTester tester, {
        void Function(Object error)? onError,
      }) async {
        // Made in the test's own zone, so its answer lands on the clock
        // the test pumps.
        answer = Completer<bool>();
        live.start();
        await tester.pump();
        expect(heard, caughtUp);
        heard.clear();
        // The reconnect, and so the replay, runs in the zone the drop is
        // reported in: that is where a listener's throw surfaces.
        if (onError == null) {
          link.attempts.last.drop(1006);
        } else {
          runZonedGuarded(
            () => link.attempts.last.drop(1006),
            (error, _) => onError(error),
          );
        }
        await tester.pump(const Duration(seconds: 1));
        expect(link.attempts, hasLength(2));
      }

      testWidgets('as the same account catches up once it answers, then '
          'hands on what the socket said meanwhile, in order', (tester) async {
        await back(tester);
        sayMeanwhile();
        await tester.pump();
        expect(heard, isEmpty, reason: 'nothing before the session answers');

        answer.complete(true);
        await tester.pump();
        expect(heard, [...caughtUp, ...saidMeanwhile]);

        heard.clear();
        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard, ['user'], reason: 'and hears the socket as it speaks');
      });

      /// What a frame said of the entities that changed, as heard.
      void hearNames() => live.onCatalogNamed = (names) => heard.add(
        names.unnamed ? 'unnamed' : 'named ${names.pids.join(' ')}',
      );

      testWidgets('hands on a held catalog frame with what it said of the '
          'entities that changed', (tester) async {
        hearNames();
        await back(tester);
        say(const {
          'type': 'invalidate',
          'topic': 'catalog',
          'pids': ['al-AAA', 'tr-BBB'],
        });
        say(const {'type': 'invalidate', 'topic': 'catalog'});
        say(const {'type': 'invalidate', 'topic': 'catalog', 'unnamed': true});
        await tester.pump();
        expect(heard, isEmpty);

        answer.complete(true);
        await tester.pump();
        expect(heard, [
          ...caughtUp,
          'named al-AAA tr-BBB',
          'catalog',
          'catalog',
          'unnamed',
          'catalog',
        ]);
      });

      /// More frames than are held, none of them the catalog's.
      void spill() {
        for (var i = 0; i <= LiveInvalidations.mostHeld; i++) {
          say(const {'type': 'invalidate', 'topic': 'player'});
        }
      }

      // The catch-up's own order: connected, the catalog, the user
      // topic, then the two a spill adds.
      const spilledUnnamed = [
        'connected',
        'unnamed',
        'catalog',
        'user',
        'player',
        'radio',
      ];

      testWidgets('names let go with a spill count as unnamed: the catch-up '
          'says so before it refreshes, once', (tester) async {
        hearNames();
        await back(tester);
        say(const {
          'type': 'invalidate',
          'topic': 'catalog',
          'pids': ['al-AAA'],
        });
        spill();
        await tester.pump();

        answer.complete(true);
        await tester.pump();
        expect(heard, spilledUnnamed);

        // The next return let nothing go.
        heard.clear();
        answer = Completer<bool>();
        link.attempts.last.drop(1006);
        await tester.pump(const Duration(seconds: 1));
        answer.complete(true);
        await tester.pump();
        expect(heard, caughtUp);
      });

      testWidgets('so does a marker let go with one, and names said after '
          'it', (tester) async {
        hearNames();
        await back(tester);
        say(const {'type': 'invalidate', 'topic': 'catalog', 'unnamed': true});
        spill();
        answer.complete(true);
        await tester.pump();
        expect(heard, spilledUnnamed);

        heard.clear();
        answer = Completer<bool>();
        link.attempts.last.drop(1006);
        await tester.pump(const Duration(seconds: 1));
        spill();
        say(const {
          'type': 'invalidate',
          'topic': 'catalog',
          'pids': ['al-AAA'],
        });
        answer.complete(true);
        await tester.pump();
        expect(heard, spilledUnnamed);
      });

      testWidgets('a spill that let no names go says nothing of them', (
        tester,
      ) async {
        hearNames();
        await back(tester);
        say(const {'type': 'invalidate', 'topic': 'catalog'});
        say(const {
          'type': 'invalidate',
          'topic': 'user',
          'pids': ['al-AAA'],
        });
        say(const {'type': 'resync', 'topic': 'user'});
        spill();
        say(const {'type': 'invalidate', 'topic': 'catalog'});
        answer.complete(true);
        await tester.pump();
        expect(heard, [...caughtUp, 'player', 'radio']);
      });

      testWidgets('a resync that covers the catalog, let go with a spill, '
          'counts as unnamed too', (tester) async {
        hearNames();
        await back(tester);
        say(const {'type': 'resync', 'topic': 'catalog'});
        spill();
        answer.complete(true);
        await tester.pump();
        expect(heard, spilledUnnamed);

        heard.clear();
        answer = Completer<bool>();
        link.attempts.last.drop(1006);
        await tester.pump(const Duration(seconds: 1));
        spill();
        say(const {'type': 'resync'});
        answer.complete(true);
        await tester.pump();
        expect(heard, spilledUnnamed);
      });

      testWidgets('hands on the rest of what was held though the names\' '
          'listener throws', (tester) async {
        final surfaced = <Object>[];
        live.onCatalogNamed = (_) => throw StateError('the listener broke');
        await back(tester, onError: surfaced.add);
        say(const {
          'type': 'invalidate',
          'topic': 'catalog',
          'pids': ['al-AAA'],
        });
        say(const {'type': 'invalidate', 'topic': 'player'});
        await tester.pump();

        answer.complete(true);
        await tester.pump();
        expect(heard, [...caughtUp, 'catalog', 'player']);
        expect(surfaced, [isA<StateError>()], reason: 'heard as itself');

        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard.last, 'user', reason: 'and the socket is still heard');
      });

      testWidgets('a read that fails hands it on too', (tester) async {
        await back(tester);
        sayMeanwhile();
        await tester.pump();

        answer.completeError(StateError('the read broke'));
        await tester.pump();

        expect(heard, [...caughtUp, ...saidMeanwhile]);
      });

      testWidgets('as an account that left catches nothing up and hands on '
          'nothing', (tester) async {
        await back(tester);
        sayMeanwhile();
        await tester.pump();

        answer.complete(false);
        await tester.pump();
        say(const {'type': 'invalidate', 'topic': 'user'});
        await tester.pump();

        expect(heard, isEmpty);
      });

      testWidgets('closed as ended while its session is read, hands on '
          'nothing it said', (tester) async {
        await back(tester);
        sayMeanwhile();
        link.reachable = false;
        link.attempts.last.drop(sessionEndedCloseCode);

        answer.complete(true);
        await tester.pump();

        expect(heard, isEmpty);
        live.stop();
      });

      testWidgets('the reply to a command sent while its session is read '
          'reaches the command', (tester) async {
        final bus = ConnectBus(send: live.sendControl);
        live.onControlFrame = bus.handleFrame;
        await back(tester);

        String? registered;
        bus
            .registerEndpoint(name: 'desk')
            .then((id) => registered = id, onError: (Object _) {})
            .ignore();
        final sent = link.attempts.last.sent;
        expect(sent, hasLength(1), reason: 'the socket takes frames at once');
        final id = (jsonDecode(sent.single) as Map<String, Object?>)['id'];
        say({'type': 'ack', 'id': id, 'endpointId': 'ep-desk'});
        await tester.pump();

        answer.complete(true);
        await tester.pump();

        expect(registered, 'ep-desk');
      });

      testWidgets('past ${LiveInvalidations.mostHeld} frames lets them go, '
          'and catches up every topic instead', (tester) async {
        await back(tester);
        for (var i = 0; i <= LiveInvalidations.mostHeld; i++) {
          say(const {'type': 'invalidate', 'topic': 'player'});
        }
        sayMeanwhile();
        await tester.pump();

        answer.complete(true);
        await tester.pump();

        expect(heard, [...caughtUp, 'player', 'radio']);
      });

      testWidgets('a pong said while its session is read is not paired with '
          'the ping the catch-up sends', (tester) async {
        var clock = DateTime.utc(2026, 7, 21, 12);
        final bus = ConnectBus(send: live.sendControl, now: () => clock);
        live
          ..onControlFrame = ((frame) {
            heard.add('${frame['type']}');
            bus.handleFrame(frame);
          })
          ..onConnected = (() {
            heard.add('connected');
            bus.ping();
          });
        Object? lastPingT() =>
            (jsonDecode(link.attempts.last.sent.last)
                as Map<String, Object?>)['t'];
        await back(tester);

        // The ping timer fires while the read is out, and the server
        // answers on the new socket, its clock five seconds ahead.
        clock = clock.add(const Duration(minutes: 1));
        bus.ping();
        final mid = lastPingT();
        say({
          'type': 'pong',
          't': mid,
          'at': clock.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
        });

        clock = clock.add(const Duration(seconds: 3));
        answer.complete(true);
        await tester.pump();
        expect(heard, [...caughtUp, 'pong'], reason: 'the pong is heard');
        final ping = lastPingT();
        expect(ping, isNot(mid), reason: 'the catch-up pinged again');
        expect(
          bus.serverClockOffset,
          Duration.zero,
          reason: 'it answered the ping from before, not the one just sent',
        );

        say({
          'type': 'pong',
          't': ping,
          'at': clock.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
        });
        expect(bus.serverClockOffset, const Duration(seconds: 5));
      });

      testWidgets('stopped while its session is read and started again, '
          'hears the socket', (tester) async {
        await back(tester);
        sayMeanwhile();
        live.stop();

        live.start();
        await tester.pump();
        expect(link.attempts, hasLength(3));
        expect(heard, caughtUp, reason: 'a start is a first connect');
        heard.clear();

        answer.complete(true);
        await tester.pump();
        expect(heard, isEmpty, reason: 'the old read touches nothing now');

        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard, ['user']);
      });

      testWidgets('stopped while down and started again, connects as a '
          'first connect', (tester) async {
        answer = Completer<bool>();
        live.start();
        await tester.pump();
        heard.clear();
        link.attempts.last.drop(1006);
        live.stop();

        live.start();
        await tester.pump();

        expect(link.attempts, hasLength(2));
        expect(heard, caughtUp, reason: 'no session to read before it');
        say(const {'type': 'invalidate', 'topic': 'user'});
        expect(heard, [...caughtUp, 'user']);
      });
    });
  });

  group('the binder on the web\'s listener', () {
    testWidgets('reads again only what failed when a return is answered with '
        'nothing changed', (tester) async {
      final repo = _RefusingRepository()
        ..sessionState = const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-1', username: 'admin'),
        );
      final link = FakeLink()..catalogAnswer = {'unchanged': true};
      final storage = _CursorStorage();
      final container = appContainer(
        repo: repo,
        observers: [FirstBuildObserver()],
        extra: [
          liveListenerProvider.overrideWithValue(true),
          liveChannelFactoryProvider.overrideWithValue(link.factory),
          catalogCursorStorageProvider.overrideWithValue(storage),
        ],
      );
      await container.read(authControllerProvider.future);
      storage.values[CatalogCursor.storageKey] = jsonEncode({
        'server': container.read(serverBaseUrlProvider),
        'account': 'us-1',
        'since': 'c-7',
      });
      // The library's newest, Home's and the music hub's: catalog reads
      // alone, which no user pass asks.
      int reads({required bool music}) => repo.browseCalls
          .where(
            (call) =>
                call.list == DiscoveryList.recentlyAdded &&
                (call.mediaType == MediaType.music) == music,
          )
          .length;
      container.listen(musicRecentlyAddedShelfProvider, (_, _) {});
      await container.read(musicRecentlyAddedShelfProvider.future);
      // Read while the server was out of reach, every retry spent.
      repo.down = true;
      container.listen(recentlyAddedShelfProvider, (_, _) {});
      await tester.pump(const Duration(minutes: 1));
      expect(container.read(recentlyAddedShelfProvider).hasError, isTrue);
      repo.down = false;
      final (failed, healthy) = (reads(music: false), reads(music: true));

      final binder = container.listen(syncBinderProvider, (_, _) {});
      await tester.pump(const Duration(seconds: 6));

      expect(link.attempts.single.subscribed, {'catalogSince': 'c-7'});
      expect(reads(music: false), failed + 1);
      expect(reads(music: true), healthy);
      // The session ends: the binder goes, then everything else.
      binder.close();
      await tester.pump(const Duration(seconds: 1));
      expect(container.exists(syncBinderProvider), isFalse);
      expect(container.read(liveLinkProvider), isNull);
      container.dispose();
      await tester.pump();
    });

    group('when the browser says it is online', () {
      /// A session whose socket came up, the library's newest held and read
      /// by Home and the caller's playlists, both failing while [down], and
      /// the music hub's newest, healthy.
      Future<
        ({
          ProviderContainer container,
          _RefusingRepository repo,
          FakeLink link,
          StreamController<void> online,
          int Function({required bool music}) reads,
        })
      >
      connected(WidgetTester tester, {required bool down}) async {
        final repo = _RefusingRepository()
          ..sessionState = const SessionState(
            authenticated: true,
            user: WaxDeckUser(id: 'us-1', username: 'admin'),
          );
        final link = FakeLink();
        final online = StreamController<void>.broadcast();
        addTearDown(online.close);
        final container = appContainer(
          repo: repo,
          observers: [FirstBuildObserver()],
          extra: [
            liveListenerProvider.overrideWithValue(true),
            liveChannelFactoryProvider.overrideWithValue(link.factory),
            catalogCursorStorageProvider.overrideWithValue(_CursorStorage()),
            networkReturnsProvider.overrideWithValue(online.stream),
          ],
        );
        await container.read(authControllerProvider.future);
        container.listen(syncBinderProvider, (_, _) {});
        await tester.pump(const Duration(seconds: 6));
        expect(container.read(liveLinkProvider), isTrue);
        container.listen(musicRecentlyAddedShelfProvider, (_, _) {});
        await container.read(musicRecentlyAddedShelfProvider.future);
        repo.down = down;
        container
          ..listen(recentlyAddedShelfProvider, (_, _) {})
          ..listen(playlistsProvider, (_, _) {});
        // Every retry spent.
        await tester.pump(const Duration(minutes: 1));
        expect(container.read(recentlyAddedShelfProvider).hasError, down);
        expect(container.read(playlistsProvider).hasError, down);
        repo.down = false;
        int reads({required bool music}) => repo.browseCalls
            .where(
              (call) =>
                  call.list == DiscoveryList.recentlyAdded &&
                  (call.mediaType == MediaType.music) == music,
            )
            .length;
        return (
          container: container,
          repo: repo,
          link: link,
          online: online,
          reads: reads,
        );
      }

      testWidgets('with the socket up, reads a list in error again, '
          'once', (tester) async {
        final s = await connected(tester, down: true);
        final (failed, healthy) = (s.reads(music: false), s.reads(music: true));
        s.online.add(null);
        await tester.pump(const Duration(seconds: 6));
        expect(s.reads(music: false), failed + 1);
        expect(s.reads(music: true), healthy);
        expect(s.link.attempts, hasLength(1));
        s.container.dispose();
        await tester.pump();
      });

      testWidgets('with the socket up, reads a user list in error again, '
          'once', (tester) async {
        final s = await connected(tester, down: true);
        final before = s.repo.playlistReads;
        s.online.add(null);
        await tester.pump(const Duration(seconds: 6));
        expect(s.repo.playlistReads, before + 1);
        s.container.dispose();
        await tester.pump();
      });

      testWidgets('with the socket down, leaves what failed to the reconnect '
          'it hurries: each read once', (tester) async {
        final s = await connected(tester, down: true);
        s.link.reachable = false;
        s.link.attempts.last.drop(1006);
        await tester.pump(const Duration(seconds: 2));
        final (failed, playlists, attempts) = (
          s.reads(music: false),
          s.repo.playlistReads,
          s.link.attempts.length,
        );
        // The socket is up, and its catch-up waits on the session.
        final session = s.repo.getSessionGate = Completer<void>();
        s.link.reachable = true;
        s.online.add(null);
        await tester.pump();
        expect(s.link.attempts, hasLength(attempts + 1), reason: 'at once');
        await tester.pump(const Duration(seconds: 6));
        expect(
          (s.reads(music: false), s.repo.playlistReads),
          (failed, playlists),
          reason: 'nothing is read before the session answers',
        );
        s.repo.getSessionGate = null;
        session.complete();
        await tester.pump(const Duration(seconds: 6));
        expect(s.container.read(liveLinkProvider), isTrue);
        expect(s.reads(music: false), failed + 1);
        expect(s.repo.playlistReads, playlists + 1);
        s.container.dispose();
        await tester.pump();
      });

      testWidgets('with the socket up, leaves a healthy user list '
          'alone', (tester) async {
        final s = await connected(tester, down: false);
        final before = s.repo.playlistReads;
        expect(before, greaterThan(0));
        s.online.add(null);
        await tester.pump(const Duration(seconds: 6));
        expect(s.repo.playlistReads, before);
        s.container.dispose();
        await tester.pump();
      });

      testWidgets('with the socket up, leaves a healthy list '
          'alone', (tester) async {
        final s = await connected(tester, down: false);
        final (home, music) = (s.reads(music: false), s.reads(music: true));
        s.online.add(null);
        await tester.pump(const Duration(seconds: 6));
        expect((s.reads(music: false), s.reads(music: true)), (home, music));
        s.container.dispose();
        await tester.pump();
      });
    });
  });

  group('the catalog cursor', () {
    const server = 'https://wax.example';
    late _CursorStorage storage;
    late FakeLink link;

    setUp(() {
      storage = _CursorStorage();
      link = FakeLink();
    });

    /// A listener over [storage] for [account] on [at], started.
    LiveInvalidations listening({String account = 'us-1', String at = server}) {
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () {},
        onUser: () {},
        cursor: CatalogCursor(storage: storage, server: at, account: account),
      )..start();
      addTearDown(live.stop);
      return live;
    }

    /// What the newest socket subscribed with.
    Future<Map<String, Object?>> subscribed() async =>
        jsonDecode(await link.attempts.last.subscribe())
            as Map<String, Object?>;

    void say(Map<String, Object?> frame) =>
        link.attempts.last.onFrame(jsonEncode(frame));

    Future<void> reconnect(WidgetTester tester) async {
      link.attempts.last.drop(1006);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('none heard subscribes as before', (tester) async {
      listening();
      await tester.pump();
      expect(await subscribed(), isEmpty);
    });

    testWidgets('one heard is presented on the next subscribe', (tester) async {
      listening();
      await tester.pump();
      say({'type': 'invalidate', 'topic': 'catalog', 'since': 'c-7'});
      say({
        'type': 'invalidate',
        'topic': 'catalog',
        'pids': ['al-A'],
        'since': 'c-9',
      });
      await reconnect(tester);

      expect(link.attempts, hasLength(2));
      expect(await subscribed(), {'catalogSince': 'c-9'});
    });

    testWidgets('a frame without one leaves the one heard', (tester) async {
      listening();
      await tester.pump();
      say({'type': 'invalidate', 'topic': 'catalog', 'since': 'c-7'});
      say({'type': 'invalidate', 'topic': 'catalog'});
      say({'type': 'invalidate', 'topic': 'user', 'since': 'u-1'});
      say({'type': 'resync', 'topic': 'catalog'});
      await reconnect(tester);

      expect(await subscribed(), {'catalogSince': 'c-7'});
    });

    testWidgets('is presented by a new listener over the same storage, for '
        'the same server and account alone', (tester) async {
      final first = listening();
      await tester.pump();
      say({'type': 'invalidate', 'topic': 'catalog', 'since': 'c-7'});
      first.stop();

      listening();
      await tester.pump();
      expect(await subscribed(), {'catalogSince': 'c-7'}, reason: 'a reload');

      listening(account: 'us-2');
      await tester.pump();
      expect(await subscribed(), isEmpty, reason: 'another account');

      listening(at: 'https://other.example');
      await tester.pump();
      expect(await subscribed(), isEmpty, reason: 'another server');
      // The subscribe-time frame the reload's cursor drew.
      await tester.pump(Duration.zero);
    });

    testWidgets('another account\'s is not presented after it hears its own', (
      tester,
    ) async {
      listening();
      await tester.pump();
      say({'type': 'invalidate', 'topic': 'catalog', 'since': 'c-7'});

      listening(account: 'us-2');
      await tester.pump();
      say({'type': 'invalidate', 'topic': 'catalog', 'since': 'c-8'});

      listening();
      await tester.pump();
      expect(await subscribed(), isEmpty);
    });

    group('a connect', () {
      /// Each answer that said the catalog is current, as heard.
      late List<bool> currents;
      setUp(() => currents = []);

      /// A listener whose storage holds a cursor heard earlier when [held],
      /// counting its catalog passes from its first connect on.
      Future<({LiveInvalidations live, List<int> passes})> connecting(
        WidgetTester tester, {
        required bool held,
      }) async {
        if (held) {
          storage.values[CatalogCursor.storageKey] = jsonEncode({
            'server': server,
            'account': 'us-1',
            'since': 'c-7',
          });
        }
        final passes = [0];
        final live =
            LiveInvalidations(
                channelFactory: link.factory,
                onCatalog: () => passes[0]++,
                onUser: () {},
                cursor: CatalogCursor(
                  storage: storage,
                  server: server,
                  account: 'us-1',
                ),
              )
              ..onCatalogCurrent = (() => currents.add(true))
              ..start();
        addTearDown(live.stop);
        await tester.pump();
        await tester.pump(Duration.zero);
        return (live: live, passes: passes);
      }

      testWidgets('presenting a cursor the server answers with nothing '
          'changed makes no catalog pass', (tester) async {
        link.catalogAnswer = {'unchanged': true};
        final c = await connecting(tester, held: true);
        expect(await subscribed(), {'catalogSince': 'c-7'});
        expect(c.passes.single, 0);
        expect(currents, [true], reason: 'what failed is read again');
      });

      testWidgets('presenting a cursor the server answers with a change named '
          'makes one', (tester) async {
        link.catalogAnswer = {
          'pids': ['al-A'],
        };
        final c = await connecting(tester, held: true);
        expect(c.passes.single, 1);
      });

      testWidgets('presenting a cursor the server answers with nothing named '
          'and nothing unnamed, as for a genre, makes one', (tester) async {
        final c = await connecting(tester, held: true);
        expect(await subscribed(), {'catalogSince': 'c-7'});
        expect(c.passes.single, 1);
        expect(currents, isEmpty);
      });

      testWidgets('presenting a cursor the server answers with entities '
          'changed unnamed makes one', (tester) async {
        link.catalogAnswer = {'unnamed': true};
        final c = await connecting(tester, held: true);
        expect(c.passes.single, 1);
      });

      testWidgets('presenting no cursor makes one', (tester) async {
        final c = await connecting(tester, held: false);
        expect(await subscribed(), isEmpty);
        expect(c.passes.single, 1);
      });

      testWidgets('a catalog frame after an answer with nothing changed makes '
          'one', (tester) async {
        link.catalogAnswer = {'unchanged': true};
        final c = await connecting(tester, held: true);
        say({'type': 'invalidate', 'topic': 'catalog'});
        expect(c.passes.single, 1);
      });

      testWidgets('a tab presents the cursor it held when it started, not one '
          'another tab stored before its first connect', (tester) async {
        link.reachable = false;
        final c = await connecting(tester, held: true);
        storage.values[CatalogCursor.storageKey] = jsonEncode({
          'server': server,
          'account': 'us-1',
          'since': 'c-9',
        });
        link.reachable = true;
        c.live.networkBack();
        await tester.pump();
        await tester.pump(Duration.zero);
        expect(await subscribed(), {'catalogSince': 'c-7'});
      });

      testWidgets('a return whose held frames spill passes in its catch-up', (
        tester,
      ) async {
        link.catalogAnswer = {'unchanged': true};
        final answer = Completer<bool>();
        final c = await connecting(tester, held: true);
        expect(c.passes.single, 0);
        c.live.onSessionInDoubt = () => answer.future;
        link.attempts.last.drop(1006);
        await tester.pump(const Duration(seconds: 1));
        expect(link.attempts, hasLength(2));
        // The answer goes with the rest.
        for (var i = 0; i <= LiveInvalidations.mostHeld; i++) {
          say(const {'type': 'invalidate', 'topic': 'player'});
        }
        answer.complete(true);
        await tester.pump();
        expect(c.passes.single, 1);
      });
    });

    testWidgets('storage that throws leaves the session working', (
      tester,
    ) async {
      storage.broken = true;
      var catalog = 0;
      final live = LiveInvalidations(
        channelFactory: link.factory,
        onCatalog: () => catalog++,
        onUser: () {},
        cursor: CatalogCursor(storage: storage, server: server, account: 'u'),
      )..start();
      addTearDown(live.stop);
      await tester.pump();
      expect(await subscribed(), isEmpty);

      say({'type': 'invalidate', 'topic': 'catalog', 'since': 'c-7'});
      expect(catalog, 2, reason: 'the catch-up, then the frame');
      await reconnect(tester);
      expect(await subscribed(), {'catalogSince': 'c-7'}, reason: 'held here');
    });
  });

  group('a cover set on another device, under an open artists index', () {
    const artist = 'ar-01HZX5N8QW3F4V9T2B7KD3M9R6';

    tearDown(() => PaintingBinding.instance.imageCache.clear());

    /// Whether the index draws a decoded picture.
    bool drawsAPicture(WidgetTester tester) => tester
        .widgetList<RawImage>(
          find.descendant(
            of: find.byType(MusicIndexScreen),
            matching: find.byType(RawImage),
          ),
        )
        .any((raw) => raw.image != null);

    testWidgets('a row drawn as a monogram after a 404 asks again under a '
        'new name once a frame names its artist, and shows the '
        'picture', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cover = (await tester.runAsync(_png))!;
      final server = _ArtServer();
      debugNetworkImageHttpClientProvider = () => server;
      // Before the body ends: the binding checks it there.
      void restore() => debugNetworkImageHttpClientProvider = null;
      addTearDown(restore);
      final repo =
          FakeRepository(
              sessionState: const SessionState(
                authenticated: true,
                user: WaxDeckUser(id: 'us-1', username: 'admin'),
              ),
            )
            ..facets['artist'] = [
              FacetBucket(
                key: artist.substring(3),
                label: 'The Bree Trio',
                count: 1,
                entityPid: artist,
              ),
            ];
      final art = repo.artUrlFor(artist);
      final store = NetworkArtworkStore(baseUrl: '');
      addTearDown(store.dispose);
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      final downloads = FakeDownloads();
      addTearDown(downloads.dispose);
      final link = FakeLink();
      final engine = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: link.factory,
      );
      addTearDown(engine.dispose);
      final container = appContainer(
        repo: repo,
        artwork: store,
        downloads: downloads,
        sync: engine,
        mirror: db,
        // The decode below runs on the real clock, where the plugin
        // behind the real port would be asked and found missing.
        extra: [
          shareIntakeProvider.overrideWithValue(const InertShareIntakePort()),
        ],
      );
      await pumpWholeApp(tester, container: container);
      container
          .read(routerProvider)
          .go(WaxRoute.musicIndex(MusicDimension.artists));
      await tester.pumpAndSettle();
      expect(find.text('The Bree Trio'), findsOneWidget);
      expect(server.asked, ['$art?size=64']);
      expect(drawsAPicture(tester), isFalse);
      // Past the session's own start, so the frame's refresh lands at
      // once.
      await tester.pump(kCatalogRefreshWindow * 2);

      server.covers[art] = cover;
      link.attempts.last.onFrame(
        jsonEncode({
          'type': 'invalidate',
          'topic': 'catalog',
          'pids': [artist],
        }),
      );
      await engine.beforeSync(() async {});
      await tester.pumpAndSettle();

      expect(server.asked, hasLength(2));
      expect(
        server.asked.last,
        matches(
          RegExp(
            '^${RegExp.escape(art)}'
            r'\?size=64&v=\d+$',
          ),
        ),
      );
      // The decode is the engine's, outside the test's clock.
      for (var i = 0; i < 500 && !drawsAPicture(tester); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(drawsAPicture(tester), isTrue);
      restore();
    });
  });
}
