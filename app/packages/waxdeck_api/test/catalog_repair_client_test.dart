import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

/// Answers the catalog check and the repair, recording what was asked.
class _CatalogAdapter implements HttpClientAdapter {
  final requests = <String>[];
  final options = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.uri.path}');
    this.options.add(options);
    final repair = options.uri.path.endsWith('/admin/catalog/repair');
    return ResponseBody.fromString(
      jsonEncode(
        repair
            ? {
                'id': 'tk-1',
                'type': 'catalog-repair',
                'state': 'queued',
                'createdAt': '2026-10-01T09:00:00Z',
              }
            : {
                'itemsMissingFromSearch': 1,
                'orphanSearchRows': 2,
                'artistRollupDrift': 3,
                'genreRollupDrift': 4,
                'releaseGroupRollupDrift': 5,
                'sortKeyDrift': 6,
                'bookDurationDrift': 7,
                'bookIsbnKeyDrift': 8,
                'albumYearDrift': 9,
                'releaseYearDrift': 10,
                'playlistPositionDrift': 11,
                'orphanArtSources': 12,
                'orphanThumbnails': 13,
                'orphanTagProvenance': 14,
                'strandedTagRows': 15,
                'consistent': false,
                'reclaimable': true,
              },
      ),
      repair ? 202 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('the check reads every count into its own field', () async {
    final adapter = _CatalogAdapter();
    final client = clientOn(adapter);
    final c = await client.getCatalogConsistency();
    expect(adapter.requests, ['GET /api/v1/admin/catalog/consistency']);
    expect(
      [
        c.itemsMissingFromSearch,
        c.orphanSearchRows,
        c.artistRollupDrift,
        c.genreRollupDrift,
        c.releaseGroupRollupDrift,
        c.sortKeyDrift,
        c.bookDurationDrift,
        c.bookIsbnKeyDrift,
        c.albumYearDrift,
        c.releaseYearDrift,
        c.playlistPositionDrift,
        c.orphanArtSources,
        c.orphanThumbnails,
        c.orphanTagProvenance,
        c.strandedTagRows,
      ],
      [for (var i = 1; i <= 15; i++) i],
    );
    expect(c.consistent, isFalse);
    expect(c.reclaimable, isTrue);
  });

  test('the repair posts and answers its task', () async {
    final adapter = _CatalogAdapter();
    final client = clientOn(adapter);
    final task = await client.repairCatalog();
    expect(adapter.requests, ['POST /api/v1/admin/catalog/repair']);
    expect(task.id, 'tk-1');
    expect(task.type, 'catalog-repair');
    expect(task.state, 'queued');
  });

  test(
    'the check is given the long-operation budget, the repair is not',
    () async {
      // The check counts the whole catalog before it answers, so the
      // ordinary 30 s would cut it off on a large one; the repair answers
      // once its task is queued.
      final adapter = _CatalogAdapter();
      final client = clientOn(adapter);
      await client.getCatalogConsistency();
      await client.repairCatalog();
      expect(adapter.options.first.receiveTimeout, const Duration(minutes: 30));
      expect(
        adapter.options.last.receiveTimeout,
        isNot(const Duration(minutes: 30)),
      );
    },
  );
}
