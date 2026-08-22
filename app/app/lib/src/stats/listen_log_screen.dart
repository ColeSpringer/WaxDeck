import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../media_view.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'stats_controller.dart';

/// What no client filter means, as a value the picker can hold. An empty
/// string rather than null, because [WaxChoice] takes a value and not an
/// optional one, and a pid is never empty.
const _allClients = '';

/// The caller's listen session log, newest first, cursor paged with
/// infinite scroll and an optional reporting-client filter.
class ListenLogScreen extends ConsumerStatefulWidget {
  const ListenLogScreen({super.key});

  @override
  ConsumerState<ListenLogScreen> createState() => _ListenLogScreenState();
}

class _ListenLogScreenState extends ConsumerState<ListenLogScreen> {
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
    ref.read(listenLogProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(listenLogProvider);
    final filter = ref.watch(listenLogClientProvider);
    final entries = log.value?.entries ?? const <ListenLogEntry>[];
    // Clients seen in the loaded pages; the active filter stays listed
    // even when it filtered itself out of the page.
    final clients = <String>{
      _allClients,
      ?filter,
      // Radio is measured in the server's stream proxy rather than
      // reported by a device, so its rows name no client. Belt and
      // braces: `_allClients` is itself the empty string, so a set
      // already folds a nameless client into the "all" row rather than
      // drawing a blank one beside it - this is the half that survives
      // that constant becoming a sentinel of its own.
      for (final entry in entries)
        if (entry.client.isNotEmpty) entry.client,
    }.toList()..sort();
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.statsDoorListenLog,
      largeTitle: false,
      controller: _scroll,
      onBack: () => context.leave(fallback: WaxRoute.stats),
      actions: <Widget>[
        WaxChoice<String>(
          value: filter ?? _allClients,
          options: clients,
          labelFor: (client) =>
              client == _allClients ? l10n.statsLogAllClients : client,
          label: l10n.statsLogReportedBy,
          semanticsId: SemanticsIds.listenLogClientFilter,
          onChanged: (client) => ref
              .read(listenLogClientProvider.notifier)
              .select(client == _allClients ? null : client),
        ),
      ],
      slivers: <Widget>[
        switch (log) {
          AsyncData() when entries.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.statsLogEmptyTitle,
              message: l10n.statsLogEmptyMessage,
              glyph: WaxIcons.recent,
            ),
          ),
          AsyncData() => SliverPadding(
            padding: sizeClass.gutter,
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) =>
                  _ListenLogRow(index: index, entry: entries[index]),
            ),
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.statsLogLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(listenLogProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
        if (log.value?.loadingMore ?? false)
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

class _ListenLogRow extends StatelessWidget {
  const _ListenLogRow({required this.index, required this.entry});

  final int index;
  final ListenLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final played = l10n.formatListenTime(entry.msPlayed);
    final details = <String>[
      ?entry.artist,
      // Skipped when empty, the way the filter above skips it: a radio
      // row is measured by the server and names no client, and joining
      // an empty string in leads the subtitle with a bare separator.
      if (entry.client.isNotEmpty) entry.client,
      l10n.formatStamp(entry.startedAt),
    ];
    return MediaListRow(
      key: Key('listen-log-row-$index'),
      data: MediaTileData(
        // A session outlives the item it was about: a track deleted
        // since is still a listen that happened.
        title: entry.title ?? l10n.statsLogRemovedItem,
        subtitle: details.join(' · '),
        domain: waxDomainOfStats(entry.mediaType),
        shape: waxShapeOfStats(entry.mediaType),
        trailingText: played,
        // The tick is the whole of what "finished" means here, and the
        // row reads it out rather than leaving it to a glyph.
        trailingSpoken: entry.finished
            ? l10n.statsLogFinishedSpoken(played)
            : played,
        badge: entry.finished ? l10n.statsLogFinished : null,
      ),
    );
  }
}
