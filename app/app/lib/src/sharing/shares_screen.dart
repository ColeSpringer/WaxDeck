import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'share_dialog.dart';
import 'shares_controller.dart';

/// The caller's share links: target, kind, plays, and expiry per row,
/// with copy and revoke, cursor paged with infinite scroll.
class SharesScreen extends ConsumerWidget {
  const SharesScreen({super.key});

  Future<void> _copy(BuildContext context, Share share) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: shareAbsoluteUrl(share.url)));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, Share share) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sharesProvider.notifier).revoke(share.pid);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Link revoked')));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(sharesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Share links')),
      body: switch (shares) {
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is WaxDeckApiException
                    ? error.message
                    : 'Could not load share links',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(sharesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, SharesState state) {
    if (state.shares.isEmpty) {
      return const Center(child: Text('No share links yet'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(sharesProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.shares.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.shares.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final share = state.shares[index];
          return _ShareRow(
            share: share,
            onCopy: () => _copy(context, share),
            onRevoke: () => _revoke(context, ref, share),
          );
        },
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.share,
    required this.onCopy,
    required this.onRevoke,
  });

  final Share share;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  static IconData _kindIcon(String kind) => switch (kind) {
    'album' => Icons.album,
    'playlist' => Icons.queue_music,
    'book' => Icons.menu_book,
    'episode' => Icons.podcasts,
    _ => Icons.music_note,
  };

  static String _date(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = share.expiresAt;
    final details = [
      share.targetKind,
      '${share.plays} plays',
      expiresAt == null ? 'never expires' : 'expires ${_date(expiresAt)}',
    ];
    return Semantics(
      identifier: 'share-row-${share.pid}',
      child: ListTile(
        key: Key('share-row-${share.pid}'),
        leading: Icon(_kindIcon(share.targetKind)),
        title: Text(
          share.targetTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(details.join(' | ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              identifier: 'share-copy-${share.pid}',
              label: 'Copy link',
              button: true,
              child: IconButton(
                key: Key('share-copy-${share.pid}'),
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy),
                onPressed: onCopy,
              ),
            ),
            Semantics(
              identifier: 'share-revoke-${share.pid}',
              label: 'Revoke link',
              button: true,
              child: IconButton(
                key: Key('share-revoke-${share.pid}'),
                tooltip: 'Revoke link',
                icon: const Icon(Icons.link_off),
                onPressed: onRevoke,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
