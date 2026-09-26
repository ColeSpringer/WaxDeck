import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

void main() {
  test(
    'forgets everything the server gave, and keeps the device settings',
    () async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      final now = DateTime.utc(2026, 9, 26);
      await db.batch((b) {
        b
          ..insert(
            db.mirrorItems,
            MirrorItemsCompanion.insert(
              pid: 'tr-A',
              ulid: 'A',
              mediaType: 'music',
              title: 'Alpha',
              durationMs: 1000,
              sortKey: 'alpha',
            ),
          )
          ..insert(
            db.mirrorPlayStates,
            MirrorPlayStatesCompanion.insert(pid: 'tr-A'),
          )
          ..insert(
            db.syncCursors,
            const SyncCursorsCompanion(catalogSince: Value('c1')),
          )
          ..insert(
            db.outboxMutations,
            OutboxMutationsCompanion.insert(
              kind: 'position',
              pid: 'tr-A',
              recordedAt: now,
            ),
          )
          ..insert(
            db.outboxListens,
            OutboxListensCompanion.insert(
              sessionId: 's1',
              pid: 'tr-A',
              startedAt: now,
              msPlayed: 1,
            ),
          )
          ..insert(
            db.downloadRecords,
            DownloadRecordsCompanion.insert(
              pid: 'tr-A',
              fileIndex: 0,
              essenceHash: 'e',
              etag: '1',
              fileName: 'e.flac',
              localPath: '/tmp/e.flac',
              sizeBytes: 1,
              state: 'complete',
            ),
          )
          ..insert(
            db.queueEntries,
            QueueEntriesCompanion.insert(
              queueId: 'q1',
              pid: 'tr-A',
              position: 0,
              sourceRank: 0,
            ),
          )
          ..insert(db.queueMeta, QueueMetaCompanion.insert(updatedAt: now))
          ..insert(
            db.artworkPins,
            ArtworkPinsCompanion.insert(
              pid: 'tr-A',
              sizePx: 256,
              artUrl: '/art',
              etag: '1',
              localPath: '/tmp/art',
              sizeBytes: 1,
              pinnedAt: now,
            ),
          )
          ..insert(
            db.clientSettings,
            ClientSettingsCompanion.insert(key: 'wifi', value: 'true'),
          );
      });

      await db.wipe();

      for (final table in <TableInfo<Table, Object?>>[
        db.mirrorItems,
        db.mirrorPlayStates,
        db.syncCursors,
        db.outboxMutations,
        db.outboxListens,
        db.downloadRecords,
        db.queueEntries,
        db.queueMeta,
        db.artworkPins,
      ]) {
        expect(
          await db.select(table).get(),
          isEmpty,
          reason: table.actualTableName,
        );
      }
      expect(await db.select(db.clientSettings).get(), hasLength(1));
    },
  );
}
