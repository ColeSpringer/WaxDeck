import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/async_sliver_face.dart';
import '../shell/paged_scroll.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
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

class _AdminSharesScreenState extends ConsumerState<AdminSharesScreen>
    with PagedScroll {
  @override
  void loadMore() => ref.read(adminSharesProvider.notifier).loadMore();

  void _report(String message) {
    ref
        .read(shellMessengerProvider.notifier)
        .show(message, channel: ShellChannel.shares);
  }

  Future<void> _copy(Share share) async {
    final l10n = context.l10n;
    await Clipboard.setData(
      ClipboardData(text: shareAbsoluteUrl(ref, share.url)),
    );
    if (!mounted) return;
    _report(l10n.adminShareCopied);
  }

  Future<void> _revoke(Share share) async {
    final l10n = context.l10n;
    try {
      await ref.read(adminSharesProvider.notifier).revoke(share.pid);
      if (!mounted) return;
      _report(l10n.adminShareRevoked);
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      _report(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shares = ref.watch(adminSharesProvider);
    fillViewportWhile(
      (shares.value?.hasMore ?? false) && !(shares.value?.loadingMore ?? true),
      at: shares.value?.shares,
    );
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.adminSectionShares,
      largeTitle: false,
      semanticsId: SemanticsIds.adminShares,
      controller: pagedScroll,
      onBack: adminBack(context),
      slivers: <Widget>[
        AsyncSliverFace<SharesState>(
          state: shares,
          errorTitle: l10n.adminSharesLoadError,
          onRetry: () => ref.invalidate(adminSharesProvider),
          isEmpty: (value) => value.shares.isEmpty,
          empty: (context, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.adminSharesEmptyTitle,
              message: l10n.adminSharesEmptyMessage,
              glyph: WaxIcons.share,
              semanticsId: SemanticsIds.adminSharesEmpty,
            ),
          ),
          builder: (context, value) =>
              ShareRows(rows: value.shares, onCopy: _copy, onRevoke: _revoke),
        ),
        if (shares.value?.loadingMore ?? false)
          const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list, count: 1),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}
