import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auto/media_session_feed.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// A session that records everything published to it, which is the whole
/// of what the OS surfaces would show.
class _RecordingSession implements MediaSessionPort {
  final List<MediaSessionItem?> published = <MediaSessionItem?>[];
  final List<(List<MediaSessionItem>, int)> queues =
      <(List<MediaSessionItem>, int)>[];

  MediaSessionItem? get last => published.isEmpty ? null : published.last;

  @override
  void publish(MediaSessionItem? item) => published.add(item);

  @override
  void publishQueue(List<MediaSessionItem> items, {int index = 0}) =>
      queues.add((items, index));

  /// Recorded apart from [publishQueue], because which of the two a
  /// track advance uses is the point.
  final List<int> indexMoves = <int>[];

  @override
  void publishQueueIndex(int index) => indexMoves.add(index);

  @override
  void showExtra(MediaSessionExtra? extra) {}
}

ItemSummary _item(
  String pid, {
  String title = 'Track',
  String? artist = 'Artist',
  String? album = 'Album',
  int durationMs = 180000,
  String? artUrl,
}) => ItemSummary(
  pid: pid,
  mediaType: MediaType.music,
  title: title,
  durationMs: durationMs,
  artist: artist,
  album: album,
  artUrl: artUrl,
);

QueueState _queue(List<String> pids, {int index = 0}) => QueueState(
  entries: <QueueEntry>[
    for (var i = 0; i < pids.length; i++)
      QueueEntry(queueId: '$i', pid: pids[i]),
  ],
  sourceOrder: <String>[for (var i = 0; i < pids.length; i++) '$i'],
  currentIndex: index,
  shuffled: false,
  repeat: QueueRepeat.off,
  source: const QueueSource(kind: QueueSourceKind.album, label: 'Album'),
  nextQueueId: pids.length,
);

RadioStation _station() => RadioStation(
  pid: 'rs-1',
  name: 'Fixture FM',
  streamUrl: 'https://example.invalid/stream',
  createdAt: DateTime.utc(2026),
  logoUrl: 'https://example.invalid/logo.png',
);

