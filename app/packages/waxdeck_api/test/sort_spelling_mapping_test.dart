import 'package:built_collection/built_collection.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  gen.$ItemSummary summary({
    String? sortKey,
    String? artistSort,
    String? artistSortKey,
  }) => gen.$ItemSummary(
    (b) => b
      ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
      ..mediaType = gen.MediaType.music
      ..title = 'The Zebra Song'
      ..durationMs = 1000
      ..sortKey = sortKey
      ..artistSort = artistSort
      ..artistSortKey = artistSortKey,
  );

  test('a summary carries the keys its title and artist are filed under', () {
    final mapped = itemSummaryFromGen(
      summary(
        sortKey: 'zebra song',
        artistSort: 'Stripes, The',
        artistSortKey: 'stripes, the',
      ),
    );
    expect(mapped.sortKey, 'zebra song');
    expect(mapped.artistSort, 'Stripes, The');
    expect(mapped.artistSortKey, 'stripes, the');
  });

  test('a summary without them leaves all three null', () {
    final mapped = itemSummaryFromGen(summary());
    expect(mapped.sortKey, isNull);
    expect(mapped.artistSort, isNull);
    expect(mapped.artistSortKey, isNull);
  });

  test('a detail carries the totals a file states', () {
    final detail = itemDetailFromGen(
      gen.Item(
        (b) => b
          ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
          ..mediaType = gen.MediaType.music
          ..title = 'The Zebra Song'
          ..durationMs = 1000
          ..sortKey = 'zebra song'
          ..artistSortKey = 'stripes, the'
          ..trackNumber = 3
          ..trackTotal = 12
          ..discNumber = 1
          ..discTotal = 2
          ..partTotal = 5,
      ),
    );
    expect(detail.sortKey, 'zebra song');
    expect(detail.artistSortKey, 'stripes, the');
    expect(detail.trackTotal, 12);
    expect(detail.discTotal, 2);
    expect(detail.partTotal, 5);
  });

  test('a detail states no total it was not given', () {
    final detail = itemDetailFromGen(
      gen.Item(
        (b) => b
          ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
          ..mediaType = gen.MediaType.music
          ..title = 'Loose'
          ..durationMs = 1000,
      ),
    );
    expect(detail.trackTotal, isNull);
    expect(detail.discTotal, isNull);
    expect(detail.partTotal, isNull);
  });

  test('an episode carries the key its title is filed under', () {
    final episode = episodeSummaryFromGen(
      gen.$EpisodeSummary(
        (b) => b
          ..pid = 'ep-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
          ..mediaType = gen.MediaType.podcast
          ..title = 'The Drift 001'
          ..durationMs = 1000
          ..sortKey = 'drift 0000000001'
          ..showPid = 'pc-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
          ..publishedAt = DateTime.utc(2026)
          ..downloaded = false,
      ),
    );
    expect(episode.sortKey, 'drift 0000000001');
  });

  test('a search hit is exact only when the server says so', () {
    gen.SearchHit hit({bool? exact}) => gen.SearchHit(
      (h) => h
        ..pid = 'ar-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
        ..kind = 'artist'
        ..title = 'Moon'
        ..exact = exact,
    );
    expect(searchHitFromGen(hit(exact: true)).exact, isTrue);
    expect(searchHitFromGen(hit()).exact, isFalse);
  });

  test('a plan entry carries the sidecars that go with its files', () {
    gen.DeletePlanEntry entry({List<String>? sidecars}) => gen.DeletePlanEntry(
      (e) => e
        ..pid = 'tr-1'
        ..files = 1
        ..bytes = 10
        ..sidecars = sidecars == null ? null : ListBuilder<String>(sidecars),
    );
    final result = deleteItemsResultFromGen(
      gen.DeleteItemsResult(
        (b) => b
          ..applied = false
          ..mode = 'trash'
          ..entries = ListBuilder<gen.DeletePlanEntry>([
            entry(sidecars: ['Shelf/one.lrc', 'Shelf/one.jpg']),
            entry(),
          ]),
      ),
    );
    expect(result.entries.first.sidecars, ['Shelf/one.lrc', 'Shelf/one.jpg']);
    expect(result.entries.last.sidecars, isEmpty);
  });

  group('what a list orders an item by', () {
    ItemSummary item({
      String title = 'The Zebra Song',
      String? artist,
      String? sortKey,
      String? artistSort,
      String? artistSortKey,
    }) => ItemSummary(
      pid: 'tr-1',
      mediaType: MediaType.music,
      title: title,
      artist: artist,
      sortKey: sortKey,
      artistSort: artistSort,
      artistSortKey: artistSortKey,
      durationMs: 1000,
    );

    test('is the catalog\'s key, and the lowercase title without one', () {
      expect(item(sortKey: 'zebra song').titleOrderKey, 'zebra song');
      expect(item().titleOrderKey, 'the zebra song');
    });

    test(
      'for an artist is the catalog\'s key, then the spelling, then the name',
      () {
        expect(
          item(
            artist: 'The Stripes',
            artistSort: 'Stripes, The',
            artistSortKey: 'stripes, the',
          ).artistOrderKey,
          'stripes, the',
        );
        expect(
          item(
            artist: 'The Stripes',
            artistSort: 'Stripes, The',
          ).artistOrderKey,
          'stripes, the',
        );
        expect(item(artist: 'The Stripes').artistOrderKey, 'the stripes');
        expect(item().artistOrderKey, isEmpty);
      },
    );

    test('an empty key is no key', () {
      expect(item(sortKey: '').titleOrderKey, isNotEmpty);
      expect(item(artist: 'Zed', artistSortKey: '').artistOrderKey, 'zed');
    });
  });
}
