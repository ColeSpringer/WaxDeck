import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../shell/semantics_ids.dart';
import 'podcasts_controller.dart';
import 'show_screen.dart';

/// The caller's podcast subscriptions, with an add-subscription dialog.
class PodcastsScreen extends ConsumerWidget {
  const PodcastsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Podcasts')),
      floatingActionButton: Semantics(
        identifier: SemanticsIds.podcastAdd,
        label: 'Add subscription',
        button: true,
        child: FloatingActionButton(
          key: const Key(SemanticsIds.podcastAdd),
          tooltip: 'Add subscription',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _SubscribeDialog(),
          ),
          child: const Icon(Icons.add),
        ),
      ),
      body: switch (subscriptions) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(subscriptionsProvider.future),
          child: value.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No subscriptions yet')),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) =>
                      _SubscriptionRow(subscription: value[index]),
                ),
        ),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is WaxDeckApiException
                    ? error.message
                    : 'Could not load subscriptions',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(subscriptionsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final show = subscription.show;
    final artUrl = show.artUrl;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: SemanticsIds.podcast(show.pid),
      label: show.title,
      button: true,
      child: ListTile(
        key: ValueKey(SemanticsIds.podcast(show.pid)),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 48,
            height: 48,
            child: artUrl == null
                ? ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.podcasts),
                  )
                : Image.network(
                    artUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.podcasts),
                    ),
                  ),
          ),
        ),
        title: Text(show.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: show.author == null
            ? null
            : Text(show.author!, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ShowScreen(pid: show.pid)),
        ),
      ),
    );
  }
}

/// URL entry plus a source-type toggle; the subscribe call surfaces
/// server errors (feed-unreachable and friends) as a SnackBar.
class _SubscribeDialog extends ConsumerStatefulWidget {
  const _SubscribeDialog();

  @override
  ConsumerState<_SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends ConsumerState<_SubscribeDialog> {
  final _urlController = TextEditingController();
  var _sourceType = 'rss';
  var _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(subscriptionsProvider.notifier)
          .subscribe(url: url, sourceType: _sourceType);
      navigator.pop();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subscription'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No Semantics identifier wrapper: on the web it would mint a
          // second, disabled text-field node beside the real input.
          // Tests locate the field by its label, like the login form.
          TextField(
            key: const Key('podcast-url-field'),
            controller: _urlController,
            decoration: const InputDecoration(labelText: 'Feed or channel URL'),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'rss', label: Text('RSS')),
              ButtonSegment(value: 'youtube', label: Text('YouTube')),
            ],
            selected: {_sourceType},
            onSelectionChanged: (selection) =>
                setState(() => _sourceType = selection.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: SemanticsIds.podcastSubscribeConfirm,
          label: 'Subscribe',
          button: true,
          child: FilledButton(
            key: const Key(SemanticsIds.podcastSubscribeConfirm),
            onPressed: _busy ? null : _subscribe,
            child: const Text('Subscribe'),
          ),
        ),
      ],
    );
  }
}