void main() {
  late _RecordingSession session;
  late MediaSessionFeed feed;
  late List<String?> artworkAsked;

  setUp(() {
    session = _RecordingSession();
    artworkAsked = <String?>[];
    feed = MediaSessionFeed(
      session: session,
      artwork: (artUrl) async {
        artworkAsked.add(artUrl);
        return artUrl == null ? null : Uri.parse('file:///covers/cover');
      },
      stationLogoUrl: (pid) => '/api/v1/radio/stations/$pid/logo',
    );
  });

  void update({
    RadioPlayback radio = const RadioPlayback(),
    NowPlaying now = NowPlaying.nothing,
    bool remote = false,
    QueueState? queue,
    Map<String, ItemSummary> known = const <String, ItemSummary>{},
  }) => feed.update(
    radio: radio,
    now: now,
    remote: remote,
    queue: queue ?? _queue(const <String>[]),
    summaryFor: (pid) => known[pid],
  );

  test('an item is published with what an OS surface can draw', () async {
    final item = _item('tr-1', artUrl: '/api/v1/items/tr-1/art');
    update(
      now: NowPlaying(
        entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
        item: item,
      ),
      queue: _queue(const <String>['tr-1']),
      known: <String, ItemSummary>{'tr-1': item},
    );

    final published = session.published.first!;
    expect(published.id, 'tr-1');
    expect(published.title, 'Track');
    expect(published.artist, 'Artist');
    expect(published.album, 'Album');
    expect(published.duration, const Duration(minutes: 3));
    expect(published.live, isFalse);
    // The cover is fetched off the critical path and published behind
    // the metadata, so the lock screen is never blank while it lands.
    expect(published.artUri, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(session.last!.artUri, Uri.parse('file:///covers/cover'));
    expect(artworkAsked, <String>['/api/v1/items/tr-1/art']);
  });

  test('the queue is published whole, in play order, with its index', () {
    final items = <String, ItemSummary>{
      'tr-1': _item('tr-1', title: 'One'),
      'tr-2': _item('tr-2', title: 'Two'),
    };
    update(
      now: NowPlaying(
        entry: const QueueEntry(queueId: '1', pid: 'tr-2'),
        item: items['tr-2'],
      ),
      queue: _queue(const <String>['tr-1', 'tr-2', 'tr-3'], index: 1),
      known: items,
    );

    final (rows, index) = session.queues.single;
    expect(index, 1);
    expect(rows.map((r) => r.id), <String>['tr-1', 'tr-2', 'tr-3']);
    // A row nothing has named yet keeps its place: the OS steps to a row
    // by index, so closing the gap would skip to the wrong item.
    expect(rows.map((r) => r.title), <String>['One', 'Two', 'Queued item']);
    // Rows carry no artwork; only what is playing does.
    expect(rows.every((r) => r.artUri == null), isTrue);
  });

  test('a station is live, named by its logo, and has no queue', () {
    update(
      radio: RadioPlayback(station: _station(), nowPlaying: 'Song - Band'),
      queue: _queue(const <String>['tr-1']),
    );

    final published = session.published.first!;
    expect(published.title, 'Fixture FM');
    expect(published.artist, 'Song - Band');
    expect(published.live, isTrue);
    expect(published.duration, isNull);
    expect(artworkAsked, <String>['/api/v1/radio/stations/rs-1/logo']);
    // Nothing to step through, so the last queue published is cleared
    // rather than left offering rows a skip cannot reach.
    expect(session.queues.single.$1, isEmpty);
  });

  test('a station outranks the item whose queue is still standing', () {
    final item = _item('tr-1');
    update(
      radio: RadioPlayback(station: _station()),
      now: NowPlaying(
        entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
        item: item,
      ),
      queue: _queue(const <String>['tr-1']),
      known: <String, ItemSummary>{'tr-1': item},
    );
    expect(session.published.single!.title, 'Fixture FM');
  });

  test('a station ending republishes the item underneath it', () {
    final item = _item('tr-1');
    final now = NowPlaying(
      entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
      item: item,
    );
    final queue = _queue(const <String>['tr-1']);
    final known = <String, ItemSummary>{'tr-1': item};
    update(
      radio: RadioPlayback(station: _station()),
      now: now,
      queue: queue,
      known: known,
    );
    update(now: now, queue: queue, known: known);

    expect(session.published.map((p) => p?.title), <String?>[
      'Fixture FM',
      'Track',
    ]);
    expect(session.queues.last.$1.map((r) => r.id), <String>['tr-1']);
  });

  test('a session on another endpoint publishes nothing at all', () {
    final item = _item('tr-1');
    update(
      now: NowPlaying(
        entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
        item: item,
      ),
      remote: true,
      queue: _queue(const <String>['tr-1']),
      known: <String, ItemSummary>{'tr-1': item},
    );
    // Nothing was ever published, so there is nothing to clear either.
    expect(session.published, isEmpty);
    expect(session.queues, isEmpty);
  });

  test('handing playback away clears what was published', () {
    final item = _item('tr-1');
    final now = NowPlaying(
      entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
      item: item,
    );
    final queue = _queue(const <String>['tr-1']);
    final known = <String, ItemSummary>{'tr-1': item};
    update(now: now, queue: queue, known: known);
    update(now: now, remote: true, queue: queue, known: known);

    expect(session.published.last, isNull);
    expect(session.queues.last.$1, isEmpty);
  });

  test('an unchanged item is not republished', () {
    final item = _item('tr-1');
    final now = NowPlaying(
      entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
      item: item,
    );
    final queue = _queue(const <String>['tr-1']);
    final known = <String, ItemSummary>{'tr-1': item};
    for (var i = 0; i < 5; i++) {
      update(now: now, queue: queue, known: known);
    }
    // The position ticks several times a second and each one reaches
    // here; MPRIS and the Windows controls emit a change signal per
    // publish, so this guard is what keeps that from being a signal
    // storm.
    expect(session.published, hasLength(1));
    expect(session.queues, hasLength(1));
  });

  test('a cover that lands after the track changed is dropped', () async {
    final first = _item('tr-1', artUrl: '/art/1');
    final second = _item('tr-2', title: 'Second', artUrl: null);
    update(
      now: NowPlaying(
        entry: const QueueEntry(queueId: '0', pid: 'tr-1'),
        item: first,
      ),
      queue: _queue(const <String>['tr-1']),
      known: <String, ItemSummary>{'tr-1': first},
    );
    update(
      now: NowPlaying(
        entry: const QueueEntry(queueId: '1', pid: 'tr-2'),
        item: second,
      ),
      queue: _queue(const <String>['tr-2']),
      known: <String, ItemSummary>{'tr-2': second},
    );
    await Future<void>.delayed(Duration.zero);

    expect(session.last!.id, 'tr-2');
    expect(session.last!.artUri, isNull);
  });
}
