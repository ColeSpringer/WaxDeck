import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import '../sharing/share_dialog.dart';
import '../sharing/share_rows.dart';
import '../sharing/shares_controller.dart';
import 'admin_console.dart';

/// Every public link this server has minted, whoever minted it.
///
/// A share is a capability URL: whoever holds it listens, without an
/// account and without a trace beyond the play count. The personal
/// listing lets somebody audit their own; this one is the operator's
/// half of the same question - what is published from here, by whom -
/// and revoke, which the endpoint already allowed an administrator, is
/// what makes it an answer rather than a report.
class AdminSharesScreen extends ConsumerStatefulWidget {
  const AdminSharesScreen({super.key});

  @override
  ConsumerState<AdminSharesScreen> createState() => _AdminSharesScreenState();
}

class _AdminSharesScreenState extends ConsumerState<AdminSharesScreen> {
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
    ref.read(adminSharesProvider.notifier).loadMore();
  }

  void _report(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(Share share) async {
    await Clipboard.setData(ClipboardData(text: shareAbsoluteUrl(share.url)));
    if (!mounted) return;
    _report('Link copied');
  }

  Future<void> _revoke(Share share) async {
    try {
      await ref.read(adminSharesProvider.notifier).revoke(share.pid);
      if (!mounted) return;
      _report('Link revoked');
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      _report(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shares = ref.watch(adminSharesProvider);
    final rows = shares.value?.shares ?? const <Share>[];

    return WaxScaffold(
      title: 'Share links',
      largeTitle: false,
      semanticsId: SemanticsIds.adminShares,
      controller: _scroll,
      onBack: adminBack(context),
      slivers: <Widget>[
        switch (shares) {
          AsyncData() when rows.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing is shared',
              message:
                  'Nobody on this server has minted a public link. When '
                  'somebody does it turns up here, with who made it and a '
                  'way to switch it off.',
              glyph: WaxIcons.share,
              semanticsId: SemanticsIds.adminSharesEmpty,
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
              title: 'Could not load the share links',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(adminSharesProvider),
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
