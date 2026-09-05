import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/books/series_index_screen.dart';
import 'package:waxdeck/src/books/series_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _series = 'sr-01JZX5N8QW3F4V9T2B7KDSERIE1';
const _other = 'sr-01JZX5N8QW3F4V9T2B7KDSERIE2';

ItemSummary _book(String pid, String title) => ItemSummary(
  pid: pid,
  mediaType: MediaType.audiobook,
  title: title,
  artist: 'Ada Author',
  durationMs: 3600000,
);

FakeRepository _repo() {
  final repo = FakeRepository(items: <ItemSummary>[]);
  repo.bookSeries.addAll(<BookSeries>[
    const BookSeries(pid: _series, name: 'Tidewater', bookCount: 3),
    const BookSeries(pid: _other, name: 'Saltmarsh', bookCount: 1),
  ]);
  repo.bookSeriesDetails[_series] = BookSeriesDetail(
    pid: _series,
    name: 'Tidewater',
    // Deliberately larger than the rows: the header prefers the
    // catalog's count where the server answered one, and the two being
    // equal would make that assertion say nothing.
    bookCount: 4,
    totalDurationMs: 10800000,
    books: <BookSeriesEntry>[
      BookSeriesEntry(
        sequence: '1',
        book: _book('bk-01JZX5N8QW3F4V9T2B7KDBOOK01', 'The Estuary'),
      ),
      BookSeriesEntry(
        sequence: '1.5',
        book: _book('bk-01JZX5N8QW3F4V9T2B7KDBOOK02', 'Slack Water'),
      ),
      // No number in the tags, which is a shape the server answers.
      BookSeriesEntry(book: _book('bk-01JZX5N8QW3F4V9T2B7KDBOOK03', 'The Bar')),
    ],
  );
  return repo;
}

Widget _host(FakeRepository repo, Widget screen) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(FakeEngine()),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(screen),
);

Finder _byId(String id) => find.bySemanticsIdentifier(id);

/// Each row's sequence and title, in the order the list draws them,
/// read off the index-keyed handles rather than off the text tree: the
/// row draws its sequence in the leading slot and its title after it.
List<String> _rowLines(WidgetTester tester) {
  final out = <String>[];
  for (var index = 0; ; index++) {
    final row = _byId(SemanticsIds.bookSeriesRow(index));
    if (row.evaluate().isEmpty) return out;
    final texts = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    out.add('${texts[0]} ${texts[1]}');
  }
}

void main() {
  testWidgets('the series lists its books in the catalog order', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_repo(), const BookSeriesScreen(pid: _series)),
    );
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.bookSeriesScreen(_series)), findsOneWidget);
    // By row index, which is the handle the screen mints so order can
    // be asserted at all: three titles being present says nothing about
    // the order the catalog put them in.
    expect(_rowLines(tester), <String>[
      '1 The Estuary',
      '1.5 Slack Water',
      '- The Bar',
    ]);

    // The number the tags spell rather than the row's position, and a
    // dash where the tags name none.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('the header counts the catalog where it was told, the rows '
      'where it was not', (tester) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo, const BookSeriesScreen(pid: _series)));
    await tester.pumpAndSettle();
    // Answered, so the catalog's number stands even though it is larger
    // than the list: the account can see the whole series.
    expect(find.textContaining('4 books'), findsOneWidget);

    // Withheld, which is what a restricted account reads: the header
    // falls back to what it can actually open rather than printing the
    // zero the server sent.
    final restricted = _repo();
    restricted.bookSeriesDetails[_series] = BookSeriesDetail(
      pid: _series,
      name: 'Tidewater',
      books: restricted.bookSeriesDetails[_series]!.books,
    );
    await tester.pumpWidget(
      _host(restricted, const BookSeriesScreen(pid: _series)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('3 books'), findsOneWidget);
  });

  testWidgets('a series with nothing this account can open says so', (
    tester,
  ) async {
    final repo = _repo();
    repo.bookSeriesDetails[_series] = const BookSeriesDetail(
      pid: _series,
      name: 'Tidewater',
    );
    await tester.pumpWidget(_host(repo, const BookSeriesScreen(pid: _series)));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to show here'), findsOneWidget);
  });

  testWidgets('a series nobody has says so rather than sitting blank', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_repo(), const BookSeriesScreen(pid: 'sr-nothing-here')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not open this series'), findsOneWidget);
  });

  testWidgets('the index draws a card per series and opens one', (
    tester,
  ) async {
    final repo = _repo();
    await tester.pumpWidget(_host(repo, const BookSeriesIndexScreen()));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.bookSeriesIndex), findsOneWidget);
    expect(_byId(SemanticsIds.bookSeriesCard(_series)), findsOneWidget);
    expect(_byId(SemanticsIds.bookSeriesCard(_other)), findsOneWidget);

    await tester.tap(_byId(SemanticsIds.bookSeriesCard(_series)));
    await tester.pumpAndSettle();

    // `go`, so the series is the location rather than a push over the
    // index: the screen it lands on is the one the route declares.
    expect(_byId(SemanticsIds.bookSeriesScreen(_series)), findsOneWidget);
    expect(find.text('The Estuary'), findsOneWidget);
  });

  testWidgets('an empty index says where a series comes from', (tester) async {
    final repo = FakeRepository(items: <ItemSummary>[]);
    await tester.pumpWidget(_host(repo, const BookSeriesIndexScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No series yet'), findsOneWidget);
  });

  test('the index and one series are both locations', () {
    expect(WaxRoute.bookSeriesIndex, '/books/series');
    expect(WaxRoute.bookSeries(_series), '/books/series/$_series');
  });
}
