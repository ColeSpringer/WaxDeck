import '../models.dart';

/// Catalog and server change feeds for offline clients.
abstract interface class SyncApi {
  /// `GET /sync/catalog`: snapshot (no [since]) or changed-since delta
  /// of the catalog, feeding the client mirror. A `sync-reset` error
  /// means drop the mirror and snapshot again.
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  });

  /// `POST /sync/catalog/removed`: of [pids] (at most 500), those the
  /// server can never put back, which is what a `removed` tombstone says
  /// of an item and a snapshot, carrying none, cannot. The pids come back
  /// as asked; one not named may still return.
  Future<List<String>> syncCatalogRemoved(List<String> pids);

  /// `GET /sync/server`: the caller's own server-side state changes.
  /// Without [since] it mints a fresh cursor and returns no events.
  Future<ServerSyncPage> syncServer({String? since, int? limit});
}
