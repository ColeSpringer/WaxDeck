import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

StoredQueue _queue(
  List<String> pids, {
  int currentIndex = 0,
  bool shuffled = false,
  String repeat = 'off',
  List<int>? sourceRanks,
}) {
  return StoredQueue(
    entries: [
      for (var i = 0; i < pids.length; i++)
        StoredQueueEntry(
          queueId: 'q$i',
          pid: pids[i],
          sourceRank: sourceRanks?[i] ?? i,
        ),
    ],
    currentIndex: currentIndex,
    shuffled: shuffled,
    repeat: repeat,
    sourceKind: 'album',
    sourceLabel: 'Kind of Blue',
    sourcePid: 'al-1',
    nextQueueId: pids.length,
    updatedAt: DateTime.utc(2026, 7, 25, 12),
  );
}

/// The queue as the store round-trips it, with every field set to
/// something distinguishable from its default.
StoredQueue _fullQueue() => StoredQueue(
  entries: const [StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0)],
  currentIndex: 0,
  shuffled: true,
  repeat: 'all',
  sourceKind: 'genre',
  sourceLabel: 'Ambient',
  sourcePid: 'ge-1',
  sourceRolling: true,
  sourceCursor: 'eyJhZnRlciI6IjUwMCJ9',
  nextQueueId: 1,
  updatedAt: DateTime.utc(2026, 7, 28),
);

void main() {
  late MirrorDatabase db;
  late DriftQueueStore store;

  setUp(() {
    db = inMemoryMirrorDatabase();
    store = DriftQueueStore(db);
  });
  tearDown(() => db.close());

  test('nothing saved restores nothing', () async {
    expect(await store.load(), isNull);
  });

  test('a saved queue comes back whole', () async {
    await store.save(
      _queue(
        ['tr-A', 'tr-B', 'tr-C'],
        currentIndex: 1,
        shuffled: true,
        repeat: 'all',
        sourceRanks: [2, 0, 1],
      ),
    );

    final loaded = (await store.load())!;
    expect([for (final e in loaded.entries) e.pid], ['tr-A', 'tr-B', 'tr-C']);
    expect([for (final e in loaded.entries) e.sourceRank], [2, 0, 1]);
    expect([for (final e in loaded.entries) e.queueId], ['q0', 'q1', 'q2']);
    expect(loaded.currentIndex, 1);
    expect(loaded.shuffled, isTrue);
    expect(loaded.repeat, 'all');
    expect(loaded.sourceKind, 'album');
    expect(loaded.sourceLabel, 'Kind of Blue');
    expect(loaded.sourcePid, 'al-1');
    expect(loaded.sourceRolling, isFalse);
    expect(loaded.nextQueueId, 3);
    // Drift keeps datetimes as unix seconds and hands them back in the
    // local zone: the instant survives, the zone flag does not.
    expect(
      loaded.updatedAt.isAtSameMomentAs(DateTime.utc(2026, 7, 25, 12)),
      isTrue,
    );
  });

  test('play order is the row order, whatever the ids say', () async {
    await store.save(
      StoredQueue(
        entries: const [
          StoredQueueEntry(queueId: 'q7', pid: 'tr-C', sourceRank: 2),
          StoredQueueEntry(queueId: 'q2', pid: 'tr-A', sourceRank: 0),
        ],
        currentIndex: 0,
        shuffled: true,
        repeat: 'off',
        sourceKind: 'playlist',
        sourceLabel: 'Roadtrip',
        nextQueueId: 8,
        updatedAt: DateTime.utc(2026, 7, 25),
      ),
    );

    final loaded = (await store.load())!;
    expect([for (final e in loaded.entries) e.pid], ['tr-C', 'tr-A']);
  });

  test('a shorter queue leaves nothing of the longer one behind', () async {
    await store.save(_queue(['tr-A', 'tr-B', 'tr-C', 'tr-D'], currentIndex: 3));
    await store.save(_queue(['tr-E']));

    final loaded = (await store.load())!;
    expect([for (final e in loaded.entries) e.pid], ['tr-E']);
    expect(loaded.currentIndex, 0);
  });

  test('an index past the end lands on the last entry', () async {
    await store.save(_queue(['tr-A', 'tr-B'], currentIndex: 1));
    await (db.delete(
      db.queueEntries,
    )..where((t) => t.queueId.equals('q1'))).go();

    expect((await store.load())!.currentIndex, 0);
  });

  test('entries with no meta row restore nothing', () async {
    await store.save(_queue(['tr-A']));
    await db.delete(db.queueMeta).go();

    expect(await store.load(), isNull);
  });

  test('clearing forgets both halves', () async {
    await store.save(_queue(['tr-A', 'tr-B']));
    await store.clear();

    expect(await store.load(), isNull);
    expect(await db.select(db.queueEntries).get(), isEmpty);
    expect(await db.select(db.queueMeta).get(), isEmpty);
  });

  test('every field of the meta row survives a save and a load', () async {
    // A save replaces the whole row, so a field the companion omits is
    // not left alone — it is reset to its column default on every write.
    // That failure is silent, which is why this asserts the whole record
    // rather than the fields a given change happened to touch.
    await store.save(_fullQueue());
    final restored = (await store.load())!;

    expect(restored.shuffled, isTrue);
    expect(restored.repeat, 'all');
    expect(restored.sourceKind, 'genre');
    expect(restored.sourceLabel, 'Ambient');
    expect(restored.sourcePid, 'ge-1');
    expect(restored.sourceRolling, isTrue);
    expect(restored.sourceCursor, 'eyJhZnRlciI6IjUwMCJ9');
    expect(restored.nextQueueId, 1);
    // Drift stores a DateTime as a Unix timestamp and hands it back in
    // local time, so the instant is what round-trips, not the zone.
    expect(restored.updatedAt.toUtc(), DateTime.utc(2026, 7, 28));
  });
}
