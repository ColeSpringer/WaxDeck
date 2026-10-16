import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import '../library/page_walk.dart';
import '../player/play_progress.dart';
import '../podcasts/podcast_shelves.dart';
import '../providers.dart';
import '../review/review_controller.dart';
import 'pinned_controller.dart';

/// How many cards a home shelf holds.
///
/// A shelf is a glance, not a listing: everything on it has a "Show all"
/// door to the surface that enumerates the same thing properly. Twelve is
/// what fills a desktop row twice over and a phone row four times.
const int kHomeShelfCards = 12;

/// How many pages a shelf reads before it settles for what it holds.
///
/// A page can come back short, even empty, and still continue: the
/// listing contract allows it, though the server keeps out of the page
/// what the caller may not see. Three ride out a run of those without
/// turning one shelf into a crawl of the library.
const int kHomeShelfPages = 3;

/// One shelf's worth of items, with the caller's position on each.
///
/// A record rather than a class: every shelf answers the same pair, and
/// the screen reads both together.
typedef HomeShelfItems = ({List<ItemSummary> items, PlayProgressView progress});

const HomeShelfItems _emptyShelf = (
  items: <ItemSummary>[],
  progress: PlayProgressView.empty,
);

/// Reads one discovery list, optionally scoped to a medium, on past
/// short pages until the shelf is full, the list ends, or
/// [kHomeShelfPages] were read.
///
/// Pages of what the shelf draws: the server narrows each list, the
/// medium and what the caller may see included, so a page comes back
/// full, and one that does not sends the walk on for the rest. A later
/// page failing keeps the cards the earlier ones gave.
///
/// [withProgress] asks for the caller's positions alongside the rows.
/// Only the shelves that draw a ring want them: the sealed shelf is
/// unplayed by construction and the rest are about what a thing is
/// rather than how far through it you are, so reading positions for them
/// would be a round trip spent confirming a row of zeroes.
Future<HomeShelfItems> readShelf(
  Ref ref,
  DiscoveryList list, {
  MediaType? mediaType,
  bool withProgress = false,
  int cards = kHomeShelfCards,
}) async {
  final repository = ref.watch(repositoryProvider);
  final states = <String, PlayProgress>{};
  // A random list's order is its seed, so the pages after the first
  // carry the one the server picked or they deal from another shuffle.
  int? seed;
  final walk = await walkPages(
    (cursor) async {
      final page = await repository.browse(
        list,
        mediaType: mediaType,
        cursor: cursor,
        seed: seed,
        limit: cards,
      );
      seed ??= page.seed;
      if (page.items.isEmpty || !withProgress) return page;
      final read = await repository.listPlayStates([
        for (final item in page.items) item.pid,
      ]);
      for (final state in read) {
        states[state.pid] = PlayProgress.of(state);
      }
      return page;
    },
    want: cards,
    maxPages: kHomeShelfPages,
    stop: () => !ref.mounted,
    keepOnFailure: true,
  );
  if (walk.items.isEmpty) return _emptyShelf;
  return (
    items: walk.items.take(cards).toList(),
    progress: PlayProgressView(states),
  );
}

/// What the caller is part way through, across every medium, most
/// recently progressed first.
///
/// The server's in-progress list: an episode or a book from its first
/// saved position, whether or not a play has counted, and a track only
/// once one has, so a track skipped a few seconds in is not offered back
/// as something to carry on with.
final continueListeningShelfProvider =
    FutureProvider.autoDispose<HomeShelfItems>(
      (ref) => readShelf(ref, DiscoveryList.inProgress, withProgress: true),
    );

/// What the library gained most recently.
final recentlyAddedShelfProvider = FutureProvider.autoDispose<HomeShelfItems>(
  (ref) => readShelf(ref, DiscoveryList.recentlyAdded),
);

/// Owned and never opened: the shelf a streaming service cannot draw.
final neverPlayedShelfProvider = FutureProvider.autoDispose<HomeShelfItems>(
  (ref) => readShelf(ref, DiscoveryList.neverPlayed),
);

