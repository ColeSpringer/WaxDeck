import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/books/books_controller.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

ItemSummary _book(
  String title, {
  String? pid,
  String? sortKey,
  String? author,
  String? authorSort,
  String? authorKey,
}) => ItemSummary(
  pid: pid ?? 'bk-$title',
  mediaType: MediaType.audiobook,
  title: title,
  artist: author,
  sortKey: sortKey,
  artistSort: authorSort,
  artistSortKey: authorKey,
  durationMs: 3600000,
);

List<String> _arranged(List<ItemSummary> books, BookSort sort) => [
  for (final book in arrangeBooks(
    books,
    BookView(sort: sort),
    PlayProgressView.empty,
  ))
    book.pid,
];

List<String> _titles(List<ItemSummary> books, BookSort sort) => [
  for (final book in arrangeBooks(
    books,
    BookView(sort: sort),
    PlayProgressView.empty,
  ))
    book.title,
];

void main() {
  group('books sorted on the client', () {
    test('by title keep the order the catalog files titles in', () {
      final books = <ItemSummary>[
        _book('The Hobbit', sortKey: 'hobbit'),
        _book('Book 10', sortKey: 'book 0000000010'),
        _book('A Wizard of Earthsea', sortKey: 'wizard of earthsea'),
        _book('Dune', sortKey: 'dune'),
        _book('Book 2', sortKey: 'book 0000000002'),
      ];
      // A lowercase title would put the wizard first, the hobbit last and
      // book 10 before book 2.
      expect(_titles(books, BookSort.title), [
        'Book 2',
        'Book 10',
        'Dune',
        'The Hobbit',
        'A Wizard of Earthsea',
      ]);
    });

    test('by title fall back to the lowercase title without a key', () {
      final books = <ItemSummary>[
        _book('Zeta'),
        _book('alpha'),
        _book('Mid', sortKey: 'mid'),
      ];
      expect(_titles(books, BookSort.title), ['alpha', 'Mid', 'Zeta']);
    });

    test('by title put books of one key in pid order, as they arrive', () {
      // Past thirty-two elements Dart's sort is not stable, and the catalog
      // folds "The Hobbit" and "Hobbit" to one key, so equal keys are
      // ordinary: they have to come out the same however the pages landed.
      final books = <ItemSummary>[
        for (var i = 0; i < 40; i++)
          _book(
            'Hobbit $i',
            pid: 'bk-${i.toString().padLeft(2, '0')}',
            sortKey: 'hobbit',
          ),
      ];
      final ascending = [for (final book in books) book.pid];
      expect(_arranged(books, BookSort.title), ascending);
      expect(_arranged(books.reversed.toList(), BookSort.title), ascending);
      expect(_arranged(books, BookSort.author), ascending);
    });

    test('by author follow the key the catalog files each artist under', () {
      final books = <ItemSummary>[
        _book(
          'The Hobbit',
          sortKey: 'hobbit',
          author: 'J. R. R. Tolkien',
          authorSort: 'Tolkien, J. R. R.',
          authorKey: 'tolkien, j. r. r.',
        ),
        _book(
          'The Dispossessed',
          sortKey: 'dispossessed',
          author: 'Ursula Le Guin',
          authorSort: 'Le Guin, Ursula',
          authorKey: 'le guin, ursula',
        ),
        _book(
          'White Teeth',
          sortKey: 'white teeth',
          author: 'Zadie Smith',
          authorKey: 'zadie smith',
        ),
        _book(
          'Interview',
          sortKey: 'interview',
          author: 'Anne Rice',
          authorSort: 'Rice, Anne',
          authorKey: 'rice, anne',
        ),
        _book(
          'Beasts',
          sortKey: 'beasts',
          author: 'The Stripes',
          authorKey: 'stripes',
        ),
        _book(
          'Notre Dame',
          sortKey: 'notre dame',
          author: 'Émile Zola',
          authorKey: 'emile zola',
        ),
        _book('Anon', sortKey: 'anon'),
      ];
      // Lowercased names and spellings would read Le Guin, Rice, The Stripes,
      // Tolkien, Zadie Smith, and Émile Zola last of all; the keys fold the
      // accent and the article, and an unattributed book still goes last.
      expect(_titles(books, BookSort.author), [
        'Notre Dame',
        'The Dispossessed',
        'Interview',
        'Beasts',
        'The Hobbit',
        'White Teeth',
        'Anon',
      ]);
    });

    test(
      'by author fall back to the spelling, then the name, without a key',
      () {
        final books = <ItemSummary>[
          _book(
            'The Hobbit',
            author: 'J. R. R. Tolkien',
            authorSort: 'Tolkien, J. R. R.',
          ),
          _book('Zed Book', author: 'Zed'),
          _book('Anon'),
        ];
        expect(_titles(books, BookSort.author), [
          'The Hobbit',
          'Zed Book',
          'Anon',
        ]);
      },
    );

    test('the author chips break a tie of counts by the artist key', () {
      final authors = bookAuthors(<ItemSummary>[
        _book('One', author: 'Terry Pratchett', authorKey: 'terry pratchett'),
        _book('Two', author: 'Terry Pratchett', authorKey: 'terry pratchett'),
        _book(
          'Three',
          author: 'Ursula Le Guin',
          authorSort: 'Le Guin, Ursula',
          authorKey: 'le guin, ursula',
        ),
        _book(
          'Four',
          author: 'Ursula Le Guin',
          authorSort: 'Le Guin, Ursula',
          authorKey: 'le guin, ursula',
        ),
        _book('Five', author: 'Zed', authorKey: 'zed'),
      ]);
      // By name alone Pratchett would lead Le Guin; by key it is the other
      // way about, and the author with the one book is last either way.
      expect(authors.map((a) => a.name), [
        'Ursula Le Guin',
        'Terry Pratchett',
        'Zed',
      ]);
      expect(authors.map((a) => a.count), [2, 2, 1]);
    });

    test('the author chips fall back to the name, and never swap on a tie', () {
      final books = <ItemSummary>[
        _book('One', author: 'ann'),
        _book('Two', author: 'Ann'),
        _book('Three', author: 'Bob'),
        _book('Four', author: 'Bob'),
      ];
      final names = bookAuthors(books).map((a) => a.name).toList();
      expect(names, ['Bob', 'Ann', 'ann']);
      expect(bookAuthors(books.reversed.toList()).map((a) => a.name), names);
    });
  });

  group('downloads sorted on the client', () {
    DownloadEntry entry(String pid, String title, {String? sortKey}) =>
        DownloadEntry(
          record: DownloadedItem(
            pid: pid,
            sizeBytes: 1,
            files: 1,
            complete: true,
          ),
          item: ItemSummary(
            pid: pid,
            mediaType: MediaType.music,
            title: title,
            sortKey: sortKey,
            durationMs: 1000,
          ),
        );

    test('list a medium in the order the catalog files its titles', () {
      final state = DownloadsState(
        entries: <DownloadEntry>[
          entry('tr-1', 'The Zebra Song', sortKey: 'zebra song'),
          entry('tr-2', 'Track 10', sortKey: 'track 0000000010'),
          entry('tr-3', 'apple tune', sortKey: 'apple tune'),
          entry('tr-4', 'Track 2', sortKey: 'track 0000000002'),
        ],
      );
      expect(state.groups.single.entries.map((e) => e.title), [
        'apple tune',
        'Track 2',
        'Track 10',
        'The Zebra Song',
      ]);
    });

    test('fall back to the lowercase title for a row with no key', () {
      final state = DownloadsState(
        entries: <DownloadEntry>[
          entry('tr-1', 'Zeta'),
          entry('tr-2', 'alpha'),
          entry('tr-3', 'Mid', sortKey: 'mid'),
        ],
      );
      expect(state.groups.single.entries.map((e) => e.title), [
        'alpha',
        'Mid',
        'Zeta',
      ]);
    });

    test('put rows of one key in pid order, as they were read', () {
      final entries = <DownloadEntry>[
        for (var i = 0; i < 40; i++)
          entry(
            'tr-${i.toString().padLeft(2, '0')}',
            'Hobbit $i',
            sortKey: 'hobbit',
          ),
      ];
      final ascending = [for (final e in entries) e.pid];
      List<String> pids(List<DownloadEntry> read) => [
        for (final e in DownloadsState(entries: read).groups.single.entries)
          e.pid,
      ];
      expect(pids(entries), ascending);
      expect(pids(entries.reversed.toList()), ascending);
    });
  });
}
