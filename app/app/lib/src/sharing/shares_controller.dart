import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../auth/auth_controller.dart';
import '../providers.dart';
import '../sync/refresh_in_place.dart';

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
}

/// Pages share links, newest first, refreshes them in place (a sweep
/// reads again what is loaded, where the list stands), and revokes them.
///
/// [all] picks the listing: the caller's own links, or - for an
/// administrator - every account's. One class rather than two because
/// the paging, the revoke, and the failure handling are identical; only
/// the scope differs, and the server decides who may ask for the wider
/// one.
class SharesController extends AsyncNotifier<SharesState>
    with RefreshedInPlace<Share, SharesState> {
  SharesController({this.all = false});

  static const pageSize = 50;

  final bool all;

  @override
  ProviderBase<Object?> get self => all ? adminSharesProvider : sharesProvider;

  @override
  int get pageRows => pageSize;

  @override
  int? get walkLimit => 1;

  @override
  Object rowKey(Share row) => row.pid;

  @override
  SharesState shape(PagedRows<Share> held, {required bool loadingMore}) =>
      SharesState(
        shares: held.rows,
        nextCursor: held.nextCursor,
        loadingMore: loadingMore,
      );

  @override
  Future<PagedRows<Share>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  }) {
    final repository = ref.read(repositoryProvider);
    return walkRows(
      (cursor) async {
        final page = await repository.listShares(
          cursor: cursor,
          limit: pageSize,
          all: all,
        );
        return (rows: page.shares, nextCursor: page.nextCursor);
      },
      want: want,
      from: from,
      maxPages: maxPages,
      stop: stop,
    );
  }

  @override
  Future<SharesState> build() {
    // Keyed on the account: the repository moves only with the server.
    final account = ref.watch(signedInAccountProvider);
    final repository = ref.watch(repositoryProvider);
    return buildInPlace(source: (account, repository));
  }

  /// Fetches the next page and appends it. No-op while a fetch is
  /// running or once the last page was reached.
  Future<void> loadMore() => loadMoreInPlace();

  /// Revokes one link and reads both listings again. Errors
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
  retry: retryUnlessRefused,
);

/// Every account's share links, for the console's oversight section.
/// A provider of its own rather than a parameter on [sharesProvider]:
/// the two listings answer different rows and are open at once whenever
/// an administrator has both screens in a history.
final adminSharesProvider =
    AsyncNotifierProvider<SharesController, SharesState>(
      () => SharesController(all: true),
      retry: retryUnlessRefused,
    );

/// Refreshes both share listings, which overlap: every row on the
/// personal one is also on the administrative one. Anything that mints
/// or revokes a link goes through here rather than naming one of them.
void invalidateShareListings(ProviderContainer container) {
  container
    ..invalidate(sharesProvider)
    ..invalidate(adminSharesProvider);
}
