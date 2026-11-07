import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/player/play_progress.dart';
import 'package:waxdeck/src/podcasts/podcast_shelves.dart';
import 'package:waxdeck/src/presenters/media_tiles.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

final AppLocalizations _l10n = AppLocalizationsEn();
final WaxLocalizations _wax = lookupWaxLocalizations(const Locale('en'));

PlayProgress _progress(int positionMs, {bool finished = false}) =>
    PlayProgress(positionMs: positionMs, played: finished, finished: finished);

Playlist _playlist({
  String kind = 'static',
  String visibility = 'private',
  bool isOwner = true,
  String ownerName = 'Frodo',
  int? itemCount,
  String? artUrl,
}) => Playlist(
  pid: 'pl-1',
  name: 'Road songs',
  kind: kind,
  visibility: visibility,
  ownerName: ownerName,
  isOwner: isOwner,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 2),
  itemCount: itemCount,
  artUrl: artUrl,
);

DownloadEntry _download(
  ItemSummary? item, {
  PlayState? progress,
  int sizeBytes = 2048,
}) => DownloadEntry(
  record: DownloadedItem(
    pid: 'tr-held',
    sizeBytes: sizeBytes,
    files: 1,
    complete: true,
  ),
  item: item,
  progress: progress,
);

void main() {
  late FakeArtworkStore store;
  late FakeRepository repository;

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    store = FakeArtworkStore();
    repository = FakeRepository();
  });

  /// The URL the tile's artwork asks the store for at 64 px, or null for a
  /// tile that draws the monogram.
  String? artworkUrl(MediaTileData tile) {
    final artwork = tile.artwork;
    if (artwork == null) return null;
    store.requested.clear();
    artwork(64);
    return store.requested.single;
  }

  group('tracks', () {
    test('trackRowTile hides the artist the album header names', () {
      final same = trackRowTile(
        testItem('tr-1', artist: 'The Bree Trio', durationMs: 214000),
        albumArtist: 'The Bree Trio',
        semanticsId: 'row-0',
      );
      final other = trackRowTile(
        testItem('tr-2', artist: 'A Guest'),
        albumArtist: 'The Bree Trio',
        semanticsId: 'row-1',
      );

      expect(same.title, 'Prancing Pony Blues');
      expect(same.subtitle, isNull);
      expect(same.trailingText, '3:34');
      expect(same.semanticsId, 'row-0');
      expect(other.subtitle, 'A Guest');
    });

    test('trackRowTile passes the play-count readout through', () {
      final tile = trackRowTile(
        testItem('tr-1'),
        albumArtist: null,
        trailingDetail: '4',
        trailingDetailSpoken: '4 plays',
        trailingDetailSemanticsId: 'plays-0',
        semanticsId: 'row-0',
      );

      expect(tile.trailingDetail, '4');
      expect(tile.trailingDetailSpoken, '4 plays');
      expect(tile.trailingDetailSemanticsId, 'plays-0');
      expect(artworkUrl(tile), isNull);
      expect(tile.domain, WaxDomain.music);
    });

    test('topTrackRowTile names the album under the title', () {
      final tile = topTrackRowTile(
        ItemSummary(
          pid: 'tr-1',
          mediaType: MediaType.music,
          title: 'Song',
          durationMs: 5000,
          artist: 'Band',
          album: 'Record',
          artUrl: '/art/2',
        ),
        store: store,
        semanticsId: 'index-0',
      );

      expect(tile.subtitle, 'Record');
      expect(tile.trailingText, '0:05');
      expect(artworkUrl(tile), '/art/2');
      expect(tile.semanticsId, 'index-0');
    });

    test('queueRowTile holds a placeholder until the item resolves', () {
      final loading = queueRowTile(
        null,
        l10n: _l10n,
        store: store,
        semanticsId: 'queue-1',
      );
      final resolved = queueRowTile(
        testItem('bk-1', mediaType: MediaType.audiobook, durationMs: 0),
        l10n: _l10n,
        store: store,
        semanticsId: 'queue-2',
      );

      expect(loading.title, _l10n.commonLoadingTitle);
      expect(loading.subtitle, isNull);
      expect(loading.trailingText, isNull);
      expect(loading.domain, WaxDomain.music);
      expect(loading.shape, ArtworkShape.square);
      expect(resolved.title, 'Prancing Pony Blues');
      expect(resolved.trailingText, isNull);
      expect(resolved.domain, WaxDomain.audiobooks);
      expect(resolved.shape, ArtworkShape.portrait);
    });

    test('itemRowTile names the artist, draws the cover and the length', () {
      final tile = itemRowTile(
        ItemSummary(
          pid: 'ep-1',
          mediaType: MediaType.podcast,
          title: 'Episode',
          durationMs: 90000,
          artist: 'Show',
          artUrl: '/art/ep',
        ),
        store: store,
        semanticsId: 'mix-0',
      );

      expect(tile.title, 'Episode');
      expect(tile.subtitle, 'Show');
      expect(tile.trailingText, '1:30');
      expect(artworkUrl(tile), '/art/ep');
      expect(tile.semanticsId, 'mix-0');
    });

    test('rulePreviewTile draws no cover and hides a zero length', () {
      final known = rulePreviewTile(testItem('tr-1', durationMs: 65000));
      final unknown = rulePreviewTile(testItem('tr-2', durationMs: 0));

      expect(known.trailingText, '1:05');
      expect(known.subtitle, 'The Bree Trio');
      expect(known.artwork, isNull);
      expect(known.semanticsId, isNull);
      expect(unknown.trailingText, isNull);
    });

    test('workbenchTrackTile carries the title and the length only', () {
      final tile = workbenchTrackTile(
        testItem('tr-1', durationMs: 125000),
        semanticsId: 'wb-tr-1',
      );

      expect(tile.title, 'Prancing Pony Blues');
      expect(tile.subtitle, isNull);
      expect(tile.trailingText, '2:05');
      expect(tile.semanticsId, 'wb-tr-1');
    });

    test('workbenchAlbumTile joins the year and the track count', () {
      final named = workbenchAlbumTile(
        const AlbumDetail(
          pid: 'al-1',
          title: 'Record',
          year: 1999,
          itemCount: 12,
        ),
        trackCount: 3,
        l10n: _l10n,
        semanticsId: 'wb-album',
      );
      final loading = workbenchAlbumTile(
        null,
        trackCount: 3,
        l10n: _l10n,
        semanticsId: 'wb-album',
      );

      expect(named.title, 'Record');
      expect(named.subtitle, '1999 · ${_l10n.musicTrackCount(12)}');
      expect(loading.title, _l10n.musicAlbumTitle);
      expect(loading.subtitle, _l10n.musicTrackCount(3));
    });
  });

  group('every row that draws an item', () {
    final rows = <String, MediaTileData Function(ItemSummary)>{
      'trackRowTile': (item) =>
          trackRowTile(item, albumArtist: null, semanticsId: 'a'),
      'topTrackRowTile': (item) =>
          topTrackRowTile(item, store: store, semanticsId: 'a'),
      'itemRowTile': (item) =>
          itemRowTile(item, store: store, semanticsId: 'a'),
      'queueRowTile': (item) =>
          queueRowTile(item, l10n: _l10n, store: store, semanticsId: 'a'),
      'rulePreviewTile': rulePreviewTile,
      'workbenchTrackTile': (item) =>
          workbenchTrackTile(item, semanticsId: 'a'),
    };

    for (final MapEntry(:key, :value) in rows.entries) {
      test('$key follows the medium of the item', () {
        final book = value(testItem('bk-1', mediaType: MediaType.audiobook));
        final episode = value(testItem('ep-1', mediaType: MediaType.podcast));
        final song = value(testItem('tr-1'));

        expect(book.domain, WaxDomain.audiobooks);
        expect(book.shape, ArtworkShape.portrait);
        expect(episode.domain, WaxDomain.podcasts);
        expect(episode.shape, ArtworkShape.square);
        expect(song.domain, WaxDomain.music);
        expect(song.shape, ArtworkShape.square);
      });

      test('$key draws the length, and none where there is none', () {
        final known = value(testItem('tr-1', durationMs: 65000));
        final unknown = value(
          testItem('ep-1', mediaType: MediaType.podcast, durationMs: 0),
        );

        expect(known.trailingText, '1:05');
        expect(unknown.trailingText, isNull);
      });
    }
  });

  group('itemCardTile', () {
    test('joins title and caption into the tooltip and reads the media', () {
      final tile = itemCardTile(
        ItemSummary(
          pid: 'bk-1',
          mediaType: MediaType.audiobook,
          title: 'A Book',
          durationMs: 3600000,
          artist: 'An Author',
          album: 'A Series',
          artUrl: '/art/3',
        ),
        l10n: _l10n,
        wax: _wax,
        store: store,
        semanticsId: 'shelf-card',
      );

      expect(tile.subtitle, 'An Author · A Series');
      expect(tile.tooltip, 'A Book\nAn Author · A Series');
      expect(tile.domain, WaxDomain.audiobooks);
      expect(tile.shape, ArtworkShape.portrait);
      expect(artworkUrl(tile), '/art/3');
      expect(tile.progress, isNull);
      expect(tile.trailingText, isNull);
      expect(tile.semanticsId, 'shelf-card');
    });

    test('drops the album that repeats the artist, and an empty caption', () {
      final same = itemCardTile(
        ItemSummary(
          pid: 'ep-1',
          mediaType: MediaType.podcast,
          title: 'Episode',
          durationMs: 1000,
          artist: 'Show',
          album: 'Show',
        ),
        l10n: _l10n,
        wax: _wax,
        store: store,
        semanticsId: 'a',
      );
      final none = itemCardTile(
        testItem('tr-1', artist: null),
        l10n: _l10n,
        wax: _wax,
        store: store,
        semanticsId: 'b',
      );

      expect(same.subtitle, 'Show');
      expect(none.subtitle, isNull);
      expect(none.tooltip, 'Prancing Pony Blues');
    });

    test('adds the ring and the time left when a position is given', () {
      final item = testItem('tr-1', durationMs: 600000);
      final tile = itemCardTile(
        item,
        l10n: _l10n,
        wax: _wax,
        store: store,
        progress: _progress(300000),
        semanticsId: 'a',
      );
      final fresh = itemCardTile(
        item,
        l10n: _l10n,
        wax: _wax,
        store: store,
        progress: PlayProgress.none,
        semanticsId: 'a',
      );

      expect(tile.progress, 0.5);
      expect(
        tile.trailingText,
        _l10n.homeShelfRemaining(_wax.formatSpan(const Duration(minutes: 5))),
      );
      expect(
        tile.trailingSpoken,
        _l10n.homeShelfRemaining(
          _wax.spellDuration(const Duration(minutes: 5)),
        ),
      );
      expect(fresh.progress, isNull);
      expect(
        fresh.trailingText,
        _l10n.homeShelfRemaining(_wax.formatSpan(const Duration(minutes: 10))),
      );
    });
  });

  group('books', () {
    final book = ItemSummary(
      pid: 'bk-1',
      mediaType: MediaType.audiobook,
      title: 'A Book',
      durationMs: 7200000,
      artist: 'An Author',
      artUrl: '/art/book',
    );

    test('seriesBookRowTile spans the whole book', () {
      final tile = seriesBookRowTile(
        book,
        wax: _wax,
        store: store,
        progress: _progress(3600000),
        semanticsId: 'series-row-0',
      );

      expect(tile.title, 'A Book');
      expect(tile.subtitle, 'An Author');
      expect(tile.domain, WaxDomain.audiobooks);
      expect(tile.shape, ArtworkShape.portrait);
      expect(tile.progress, 0.5);
      expect(tile.trailingText, _wax.formatSpan(const Duration(hours: 2)));
      expect(tile.trailingSpoken, _wax.spellDuration(const Duration(hours: 2)));
      expect(artworkUrl(tile), '/art/book');
    });

    test('seriesBookRowTile shows nothing for a book of unknown length', () {
      final tile = seriesBookRowTile(
        ItemSummary(
          pid: 'bk-2',
          mediaType: MediaType.audiobook,
          title: 'Empty',
          durationMs: 0,
        ),
        wax: _wax,
        store: store,
        progress: PlayProgress.none,
        semanticsId: 'series-row-1',
      );

      expect(tile.trailingText, isNull);
      expect(tile.trailingSpoken, isNull);
    });

    test('bookContinueTile says how much is left, or nothing', () {
      final started = bookContinueTile(
        book,
        l10n: _l10n,
        wax: _wax,
        store: store,
        progress: _progress(3600000),
        semanticsId: 'continue-bk-1',
      );
      final fresh = bookContinueTile(
        book,
        l10n: _l10n,
        wax: _wax,
        store: store,
        progress: PlayProgress.none,
        semanticsId: 'continue-bk-1',
      );

      expect(started.progress, 0.5);
      expect(
        started.trailingText,
        _l10n.booksTimeLeft(_wax.formatSpan(const Duration(hours: 1))),
      );
      expect(
        started.trailingSpoken,
        _l10n.booksTimeLeft(_wax.spellDuration(const Duration(hours: 1))),
      );
      expect(started.domain, WaxDomain.audiobooks);
      expect(fresh.progress, isNull);
      expect(
        fresh.trailingText,
        _l10n.booksTimeLeft(_wax.formatSpan(const Duration(hours: 2))),
      );
    });

    test('bookContinueTile says nothing with no length or nothing left', () {
      MediaTileData tile(ItemSummary book, PlayProgress progress) =>
          bookContinueTile(
            book,
            l10n: _l10n,
            wax: _wax,
            store: store,
            progress: progress,
            semanticsId: 'continue-bk-1',
          );

      final unknownLength = tile(
        ItemSummary(
          pid: 'bk-2',
          mediaType: MediaType.audiobook,
          title: 'Empty',
          durationMs: 0,
        ),
        _progress(60000),
      );
      final heardToTheEnd = tile(book, _progress(7200000));

      expect(unknownLength.trailingText, isNull);
      expect(unknownLength.trailingSpoken, isNull);
      expect(unknownLength.progress, isNull);
      expect(heardToTheEnd.trailingText, isNull);
      expect(heardToTheEnd.trailingSpoken, isNull);
      expect(heardToTheEnd.progress, 1.0);
    });

    test('bookCardTile says finished, time left, or the length', () {
      (String?, String?) run(PlayProgress progress) {
        final tile = bookCardTile(
          book,
          l10n: _l10n,
          wax: _wax,
          store: store,
          progress: progress,
          semanticsId: 'book-bk-1',
        );
        return (tile.trailingText, tile.trailingSpoken);
      }

      expect(run(_progress(0, finished: true)).$1, _l10n.booksFinished);
      expect(run(_progress(3600000)), (
        _l10n.booksTimeLeft(_wax.formatSpan(const Duration(hours: 1))),
        _l10n.booksTimeLeft(_wax.spellDuration(const Duration(hours: 1))),
      ));
      expect(run(PlayProgress.none), (
        _wax.formatSpan(const Duration(hours: 2)),
        _wax.spellDuration(const Duration(hours: 2)),
      ));
    });

    test('bookCardTile shows nothing for a book of unknown length', () {
      final tile = bookCardTile(
        ItemSummary(
          pid: 'bk-2',
          mediaType: MediaType.audiobook,
          title: 'Empty',
          durationMs: 0,
        ),
        l10n: _l10n,
        wax: _wax,
        store: store,
        progress: PlayProgress.none,
        semanticsId: 'book-bk-2',
      );

      expect(tile.trailingText, isNull);
      expect(tile.subtitle, isNull);
      expect(tile.shape, ArtworkShape.portrait);
    });

    test('bookShelfTile is a bare portrait cover', () {
      final tile = bookShelfTile(book, store: store, semanticsId: 'book-bk-1');

      expect(tile.title, 'A Book');
      expect(tile.subtitle, isNull);
      expect(tile.domain, WaxDomain.audiobooks);
      expect(tile.shape, ArtworkShape.portrait);
      expect(artworkUrl(tile), '/art/book');
      expect(tile.semanticsId, 'book-bk-1');
    });

    test('seriesCardTile counts books, and says nothing for zero', () {
      final some = seriesCardTile(
        const BookSeries(pid: 'bs-1', name: 'The Saga', bookCount: 3),
        l10n: _l10n,
        semanticsId: 'series-bs-1',
      );
      final none = seriesCardTile(
        const BookSeries(pid: 'bs-2', name: 'Hidden'),
        l10n: _l10n,
        semanticsId: 'series-bs-2',
      );

      expect(some.title, 'The Saga');
      expect(some.subtitle, _l10n.bookSeriesBookCount(3));
      expect(some.domain, WaxDomain.audiobooks);
      expect(none.subtitle, isNull);
    });

    test(
      'chapterRowTile falls back to a number and runs to the next start',
      () {
        final detail = testBook(
          'bk-1',
          durationMs: 600000,
          chapters: const <ChapterMark>[
            ChapterMark(index: 0, title: 'Prologue', startMs: 0, endMs: 30000),
            ChapterMark(index: 1, startMs: 30000),
            ChapterMark(index: 2, title: 'Last', startMs: 300000),
          ],
        );
        final named = chapterRowTile(
          detail,
          0,
          l10n: _l10n,
          semanticsId: 'chapter-0',
        );
        final unnamed = chapterRowTile(
          detail,
          1,
          l10n: _l10n,
          semanticsId: 'chapter-1',
        );
        final last = chapterRowTile(
          detail,
          2,
          l10n: _l10n,
          semanticsId: 'chapter-2',
        );

        expect(named.title, 'Prologue');
        expect(named.trailingText, '0:30');
        expect(unnamed.title, _l10n.bookChapterFallback(2));
        expect(unnamed.trailingText, '4:30');
        expect(last.trailingText, '5:00');
        expect(last.semanticsId, 'chapter-2');
      },
    );

    test('chapterRowTile shows no length for a chapter that runs nowhere', () {
      final detail = testBook(
        'bk-1',
        durationMs: 60000,
        chapters: const <ChapterMark>[
          ChapterMark(index: 0, startMs: 0, endMs: 0),
          ChapterMark(index: 1, startMs: 60000),
        ],
      );

      expect(
        chapterRowTile(
          detail,
          0,
          l10n: _l10n,
          semanticsId: 'chapter-0',
        ).trailingText,
        isNull,
      );
      expect(
        chapterRowTile(
          detail,
          1,
          l10n: _l10n,
          semanticsId: 'chapter-1',
        ).trailingText,
        isNull,
      );
    });
  });

  group('music entities', () {
    test('bucketTile names the unknown bucket and keeps the shape', () {
      final known = bucketTile(
        const FacetBucket(key: 'k', label: 'Jazz', count: 4),
        unknownTitle: 'Unknown genre',
        caption: '4 tracks',
        shape: ArtworkShape.circle,
        semanticsId: 'bucket-0',
      );
      final unknown = bucketTile(
        const FacetBucket(key: '', label: '', count: 1, unknown: true),
        unknownTitle: 'Unknown genre',
        caption: '1 track',
        shape: ArtworkShape.square,
        semanticsId: 'bucket-1',
        artwork: (_) => null,
      );

      expect(known.title, 'Jazz');
      expect(known.subtitle, '4 tracks');
      expect(known.shape, ArtworkShape.circle);
      expect(known.artwork, isNull);
      expect(unknown.title, 'Unknown genre');
      expect(unknown.artwork, isNotNull);
      expect(unknown.semanticsId, 'bucket-1');
    });

    test('releaseTile draws a monogram for a release with no entity', () {
      final entity = releaseTile(
        'Record',
        trackCount: 9,
        pid: 'al-1',
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'album-al-1',
      );
      final loose = releaseTile(
        'Loose folder',
        trackCount: 2,
        l10n: _l10n,
        store: store,
        repository: repository,
      );

      expect(entity.title, 'Record');
      expect(entity.subtitle, _l10n.musicTrackCount(9));
      expect(artworkUrl(entity), repository.artUrlFor('al-1'));
      expect(entity.semanticsId, 'album-al-1');
      expect(loose.title, 'Loose folder');
      expect(loose.artwork, isNull);
      expect(loose.semanticsId, isNull);
    });

    test('mixCardTile titles by seed and subtitles with the mix kind', () {
      final genre = mixCardTile(
        const MixCard(name: 'Shoegaze', artUrl: '/art/mix'),
        l10n: _l10n,
        store: store,
        semanticsId: 'mix-0',
      );
      final seeded = mixCardTile(
        const MixCard(name: 'Nightjar', seedPid: 'ar-1'),
        l10n: _l10n,
        store: store,
        semanticsId: 'mix-1',
      );

      expect(genre.title, 'Shoegaze');
      expect(genre.tooltip, 'Shoegaze');
      expect(genre.subtitle, _l10n.discoveryInstantMixTitle);
      expect(artworkUrl(genre), '/art/mix');
      expect(genre.domain, WaxDomain.music);
      expect(seeded.title, _l10n.homeMixMoreLike('Nightjar'));
      expect(seeded.artwork, isNull);
    });

    test('pinnedCardTile names the kind, the artist and the shape', () {
      final album = pinnedCardTile(
        const EntityCard(
          pid: 'al-1',
          kind: EntityCardKind.album,
          title: 'Record',
          artist: 'Band',
        ),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'pinned-al-1',
      );
      final artist = pinnedCardTile(
        const EntityCard(
          pid: 'ar-1',
          kind: EntityCardKind.artist,
          title: 'Band',
        ),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'pinned-ar-1',
      );
      final group = pinnedCardTile(
        const EntityCard(
          pid: 'rg-1',
          kind: EntityCardKind.releaseGroup,
          title: 'Group',
        ),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'pinned-rg-1',
      );
      final show = pinnedCardTile(
        const EntityCard(
          pid: 'pc-1',
          kind: EntityCardKind.podcast,
          title: 'Show',
        ),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'pinned-pc-1',
      );
      final book = pinnedCardTile(
        const EntityCard(pid: 'bk-1', kind: EntityCardKind.book, title: 'Bk'),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'pinned-bk-1',
      );

      expect(
        album.subtitle,
        _l10n.homePinnedCaption(_l10n.homePinnedKindAlbum, 'Band'),
      );
      expect(album.tooltip, 'Record\n${album.subtitle}');
      expect(artworkUrl(album), repository.artUrlFor('al-1'));
      expect(album.domain, WaxDomain.music);
      expect(album.shape, ArtworkShape.square);
      expect(artist.subtitle, _l10n.homePinnedKindArtist);
      expect(artist.shape, ArtworkShape.circle);
      expect(group.artwork, isNull);
      expect(show.domain, WaxDomain.podcasts);
      expect(book.domain, WaxDomain.audiobooks);
      expect(
        pinnedCardCaption(
          _l10n,
          const EntityCard(
            pid: 'pl-1',
            kind: EntityCardKind.playlist,
            title: 'List',
            artist: '',
          ),
        ),
        _l10n.homePinnedKindPlaylist,
      );
    });
  });

  group('playlistTile', () {
    test('badges a smart list and bylines a borrowed one', () {
      final smart = playlistTile(
        _playlist(kind: 'smart', artUrl: '/art/pl'),
        l10n: _l10n,
        store: store,
        semanticsId: 'playlist-pl-1',
      );
      final borrowed = playlistTile(
        _playlist(isOwner: false, itemCount: 7),
        l10n: _l10n,
        store: store,
        semanticsId: 'playlist-pl-1',
      );

      expect(smart.title, 'Road songs');
      expect(smart.badge, _l10n.playlistSmart);
      expect(smart.subtitle, isNull);
      expect(smart.trailingText, isNull);
      expect(artworkUrl(smart), '/art/pl');
      expect(borrowed.badge, isNull);
      expect(borrowed.subtitle, _l10n.playlistSharedBy('Frodo'));
      expect(borrowed.trailingText, _l10n.playlistItemCount(7));
    });

    test('says so when your own list is shared', () {
      final tile = playlistTile(
        _playlist(visibility: 'shared'),
        l10n: _l10n,
        store: store,
        semanticsId: 'playlist-pl-1',
      );

      expect(tile.subtitle, _l10n.playlistSharedByYou);
    });
  });

  group('podcasts', () {
    final episode = testEpisode(
      'ep-1',
      title: 'Pipeweed Economics',
      artist: 'Barliman',
      durationMs: 600000,
      episodeNumber: 4,
    );

    test('episodeRowTile derives facts, time left and the unplayed dot', () {
      final tile = episodeRowTile(
        episode,
        l10n: _l10n,
        progress: _progress(300000),
        semanticsId: 'episode-ep-1',
      );
      final fresh = episodeRowTile(
        episode,
        l10n: _l10n,
        progress: PlayProgress.none,
        semanticsId: 'episode-ep-1',
      );

      expect(tile.title, 'Pipeweed Economics');
      expect(tile.subtitle, _l10n.podcastEpisodeNumber(4));
      expect(tile.domain, WaxDomain.podcasts);
      expect(tile.progress, 0.5);
      expect(
        tile.trailingText,
        _l10n.podcastTimeLeft(_l10n.formatListenTime(300000)),
      );
      expect(tile.downloaded, isTrue);
      expect(tile.unplayed, isFalse);
      expect(fresh.trailingText, _l10n.formatListenTime(600000));
      expect(fresh.unplayed, isTrue);
      expect(tile.semanticsId, 'episode-ep-1');
    });

    test('episodeRowTile lets a caller replace the facts', () {
      final replaced = episodeRowTile(
        episode,
        l10n: _l10n,
        progress: PlayProgress.none,
        subtitle: 'Season finale',
        semanticsId: 'a',
      );
      final emptied = episodeRowTile(
        testEpisode('ep-2', downloaded: true),
        l10n: _l10n,
        progress: PlayProgress.none,
        subtitle: '',
        semanticsId: 'b',
      );

      expect(replaced.subtitle, 'Season finale');
      expect(emptied.subtitle, isNull);
      expect(artworkUrl(emptied), isNull);
    });

    test('episodeRowTile says when there is no audio to stream', () {
      final tile = episodeRowTile(
        testEpisode('ep-3', downloaded: false, hasEnclosure: false),
        l10n: _l10n,
        progress: PlayProgress.none,
        semanticsId: 'a',
      );

      expect(tile.subtitle, contains(_l10n.podcastNoAudioToStream));
    });

    test('episodeRowTile shows no length for a feed that declared none', () {
      final unlengthed = testEpisode('ep-4', durationMs: 0);
      final fresh = episodeRowTile(
        unlengthed,
        l10n: _l10n,
        progress: PlayProgress.none,
        semanticsId: 'a',
      );
      final started = episodeRowTile(
        unlengthed,
        l10n: _l10n,
        progress: _progress(30000),
        semanticsId: 'a',
      );

      expect(fresh.trailingText, isNull);
      expect(started.trailingText, isNull);
    });

    test('episodeShelfTile is unplayed and names the show', () {
      final tile = episodeShelfTile(
        ShelfEpisode(episode: episode, progress: PlayProgress.none),
        store: store,
        semanticsId: 'shelf-episodes-ep-1',
      );

      expect(tile.title, 'Pipeweed Economics');
      expect(tile.subtitle, 'Barliman');
      expect(tile.tooltip, 'Pipeweed Economics\nBarliman');
      expect(tile.domain, WaxDomain.podcasts);
      expect(tile.unplayed, isTrue);
      expect(tile.downloaded, isTrue);
    });

    test('episodeContinueTile shows the ring and the time left', () {
      final tile = episodeContinueTile(
        ShelfEpisode(episode: episode, progress: _progress(450000)),
        l10n: _l10n,
        store: store,
        semanticsId: 'continue-ep-1',
      );
      final done = episodeContinueTile(
        ShelfEpisode(episode: episode, progress: _progress(600000)),
        l10n: _l10n,
        store: store,
        semanticsId: 'continue-ep-1',
      );

      expect(tile.subtitle, 'Barliman');
      expect(tile.progress, 0.75);
      expect(
        tile.trailingText,
        _l10n.podcastTimeLeft(_l10n.formatListenTime(150000)),
      );
      expect(tile.unplayed, isFalse);
      expect(done.trailingText, isNull);
    });

    test('showTile prefers what is waiting over the episode count', () {
      Subscription subscribed(int? unplayed, int? episodes) => Subscription(
        show: testShow('pc-1', episodeCount: episodes),
        settings: const SubscriptionSettings(),
        subscribedAt: DateTime.utc(2026, 7, 1),
        unplayedCount: unplayed,
      );

      final waiting = showTile(
        subscribed(3, 20),
        l10n: _l10n,
        store: store,
        semanticsId: 'podcast-pc-1',
      );
      final caughtUp = showTile(
        subscribed(0, 20),
        l10n: _l10n,
        store: store,
        semanticsId: 'podcast-pc-1',
      );
      final blank = showTile(
        subscribed(null, null),
        l10n: _l10n,
        store: store,
        semanticsId: 'podcast-pc-1',
      );

      expect(waiting.title, 'The Prancing Pony Hour');
      expect(waiting.subtitle, 'Barliman Butterbur');
      expect(waiting.trailingText, _l10n.podcastUnplayedCount(3));
      expect(waiting.unplayed, isTrue);
      expect(waiting.domain, WaxDomain.podcasts);
      expect(caughtUp.trailingText, _l10n.podcastEpisodeCount(20));
      expect(caughtUp.unplayed, isFalse);
      expect(blank.trailingText, isNull);
    });
  });

  group('downloads', () {
    final track = ItemSummary(
      pid: 'tr-held',
      mediaType: MediaType.audiobook,
      title: 'Held Book',
      durationMs: 1000000,
      artist: 'Author',
      artUrl: '/art/held',
    );

    test('downloadShelfTile is downloaded and reads the stored media', () {
      final tile = downloadShelfTile(
        _download(track),
        store: store,
        semanticsId: 'shelf-downloaded-tr-held',
      );
      final gone = downloadShelfTile(
        _download(null),
        store: store,
        semanticsId: 'shelf-downloaded-tr-held',
      );

      expect(tile.title, 'Held Book');
      expect(tile.subtitle, 'Author');
      expect(tile.domain, WaxDomain.audiobooks);
      expect(tile.shape, ArtworkShape.portrait);
      expect(tile.downloaded, isTrue);
      expect(tile.tooltip, 'Held Book\nAuthor');
      expect(artworkUrl(tile), '/art/held');
      expect(gone.title, 'tr-held');
      expect(gone.tooltip, 'tr-held');
      expect(gone.domain, WaxDomain.music);
      expect(gone.artwork, isNull);
    });

    test('downloadTransferTile passes the live fraction and held readout', () {
      final tile = downloadTransferTile(
        _download(track, sizeBytes: 5000),
        l10n: _l10n,
        store: store,
        progress: 0.4,
        trailingDetail: 'Held',
        trailingDetailSpoken: 'Held for wifi',
        semanticsId: 'download-tr-held',
      );

      expect(tile.title, 'Held Book');
      expect(tile.progress, 0.4);
      expect(tile.trailingText, _l10n.formatBytes(5000));
      expect(tile.trailingDetail, 'Held');
      expect(tile.trailingDetailSpoken, 'Held for wifi');
      expect(tile.downloaded, isFalse);
      expect(tile.domain, WaxDomain.audiobooks);
    });

    PlayState state(int positionMs, {bool finished = false}) => PlayState(
      pid: 'tr-held',
      positionMs: positionMs,
      played: finished,
      finished: finished,
      playCount: 0,
      starred: false,
      updatedAt: DateTime.utc(2026, 7, 1),
    );

    test('downloadRowTile marks never-heard and measures a partial play', () {
      final unheard = downloadRowTile(
        _download(track),
        l10n: _l10n,
        store: store,
        semanticsId: 'download-tr-held',
      );
      final partway = downloadRowTile(
        _download(track, progress: state(250000)),
        l10n: _l10n,
        store: store,
        semanticsId: 'download-tr-held',
      );
      final finished = downloadRowTile(
        _download(track, progress: state(250000, finished: true)),
        l10n: _l10n,
        store: store,
        semanticsId: 'download-tr-held',
      );

      expect(unheard.unplayed, isTrue);
      expect(unheard.progress, isNull);
      expect(unheard.downloaded, isTrue);
      expect(unheard.trailingText, _l10n.formatBytes(2048));
      expect(partway.unplayed, isFalse);
      expect(partway.progress, 0.25);
      expect(finished.progress, isNull);
    });
  });

  group('radio', () {
    test('savedSongTile leads with the announcement when nothing parsed', () {
      final parsed = savedSongTile(
        RadioSavedSong(
          pid: 'rw-1',
          nowPlaying: 'Band - Song',
          artist: 'Band',
          title: 'Song',
          stationName: 'Coastal FM',
          inLibraryPid: 'tr-1',
          heardAt: DateTime.utc(2026, 7, 1),
          hasArt: true,
        ),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'saved-rw-1',
      );
      final raw = savedSongTile(
        RadioSavedSong(
          pid: 'rw-2',
          nowPlaying: 'Just a line',
          stationName: 'Coastal FM',
          heardAt: DateTime.utc(2026, 7, 1),
          hasArt: false,
        ),
        l10n: _l10n,
        store: store,
        repository: repository,
        semanticsId: 'saved-rw-2',
      );

      expect(parsed.title, 'Song');
      expect(
        parsed.subtitle,
        'Band · Coastal FM · ${_l10n.radioSavedInLibrary}',
      );
      expect(artworkUrl(parsed), repository.radioSavedArtUrlFor('rw-1'));
      expect(parsed.domain, WaxDomain.radio);
      expect(raw.title, 'Just a line');
      expect(raw.subtitle, 'Coastal FM');
      expect(raw.artwork, isNull);
    });

    test('stationTile is a circle on the radio hue', () {
      final tile = stationTile(
        RadioStation(
          pid: 'rs-1',
          name: 'Coastal FM',
          streamUrl: 'https://stream.example/coastal',
          createdAt: DateTime.utc(2026, 7, 1),
        ),
        subtitle: 'Playing',
        artwork: (_) => null,
        semanticsId: 'radio-rs-1',
      );

      expect(tile.title, 'Coastal FM');
      expect(tile.subtitle, 'Playing');
      expect(tile.domain, WaxDomain.radio);
      expect(tile.shape, ArtworkShape.circle);
      expect(tile.artwork, isNotNull);
      expect(tile.semanticsId, 'radio-rs-1');
    });
  });

  group('search', () {
    test('recentSearchTile is the query and nothing else', () {
      final tile = recentSearchTile('nightjar', semanticsId: 'recent-0');

      expect(tile.title, 'nightjar');
      expect(tile.subtitle, isNull);
      expect(tile.semanticsId, 'recent-0');
    });

    test('searchHitTile picks the hue and the shape from the group', () {
      const hit = SearchHit(
        pid: 'x-1',
        kind: 'artist',
        title: 'Nightjar',
        subtitle: '3 albums',
      );

      final artist = searchHitTile(
        hit,
        SearchHitKind.artists,
        semanticsId: 'hit-0',
      );
      final episode = searchHitTile(
        hit,
        SearchHitKind.episodes,
        semanticsId: 'hit-1',
      );
      final book = searchHitTile(
        hit,
        SearchHitKind.books,
        semanticsId: 'hit-2',
      );
      final track = searchHitTile(
        hit,
        SearchHitKind.tracks,
        semanticsId: 'hit-3',
      );

      expect(artist.title, 'Nightjar');
      expect(artist.subtitle, '3 albums');
      expect(artist.shape, ArtworkShape.circle);
      expect(artist.domain, WaxDomain.music);
      expect(episode.domain, WaxDomain.podcasts);
      expect(episode.shape, ArtworkShape.square);
      expect(book.domain, WaxDomain.audiobooks);
      expect(book.semanticsId, 'hit-2');
      expect(track.domain, WaxDomain.music);
      expect(track.semanticsId, 'hit-3');
    });
  });

  group('stats', () {
    ListenLogEntry entry({
      String? title = 'Song',
      String? artist = 'Band',
      String client = 'web',
      bool finished = false,
      StatsMediaType mediaType = StatsMediaType.music,
    }) => ListenLogEntry(
      pid: 'tr-1',
      title: title,
      artist: artist,
      mediaType: mediaType,
      startedAt: DateTime.utc(2026, 7, 1, 8),
      msPlayed: 125000,
      finished: finished,
      client: client,
      source: 'live',
    );

    test('listenLogTile joins who, where and when under the title', () {
      final tile = listenLogTile(entry(), l10n: _l10n);

      expect(tile.title, 'Song');
      expect(
        tile.subtitle,
        'Band · web · ${_l10n.formatStamp(DateTime.utc(2026, 7, 1, 8))}',
      );
      expect(tile.trailingText, _l10n.formatListenTime(125000));
      expect(tile.trailingSpoken, _l10n.formatListenTime(125000));
      expect(tile.badge, isNull);
      expect(tile.domain, WaxDomain.music);
    });

    test('listenLogTile marks a finished listen and a removed item', () {
      final tile = listenLogTile(
        entry(
          title: null,
          artist: null,
          client: '',
          finished: true,
          mediaType: StatsMediaType.audiobook,
        ),
        l10n: _l10n,
      );
      final radio = listenLogTile(
        entry(mediaType: StatsMediaType.radio),
        l10n: _l10n,
      );

      expect(tile.title, _l10n.statsLogRemovedItem);
      expect(tile.subtitle, _l10n.formatStamp(DateTime.utc(2026, 7, 1, 8)));
      expect(tile.badge, _l10n.statsLogFinished);
      expect(
        tile.trailingSpoken,
        _l10n.statsLogFinishedSpoken(_l10n.formatListenTime(125000)),
      );
      expect(tile.domain, WaxDomain.audiobooks);
      expect(tile.shape, ArtworkShape.portrait);
      expect(radio.domain, WaxDomain.radio);
      expect(radio.shape, ArtworkShape.square);
    });

    test('topEntryTile reads the kind of list for the hue and the shape', () {
      const row = TopEntry(
        name: 'Nightjar',
        artUrl: '/art/top',
        plays: 12,
        ms: 600000,
      );

      final artists = topEntryTile(
        row,
        'artists',
        l10n: _l10n,
        store: store,
        semanticsId: 'top-0',
      );
      final shows = topEntryTile(
        row,
        'shows',
        l10n: _l10n,
        store: store,
        semanticsId: 'top-1',
      );
      final stations = topEntryTile(
        row,
        'stations',
        l10n: _l10n,
        store: store,
        semanticsId: 'top-2',
      );
      final genres = topEntryTile(
        const TopEntry(name: '', plays: 1, ms: 0),
        'genres',
        l10n: _l10n,
        store: store,
        semanticsId: 'top-3',
      );
      final albums = topEntryTile(
        row,
        'albums',
        l10n: _l10n,
        store: store,
        semanticsId: 'top-4',
      );

      expect(artists.title, 'Nightjar');
      expect(artists.subtitle, _l10n.statsPlays(12));
      expect(artists.trailingText, _l10n.formatListenTime(600000));
      expect(artworkUrl(artists), '/art/top');
      expect(artists.shape, ArtworkShape.circle);
      expect(artists.domain, WaxDomain.music);
      expect(shows.domain, WaxDomain.podcasts);
      expect(shows.shape, ArtworkShape.square);
      expect(stations.domain, WaxDomain.radio);
      expect(genres.title, _l10n.statsLogRemovedItem);
      expect(genres.shape, ArtworkShape.circle);
      expect(albums.shape, ArtworkShape.square);
      expect(albums.semanticsId, 'top-4');
    });
  });
}
