import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../music/music_controllers.dart';
import '../providers.dart';
import 'queue_state.dart';

/// How many items a rolling window draws at a time.
///
/// Deliberately far below [kQueueCap]: the draw lands on a queue that is
/// nearly full, so every entry it adds evicts an older one, and drawing a
/// whole cap's worth would leave the queue with no history at all - the
/// "Previously" strip empty a moment after a track ends. A hundred is
/// several hours ahead and leaves most of the queue to what was played.
const int kQueueDrawSize = 100;

/// How many pages a draw with no cursor will read looking for the entry
/// the queue stands at.
///
/// A cursor is the ordinary way back into a source; this is the fallback
/// for a window cut short of its caller's frontier, and for one restored
/// from a build that stored no cursor. Each page is a cap's worth, so
/// this reaches twenty thousand items in - past that, sealing the window
/// is a better answer than a minute of paging.
const int _maxPlacementPages = 40;

/// One draw against the scope a rolling queue was cut from.
class QueueDraw {
  const QueueDraw({
    required this.pids,
    required this.cursor,
    required this.more,
    this.seed,
  });

  /// What to append, in the source's own order. Empty is a real answer:
  /// a page whose every item was filtered out still moves the cursor on.
  final List<String> pids;

  /// Where the source stands after this draw.
  final String cursor;

  /// Whether the source has more behind this draw.
  final bool more;

  /// The seed this draw walked, for the sources whose order is a
  /// permutation rather than a listing.
  final int? seed;
}

/// A way back to the scope a queue was cut from.
///
/// The queue is a window: it holds at most [kQueueCap] entries of
/// something that may be far larger, and this is what turns the source
/// it came from back into more pids. Sources that cannot be paged - a
/// mix, a search, one item tapped on its own - answer null, and the
/// window is sealed rather than pretending there is more.
abstract class QueueSourcePager {
  /// The next draw against [source], or null when nothing here can page
  /// it or place itself in it.
  ///
  /// [afterPid] is the entry standing at the queue's frontier, used only
  /// when the source carries no cursor: the draw pages the source from
  /// its head until it passes that entry, and continues from there.
  Future<QueueDraw?> draw(QueueSource source, {String? afterPid});
}

/// [QueueSourcePager] over the repository, which is where every one of
/// these listings already lives: a bucket is a facet drill, the library
/// is a browse list, a playlist is its own members endpoint.
class RepositoryQueueSourcePager implements QueueSourcePager {
  RepositoryQueueSourcePager(this._repository);

  final WaxDeckRepository _repository;

  @override
  Future<QueueDraw?> draw(QueueSource source, {String? afterPid}) async {
    final listing = _listing(source);
    if (listing == null) return null;
    if (source.cursor.isNotEmpty || source.seed != null) {
      return _read(listing, source.cursor, kQueueDrawSize);
    }
    return afterPid == null ? null : _place(listing, afterPid);
  }

  /// Pages [listing] from its head until it passes [afterPid], and hands
  /// back everything after it on that page.
  ///
  /// The whole remainder rather than a draw's worth, because a keyset
  /// cursor names a page boundary and there is no cursor for the middle
  /// of one. It costs a wider append on the one path that needs placing
  /// at all, which is a restore.
  Future<QueueDraw?> _place(_Listing listing, String afterPid) async {
    var cursor = '';
    for (var page = 0; page < _maxPlacementPages; page++) {
      final read = await _read(listing, cursor, kQueueCap);
      final at = read.pids.indexOf(afterPid);
      if (at >= 0) {
        return QueueDraw(
          pids: read.pids.sublist(at + 1),
          cursor: read.cursor,
          more: read.more,
          seed: read.seed,
        );
      }
      if (!read.more) return null;
      cursor = read.cursor;
    }
    return null;
  }

  Future<QueueDraw> _read(_Listing listing, String cursor, int limit) async {
    final page = await listing(cursor.isEmpty ? null : cursor, limit);
    return QueueDraw(
      pids: page.pids,
      cursor: page.nextCursor ?? '',
      more: page.nextCursor != null,
      seed: page.seed,
    );
  }

