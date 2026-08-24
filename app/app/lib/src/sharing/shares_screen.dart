import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'share_dialog.dart';
import 'share_rows.dart';
import 'shares_controller.dart';

/// The caller's share links: what each one opens, how often it has been
/// played, and when it stops working, with copy and revoke per row.
///
/// A place beneath settings rather than beside it, so the Account
/// section's own row goes here rather than pushing: a stranger opening
/// this location gets the page with settings underneath, and back lands
/// where the tap came from.
class SharesScreen extends ConsumerStatefulWidget {
  const SharesScreen({super.key});

  @override
  ConsumerState<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends ConsumerState<SharesScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    ref.read(sharesProvider.notifier).loadMore();
  }

  void _report(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(Share share) async {
    await Clipboard.setData(
      ClipboardData(text: shareAbsoluteUrl(ref, share.url)),
    );
    if (!mounted) return;
    _report(context.l10n.sharingLinkCopied);
  }

  Future<void> _revoke(Share share) async {
    try {
      await ref.read(sharesProvider.notifier).revoke(share.pid);
      if (!mounted) return;
      _report(context.l10n.sharingLinkRevoked);
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      _report(context.explain(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shares = ref.watch(sharesProvider);
    final rows = shares.value?.shares ?? const <Share>[];

    return WaxScaffold(
      title: context.l10n.sharingTitle,
      largeTitle: false,
      controller: _scroll,
      onBack: () => context.leave(fallback: WaxRoute.settings),
      slivers: <Widget>[
        switch (shares) {
          AsyncData() when rows.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: context.l10n.sharingEmptyTitle,
              message: context.l10n.sharingEmptyMessage,
              glyph: WaxIcons.share,
              semanticsId: SemanticsIds.sharesEmpty,
            ),
          ),
          AsyncData() => ShareRows(
            rows: rows,
            onCopy: _copy,
            onRevoke: _revoke,
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: context.l10n.sharingLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(sharesProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
        if (shares.value?.loadingMore ?? false)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(WaxSpace.s16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}
