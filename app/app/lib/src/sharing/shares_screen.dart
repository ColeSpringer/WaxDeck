import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'share_dialog.dart';
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
    await Clipboard.setData(ClipboardData(text: shareAbsoluteUrl(share.url)));
    if (!mounted) return;
    _report('Link copied');
  }

  Future<void> _revoke(Share share) async {
    try {
      await ref.read(sharesProvider.notifier).revoke(share.pid);
      if (!mounted) return;
      _report('Link revoked');
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      _report(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shares = ref.watch(sharesProvider);
    final rows = shares.value?.shares ?? const <Share>[];

    return WaxScaffold(
      title: 'Share links',
      largeTitle: false,
      controller: _scroll,
      onBack: () => context.leave(fallback: WaxRoute.settings),
      slivers: <Widget>[
        switch (shares) {
          AsyncData() when rows.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'No share links yet',
              message:
                  'Share a track, an episode, a book, or a playlist and the '
                  'link turns up here, with how often it has been played and '
                  'a way to switch it off.',
              glyph: WaxIcons.share,
              semanticsId: SemanticsIds.sharesEmpty,
            ),
          ),
          AsyncData() => _ShareList(
            rows: rows,
            onCopy: _copy,
            onRevoke: _revoke,
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load your share links',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
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

class _ShareList extends StatelessWidget {
  const _ShareList({
    required this.rows,
    required this.onCopy,
    required this.onRevoke,
  });

  final List<Share> rows;
  final Future<void> Function(Share share) onCopy;
  final Future<void> Function(Share share) onRevoke;

  /// A share's target reads as its own medium, so the row's glyph says
  /// what the link opens rather than that it is a link. A playlist has
  /// no domain of its own and takes the music glyph, which is what it is
  /// made of.
  static WaxGlyph _glyph(String kind) => switch (kind) {
    'episode' => WaxIcons.podcasts,
    'book' => WaxIcons.audiobooks,
    'playlist' => WaxIcons.playlists,
    _ => WaxIcons.music,
  };

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  /// What a row says under its title: what it opens, how much it has been
  /// used, and when it dies. Three facts, in that order, because that is
  /// the order somebody auditing their own links reads them in.
  static String _caption(Share share) {
    final expiresAt = share.expiresAt;
    final expired = expiresAt != null && expiresAt.isBefore(DateTime.now());
    return <String>[
      share.targetKind,
      share.plays == 1 ? '1 play' : '${share.plays} plays',
      if (expiresAt == null)
        'never expires'
      else if (expired)
        'expired ${_date(expiresAt)}'
      else
        'expires ${_date(expiresAt)}',
      if (share.allowDownload) 'download allowed',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final share = rows[index];
          return WaxOptionRow(
            glyph: _glyph(share.targetKind),
            title: share.targetTitle,
            subtitle: _caption(share),
            semanticsId: SemanticsIds.shareRow(share.pid),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                WaxIconButton(
                  glyph: WaxIcons.share,
                  label: 'Copy link',
                  semanticsId: SemanticsIds.shareCopy(share.pid),
                  onPressed: () => onCopy(share),
                ),
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: 'Revoke link',
                  semanticsId: SemanticsIds.shareRevoke(share.pid),
                  onPressed: () => onRevoke(share),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
