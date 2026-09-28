import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/player/download_action.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

const _book = 'bk-01JZX5N8QW3F4V9T2B7KD3M9R6';
const _me = 'us-1';

void main() {
  testWidgets('a book fetched for offline brings its marks along', (
    tester,
  ) async {
    // Made on another device before this one ever opened the book, they
    // would otherwise reach it only through a player opened online.
    final db = inMemoryMirrorDatabase();
    final repo = FakeRepository()
      ..bookmarks[_book] = [
        Bookmark(
          id: 'bm-01JZX5N8QW3F4V9T2B7KD3M9R6',
          positionMs: 60000,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ];
    final sync = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    )..account = _me;
    final downloads = FakeDownloads();
    addTearDown(() async {
      sync.dispose();
      downloads.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          syncEngineProvider.overrideWithValue(sync),
          downloadManagerProvider.overrideWithValue(downloads),
          artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
        ],
        child: localizedHost(
          const Scaffold(
            body: DownloadAction(
              pid: _book,
              label: 'Download',
              semanticsId: SemanticsIds.bookDownload,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.bookDownload));
    await tester.pump();
    downloads.emit(
      const DownloadProgress(pid: _book, fraction: 1, complete: true),
    );
    await tester.pumpAndSettle();

    expect(downloads.downloaded, [_book]);
    expect(
      [for (final m in await sync.localBookmarks(_book, owner: _me)) m.mark.id],
      ['bm-01JZX5N8QW3F4V9T2B7KD3M9R6'],
    );
  });
}