/// Starred or well rated, and not heard in months.
final rediscoverShelfProvider = FutureProvider.autoDispose<HomeShelfItems>(
  (ref) => readShelf(ref, DiscoveryList.rediscover),
);

/// What the caller comes back to.
final mostPlayedShelfProvider = FutureProvider.autoDispose<HomeShelfItems>(
  (ref) => readShelf(ref, DiscoveryList.mostPlayed),
);

// --- the music hub's shelves ------------------------------------------------
//
// The same reads as home's, scoped to one medium. Their own providers
// rather than a family keyed by media type: there are three of them, a
// family would be keyed by a pair (list, medium) nothing else needs, and
// the fan-out lists what it invalidates by name.

/// Music the library gained most recently.
final musicRecentlyAddedShelfProvider =
    FutureProvider.autoDispose<HomeShelfItems>(
      (ref) => readShelf(
        ref,
        DiscoveryList.recentlyAdded,
        mediaType: MediaType.music,
      ),
    );

/// The music the caller comes back to.
final musicMostPlayedShelfProvider = FutureProvider.autoDispose<HomeShelfItems>(
  (ref) => readShelf(ref, DiscoveryList.mostPlayed, mediaType: MediaType.music),
);

/// The music the caller starred.
final musicStarredShelfProvider = FutureProvider.autoDispose<HomeShelfItems>(
  (ref) => readShelf(ref, DiscoveryList.starred, mediaType: MediaType.music),
);

/// The music hub's shelves, for the catalog fan-out and for a refresh.
final List<ProviderBase<Object?>> musicShelfProviders = <ProviderBase<Object?>>[
  musicRecentlyAddedShelfProvider,
  musicMostPlayedShelfProvider,
  musicStarredShelfProvider,
];

/// The music hub's shelves that are about the caller. Same split, same
/// reason: what the library gained most recently is not per-user.
final List<ProviderBase<Object?>> musicUserShelfProviders =
    <ProviderBase<Object?>>[
      musicMostPlayedShelfProvider,
      musicStarredShelfProvider,
    ];

/// One "Made for you" card: a mix that has not been built yet.
///
/// The card carries its seed rather than its tracks. A mix is computed
/// fresh per call and never persisted, so building eight of them to draw
/// a shelf nobody may tap would be eight neighbor-graph walks per visit
/// to the home screen; the tap is what mints one.
class MixCard {
  const MixCard({required this.name, this.genre, this.seedPid, this.artUrl});

  /// The genre or artist this mix is drawn from, under its own name.
  /// Not copy: it rides the queue as the source label, where a
  /// translated frame would freeze one device's language. See [titleOf].
  final String name;

  /// The genre this mix is drawn from, for a top-genre card.
  final String? genre;

  /// The entity this mix is drawn from, for a "more like this" card.
  final String? seedPid;

  /// A cover to draw it with. A genre has none; an artist card borrows
  /// the artwork the top list already answered.
  final String? artUrl;

  /// What the card says. A genre card is its genre and nothing else; an
  /// artist card is a sentence about one, so the frame is the
  /// translator's.
  String titleOf(AppLocalizations l10n) =>
      seedPid == null ? name : l10n.homeMixMoreLike(name);

  /// What the queue calls where these tracks came from. A genre mix is
  /// its genre; a seeded one is not the thing it was seeded from, so it
  /// carries no name and the queue words the kind instead.
  String get queueLabel => seedPid == null ? name : '';
}

/// How many top genres get a card. Enough to feel like a set of choices,
/// few enough that the shelf does not become the whole genre index.
const int kMixCards = 6;

