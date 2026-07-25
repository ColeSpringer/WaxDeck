import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../media_icons.dart';
import '../shell/semantics_ids.dart';
import 'stats_controller.dart';

/// The caller's listen session log, newest first, cursor paged with
/// infinite scroll and an optional reporting-client filter.
class ListenLogScreen extends ConsumerWidget {
  const ListenLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(listenLogProvider);
    final filter = ref.watch(listenLogClientProvider);
    // Clients seen in the loaded pages; the active filter stays listed
    // even when it filtered itself out of the page.
    final clients = <String>{
      ?filter,
      for (final entry in log.value?.entries ?? const <ListenLogEntry>[])
        entry.client,
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listen log'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Semantics(
              identifier: SemanticsIds.listenLogClientFilter,
              child: DropdownButton<String?>(
                key: const Key(SemanticsIds.listenLogClientFilter),
                value: filter,
                underline: const SizedBox.shrink(),
                onChanged: (client) =>
                    ref.read(listenLogClientProvider.notifier).select(client),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All clients'),
                  ),
                  for (final client in clients)
                    DropdownMenuItem<String?>(
                      value: client,
                      child: Text(client),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: switch (log) {
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is WaxDeckApiException
                    ? error.message
                    : 'Could not load the listen log',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(listenLogProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, ListenLogState state) {
    if (state.entries.isEmpty) {
      return const Center(child: Text('No listens recorded yet'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(listenLogProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.entries.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.entries.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _ListenLogRow(index: index, entry: state.entries[index]);
        },
      ),
    );
  }
}

class _ListenLogRow extends StatelessWidget {
  const _ListenLogRow({required this.index, required this.entry});

  final int index;
  final ListenLogEntry entry;

  static String _stamp(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = [
      if (entry.artist != null) entry.artist!,
      entry.client,
      _stamp(entry.startedAt),
    ];
    return ListTile(
      key: Key('listen-log-row-$index'),
      leading: Icon(mediaFallbackIcon(entry.mediaType)),
      title: Text(
        entry.title ?? 'Removed item',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        details.join(' | '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatListenTime(entry.msPlayed), style: textTheme.labelMedium),
          if (entry.finished)
            Icon(
              Icons.check,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }
}
