import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [SyncApi] for `FakeRepository`.
mixin FakeSync on FakeRepositoryState implements SyncApi {
  /// Catalog pages to hand back in order, ahead of the default one built
  /// from [libraryItems]. Lets a test script a tombstone.
  final catalogPages = <CatalogSyncPage>[];

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    if (catalogPages.isNotEmpty) return catalogPages.removeAt(0);
    return CatalogSyncPage(
      entries: [
        for (final item in libraryItems)
          CatalogSyncEntry(op: 'upsert', pid: item.pid, item: item),
      ],
      nextSince: 'fake-catalog-cursor',
    );
  }

  /// The pids [syncCatalogRemoved] names, of those it is asked about.
  final removedForGood = <String>{};

  @override
  Future<List<String>> syncCatalogRemoved(List<String> pids) async => [
    for (final pid in pids)
      if (removedForGood.contains(pid)) pid,
  ];

  /// Pages the server-state stream answers with, in order; an empty page
  /// once they run out.
  final serverPages = <ServerSyncPage>[];

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
    if (serverPages.isNotEmpty) return serverPages.removeAt(0);
    return const ServerSyncPage(nextSince: 'fake-server-cursor');
  }
}
