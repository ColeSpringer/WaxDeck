import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Accumulated pages of the caller's share links.
class SharesState {
  const SharesState({
    required this.shares,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<Share> shares;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  SharesState copyWith({bool? loadingMore}) => SharesState(
    shares: shares,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages share links, newest first, and revokes them.
///
/// [all] picks the listing: the caller's own links, or - for an
/// administrator - every account's. One class rather than two because
/// the paging, the revoke, and the failure handling are identical; only
/// the scope differs, and the server decides who may ask for the wider
/// one.
class SharesController extends AsyncNotifier<SharesState> {
  SharesController({this.all = false});

  static const pageSize = 50;

  final bool all;

  var _generation = 0;

  @override
  Future<SharesState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listShares(limit: pageSize, all: all);
    return SharesState(shares: page.shares, nextCursor: page.nextCursor);
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .listShares(cursor: current.nextCursor, limit: pageSize, all: all);
      if (generation != _generation) return;
      state = AsyncData(
        SharesState(
          shares: [...current.shares, ...page.shares],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }

  /// Revokes one link and reloads both listings from the top. Errors
  /// propagate so the screen can surface the message.
  ///
  /// Both, not just this one: the administrative listing is everyone's
  /// links including the caller's own, so one revoked row is stale in
  /// two caches. Left to `invalidateSelf`, an administrator who revoked
  /// their own link from the console would find it still listed on
  /// their personal screen, and revoking it there answers 404 for a
  /// link the app itself just took away.
  Future<void> revoke(String sharePid) async {
    await ref.read(repositoryProvider).revokeShare(sharePid);
    invalidateShareListings(ref.container);
  }
}

final sharesProvider = AsyncNotifierProvider<SharesController, SharesState>(
  SharesController.new,
);

/// Every account's share links, for the console's oversight section.
/// A provider of its own rather than a parameter on [sharesProvider]:
/// the two listings answer different rows and are open at once whenever
/// an administrator has both screens in a history.
final adminSharesProvider =
    AsyncNotifierProvider<SharesController, SharesState>(
      () => SharesController(all: true),
    );

/// Refreshes both share listings, which overlap: every row on the
/// personal one is also on the administrative one. Anything that mints
/// or revokes a link goes through here rather than naming one of them.
void invalidateShareListings(ProviderContainer container) {
  container
    ..invalidate(sharesProvider)
    ..invalidate(adminSharesProvider);
}