/// The mixes offered on the home screen.
///
/// Built client-side from what the caller actually listens to: a card per
/// top genre, and one per top artist. Both are seeds the mix endpoint
/// already takes, so this costs one stats read rather than a mix engine
/// running eight times.
///
/// A listener with no history gets nothing, and the shelf hides: an
/// instant mix of a library nobody has played is a random draw with a
/// personal-sounding label on it.
final mixCardsProvider = FutureProvider.autoDispose<List<MixCard>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  // Two independent reads, so they go together: awaited one after the
  // other this shelf cost two round trips to answer one question.
  final [genres, artists] = await Future.wait(<Future<TopList>>[
    repository.getTopList(kind: 'genres', limit: kMixCards),
    repository.getTopList(kind: 'artists', limit: kMixCards),
  ]);
  return <MixCard>[
    for (final genre in genres.entries.take(kMixCards))
      MixCard(name: genre.name, genre: genre.name, artUrl: genre.artUrl),
    for (final artist in artists.entries.take(kMixCards))
      // A top entry carries a pid only while its name still resolves to
      // an entity; a renamed or merged artist reads as a name alone,
      // which is nothing the mix endpoint takes as a seed.
      if (artist.pid case final seed?)
        MixCard(name: artist.name, seedPid: seed, artUrl: artist.artUrl),
  ];
});

/// Whether home has anything at all to draw.
///
/// A fresh server answers every shelf empty, and eight empty shelves is
/// not a screen. This is the one read that decides between the shelves
/// and the first-run state, so only a probe that proved the library
/// empty draws the latter: one the budget ran out on may hold anything,
/// and each shelf hides itself when it has nothing.
final libraryHasAnythingProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final repository = ref.watch(repositoryProvider);
  final walk = await probePages(
    (cursor, limit) => repository.listItems(cursor: cursor, limit: limit),
  );
  return !walk.provedEmpty;
}, retry: retryUnlessRefused);

/// Every home read, for the pull-to-refresh gesture and the error
/// state's retry: the ways somebody asks home to check itself again.
final List<ProviderBase<Object?>> homeShelfProviders = <ProviderBase<Object?>>[
  libraryHasAnythingProvider,
  ...homeCatalogShelfProviders,
];

/// The home reads a catalog change moves, for the catalog fan-out. Every
/// shelf, because a retag or an enrichment changes the titles and art on
/// all of them; not the probe, which is not worth a read on every pass
/// of a scan: the binder asks it again on a pass while it reads empty,
/// once a run of catalog changes goes quiet, and when the libraries
/// change.
final List<ProviderBase<Object?>> homeCatalogShelfProviders =
    <ProviderBase<Object?>>[
      pinnedCardsProvider,
      continueListeningShelfProvider,
      recentlyAddedShelfProvider,
      neverPlayedShelfProvider,
      rediscoverShelfProvider,
      mostPlayedShelfProvider,
      mixCardsProvider,
    ];

/// The home reads that are about the caller rather than about the
/// library.
///
/// What the *user* stream invalidates. The others are catalog facts - a
/// probe for whether the library holds anything, and what was added most
/// recently - and a checkpoint on another device says nothing about
/// either, so re-running them on every play-state event is six reads
/// spent confirming what has not moved.
final List<ProviderBase<Object?>> homeUserShelfProviders =
    <ProviderBase<Object?>>[
      continueListeningShelfProvider,
      neverPlayedShelfProvider,
      rediscoverShelfProvider,
      mostPlayedShelfProvider,
      mixCardsProvider,
    ];

/// Refreshes every shelf. What the pull gesture runs, and what the
/// error state's retry runs.
///
/// The episode shelf is invalidated beside the rest rather than listed
/// in [homeShelfProviders]: it belongs to the podcast domain, the
/// invalidation fan-out already reaches it from there, and listing it
/// twice would have the fan-out refetch it twice per hint.
Future<void> refreshHome(WidgetRef ref) async {
  for (final provider in homeShelfProviders) {
    ref.invalidate(provider);
  }
  ref.invalidate(latestEpisodesProvider);
  // The review banner is on this screen too, and the pull gesture is
  // the one way somebody asks home to re-check itself.
  ref.invalidate(pendingReviewCountProvider);
  // Awaited so the gesture's spinner lasts as long as the reads do. The
  // first shelf is representative: they run concurrently against one
  // server, and holding the indicator for the slowest of eight would
  // make a refresh feel slower than it is.
  await ref.read(libraryHasAnythingProvider.future);
}
