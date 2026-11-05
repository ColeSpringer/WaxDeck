import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../media_view.dart';
import '../shell/async_sliver_face.dart';
import '../shell/paged_scroll.dart';
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

class _ListenLogScreenState extends ConsumerState<ListenLogScreen>
    with PagedScroll {
  @override
  void loadMore() => ref.read(listenLogProvider.notifier).loadMore();

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(listenLogProvider);
    fillViewportWhile(
      (log.value?.hasMore ?? false) && !(log.value?.loadingMore ?? true),
      at: log.value?.entries,
    );
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
      controller: pagedScroll,
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
        AsyncSliverFace<ListenLogState>(
          state: log,
          errorTitle: l10n.statsLogLoadError,
          onRetry: () => ref.invalidate(listenLogProvider),
          isEmpty: (value) => value.entries.isEmpty,
          empty: (context, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.statsLogEmptyTitle,
              glyph: WaxIcons.recent,
            ),
          ),
          builder: (context, value) => SliverPadding(
            padding: sizeClass.gutter,
            sliver: SliverList.builder(
              itemCount: value.entries.length,
              itemBuilder: (context, index) =>
                  _ListenLogRow(index: index, entry: value.entries[index]),
            ),
          ),
        ),
        if (log.value?.loadingMore ?? false)
          const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list, count: 1),
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
