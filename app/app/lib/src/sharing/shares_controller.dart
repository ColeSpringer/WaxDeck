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

/// Pages the caller's share links, newest first, and revokes them.
class SharesController extends AsyncNotifier<SharesState> {
  static const pageSize = 50;

  var _generation = 0;

  @override
  Future<SharesState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listShares(limit: pageSize);
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
          .listShares(cursor: current.nextCursor, limit: pageSize);
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
      // a bad cast. Release the paging guard first — loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently — then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }

  /// Revokes one link and reloads the list from the top. Errors
  /// propagate so the screen can surface the message.
  Future<void> revoke(String sharePid) async {
    await ref.read(repositoryProvider).revokeShare(sharePid);
    ref.invalidateSelf();
  }
}

final sharesProvider = AsyncNotifierProvider<SharesController, SharesState>(
  SharesController.new,
);
