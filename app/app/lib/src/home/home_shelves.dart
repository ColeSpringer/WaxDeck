import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
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

/// How many rows a shelf that discards reads to fill itself.
///
/// Much larger than the shelf, because two kinds of shelf throw rows
/// away: the resume shelf drops anything finished, and a media-scoped
/// shelf gets a window filtered rather than a list filtered (the
/// contract says so). Both can burn most of a page.
const int kHomeShelfWindow = 100;

/// How many rows a shelf that discards nothing reads.
///
/// Not the card count exactly. A caller with restricted library
/// visibility has rows dropped underneath it - the listing contract says
/// short pages are legal - so a shelf asking for precisely what it draws
/// would come back thin for them. Twice over covers that without paying
/// for a hundred rows to draw a dozen.
const int kHomeShelfSlack = kHomeShelfCards * 2;

/// One shelf's worth of items, with the caller's position on each.
///
/// A record rather than a class: every shelf answers the same pair, and
/// the screen reads both together.
typedef HomeShelfItems = ({List<ItemSummary> items, PlayProgressView progress});

const HomeShelfItems _emptyShelf = (
  items: <ItemSummary>[],
  progress: PlayProgressView.empty,
);

/// Reads one discovery list, optionally scoped to a medium.
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
  bool Function(ItemSummary item, PlayProgress progress)? keep,
}) async {
  final repository = ref.watch(repositoryProvider);
  final page = await repository.browse(
    list,
    mediaType: mediaType,
    // A shelf that throws rows away has to read past what it draws. The
    // media type is not one of those: the server narrows the list itself
    // now, so a filtered page comes back full.
    limit: keep != null ? kHomeShelfWindow : kHomeShelfSlack,
  );
  if (page.items.isEmpty) return _emptyShelf;
  var progress = PlayProgressView.empty;
  if (withProgress || keep != null) {
    final states = await repository.listPlayStates([
      for (final item in page.items) item.pid,
    ]);
    progress = PlayProgressView(<String, PlayProgress>{
      for (final state in states)
        state.pid: PlayProgress(
          positionMs: state.positionMs,
          played: state.played,
          finished: state.finished,
          updatedAt: state.updatedAt,
        ),
    });
  }
  final kept = <ItemSummary>[];
  for (final item in page.items) {
    if (kept.length == cards) break;
    if (keep != null && !keep(item, progress[item.pid])) continue;
    kept.add(item);
  }
  return (items: kept, progress: progress);
}

/// What the caller was in the middle of, across every medium.
///
/// The recently-played list carries what they finished too, and a
/// "continue" card over a finished album is an offer to hear it again
/// dressed up as an offer to carry on, so the finished rows are dropped
/// here rather than drawn without a ring.
final continueListeningShelfProvider =
    FutureProvider.autoDispose<HomeShelfItems>(
      (ref) => readShelf(
        ref,
        DiscoveryList.recentlyPlayed,
        withProgress: true,
        keep: (item, progress) => progress.inProgress,
      ),
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
/// and the first-run state, and it is the cheapest question there is:
/// does the library hold one item.
final libraryHasAnythingProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final page = await ref.watch(repositoryProvider).listItems(limit: 1);
  return page.items.isNotEmpty;
});

/// Every home read, for the pull-to-refresh gesture and for the catalog
/// fan-out: a scan changes what is on all of them at once.
final List<ProviderBase<Object?>> homeShelfProviders = <ProviderBase<Object?>>[
  libraryHasAnythingProvider,
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
