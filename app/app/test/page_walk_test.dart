import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/library/page_walk.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

ItemSummary _item(int n) => ItemSummary(
  pid: 'tr-$n',
  mediaType: MediaType.music,
  title: 'Track $n',
  durationMs: 1000,
);

/// A listing scripted as pages, each handing out the cursor of the one
/// after it, and the cursors it was asked for, in order.
({Future<ItemPage> Function(String?) fetch, List<String?> asked}) _listing(
  List<List<ItemSummary>> pages, {
  int? failAt,
}) {
  final asked = <String?>[];
  Future<ItemPage> fetch(String? cursor) async {
    asked.add(cursor);
    final at = cursor == null ? 0 : int.parse(cursor.substring(1));
    if (at == failAt) {
      throw const WaxDeckApiException(
        code: 'invalid-request',
        message: 'cursor was issued for another scope',
        statusCode: 400,
      );
    }
    return ItemPage(
      items: pages[at],
      nextCursor: at + 1 < pages.length ? 'c${at + 1}' : null,
    );
  }

  return (fetch: fetch, asked: asked);
}

/// A listing page may come back short or empty and still carry a cursor:
/// the server filters some rows after the cut. Only a page without a
/// cursor ends the list.
void main() {
  test(
    'reads past an empty page and stops once it holds what it wants',
    () async {
      final listing = _listing([
        [],
        [_item(1), _item(2)],
        [_item(3)],
      ]);

      final walk = await walkPages(listing.fetch, want: 2);

      expect(walk.items.map((i) => i.pid), ['tr-1', 'tr-2']);
      expect(walk.exhausted, isFalse, reason: 'a page is left unread');
      expect(listing.asked, [null, 'c1']);
    },
  );

  test('stops at the end, which proves the listing exhausted', () async {
    final listing = _listing([[], []]);

    final walk = await walkPages(listing.fetch);

    expect(walk.items, isEmpty);
    expect(walk.exhausted, isTrue);
    expect(walk.nextCursor, isNull);
  });

  test('stops at its page budget without claiming the end', () async {
    final listing = _listing([for (var i = 0; i < 10; i++) <ItemSummary>[]]);

    final walk = await walkPages(listing.fetch, maxPages: 3);

    expect(walk.items, isEmpty);
    expect(walk.exhausted, isFalse, reason: 'seven pages were never read');
    expect(walk.nextCursor, 'c3');
    expect(listing.asked, hasLength(3));
  });

  test('a listing that draws its rows reads on with no budget', () async {
    // A budget that ran out would leave the list short over rows it
    // never reached.
    final listing = _listing([
      for (var i = 0; i < 10; i++) <ItemSummary>[],
      [_item(1)],
    ]);

    final walk = await readPages(listing.fetch, want: 1);

    expect(walk.items.map((i) => i.pid), ['tr-1']);
    expect(walk.exhausted, isTrue);
    expect(listing.asked, hasLength(11));
  });

  test(
    'only a walk read to its end with nothing in it proves emptiness',
    () async {
      expect((await walkPages(_listing([[], []]).fetch)).provedEmpty, isTrue);
      expect(
        (await walkPages(
          _listing([[], [], []]).fetch,
          maxPages: 2,
        )).provedEmpty,
        isFalse,
        reason: 'a page is left unread',
      );
      expect(
        (await walkPages(
          _listing([
            [_item(1)],
          ]).fetch,
        )).provedEmpty,
        isFalse,
      );
    },
  );

  test('a walk asked to stop reads no further page', () async {
    // The reader is gone, the listing it read for with it.
    final listing = _listing([for (var i = 0; i < 5; i++) <ItemSummary>[]]);
    var gone = false;

    final walk = readPages(listing.fetch, want: 1, stop: () => gone);
    gone = true;

    expect((await walk).exhausted, isFalse);
    expect(listing.asked, [null]);
  });

  test(
    'a walk that keeps what it read ends with it when a page fails',
    () async {
      final listing = _listing([
        [_item(1)],
        [_item(2)],
        [_item(3)],
      ], failAt: 1);

      final walk = await walkPages(listing.fetch, want: 3, keepOnFailure: true);

      expect(walk.items.map((i) => i.pid), ['tr-1']);
      expect(walk.nextCursor, 'c1', reason: 'a later walk reads on from it');
    },
  );

  test('one that has read nothing yet throws its failure all the same', () {
    final listing = _listing([[], [], []], failAt: 1);

    expect(
      walkPages(listing.fetch, keepOnFailure: true),
      throwsA(isA<WaxDeckApiException>()),
    );
  });

  test('a probe asks for one row, and pages wide past one that showed '
      'nothing', () async {
    final limits = <int>[];
    final pages = [
      <ItemSummary>[],
      <ItemSummary>[],
      [_item(1)],
    ];
    final walk = await probePages((cursor, limit) async {
      limits.add(limit);
      final at = cursor == null ? 0 : int.parse(cursor.substring(1));
      return ItemPage(
        items: pages[at],
        nextCursor: at + 1 < pages.length ? 'c${at + 1}' : null,
      );
    });

    expect(walk.items.map((i) => i.pid), ['tr-1']);
    expect(limits, [1, kProbePageSize, kProbePageSize]);
  });

  test('a probe stops at its budget', () async {
    var asked = 0;
    final walk = await probePages((cursor, limit) async {
      asked++;
      return const ItemPage(items: <ItemSummary>[], nextCursor: 'more');
    });

    expect(walk.provedEmpty, isFalse);
    expect(asked, kProbePageBudget);
  });

  test('forwards each cursor in the order the pages handed them out', () async {
    final listing = _listing([
      [],
      [],
      [_item(1)],
    ]);

    await walkPages(listing.fetch);

    expect(listing.asked, [null, 'c1', 'c2']);
  });

  test('a refusal partway reaches the caller', () async {
    final listing = _listing([[], [], []], failAt: 1);

    await expectLater(
      walkPages(listing.fetch),
      throwsA(isA<WaxDeckApiException>()),
    );
    expect(listing.asked, [null, 'c1']);
  });
}