  /// How one source lists itself, or null when it does not.
  ///
  /// The sources left out are the ones with no listing behind them: a
  /// mix and a search are answers rather than places, a single item is
  /// its own whole scope, and a show or a book queues what it queues.
  _Listing? _listing(QueueSource source) {
    switch (source.kind) {
      case QueueSourceKind.library:
        // A seeded window is walking a permutation, and the seed is what
        // keeps the pages of it from overlapping. Without one the
        // library lists in its own order.
        final seed = source.seed;
        if (seed != null) {
          // The random list is over everything the library holds, so the
          // media type is this end's to apply: a shuffle of all music
          // that dealt out an audiobook would be a twelve-hour track.
          return (cursor, limit) => _repository
              .browse(
                DiscoveryList.random,
                cursor: cursor,
                limit: limit,
                seed: seed,
              )
              .then(
                (page) => _pageOf(page, (i) => i.mediaType == MediaType.music),
              );
        }
        return (cursor, limit) => _repository
            .listItems(mediaType: MediaType.music, cursor: cursor, limit: limit)
            .then((page) => _pageOf(page, null));
      case QueueSourceKind.artist:
      case QueueSourceKind.album:
      case QueueSourceKind.genre:
      case QueueSourceKind.year:
        final dimension = _dimensionOf(source.kind);
        final segment = source.pid;
        if (segment == null) return null;
        return (cursor, limit) => _repository
            .listItems(
              facet: dimension.wireName,
              facetKey: musicFacetKey(dimension, segment),
              cursor: cursor,
              limit: limit,
            )
            // A bucket counts whatever carried its artist or its year,
            // books included, and the screens that queue one leave them
            // out for the same reason a draw does: a twelve-hour file
            // arriving between two tracks is not what was asked for.
            .then(
              (page) =>
                  _pageOf(page, (i) => i.mediaType != MediaType.audiobook),
            );
      case QueueSourceKind.playlist:
        final pid = source.pid;
        if (pid == null) return null;
        return (cursor, limit) async {
          final page = await _repository.listPlaylistItems(
            pid,
            cursor: cursor,
            limit: limit,
          );
          return _Page(
            pids: [for (final entry in page.entries) entry.item.pid],
            nextCursor: page.nextCursor,
          );
        };
      case QueueSourceKind.mix:
      case QueueSourceKind.shelf:
      case QueueSourceKind.search:
      case QueueSourceKind.show:
      case QueueSourceKind.book:
      case QueueSourceKind.single:
      case QueueSourceKind.unknown:
        return null;
    }
  }

  MusicDimension _dimensionOf(QueueSourceKind kind) => switch (kind) {
    QueueSourceKind.artist => MusicDimension.artists,
    QueueSourceKind.album => MusicDimension.albums,
    QueueSourceKind.genre => MusicDimension.genres,
    QueueSourceKind.year => MusicDimension.years,
    // Unreachable: the caller matched on the four dimension kinds.
    _ => MusicDimension.artists,
  };

  /// One listing page as pids, keeping the items [keep] admits.
  static _Page _pageOf(ItemPage page, bool Function(ItemSummary)? keep) =>
      _Page(
        pids: [
          for (final item in page.items)
            if (keep == null || keep(item)) item.pid,
        ],
        nextCursor: page.nextCursor,
        seed: page.seed,
      );
}

/// One page of pids from a source, whatever endpoint answered it.
class _Page {
  const _Page({required this.pids, this.nextCursor, this.seed});

  final List<String> pids;
  final String? nextCursor;
  final int? seed;
}

/// A source's listing, as one call: a cursor and a limit in, a page of
/// pids out.
typedef _Listing = Future<_Page> Function(String? cursor, int limit);

final queueSourcePagerProvider = Provider<QueueSourcePager>(
  (ref) => RepositoryQueueSourcePager(ref.watch(repositoryProvider)),
);
