import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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
      for (final entry in entries) entry.client,
    }.toList()..sort();
    final sizeClass = WaxSizeClass.of(context);

    return WaxScaffold(
      title: 'Listen log',
      largeTitle: false,
      controller: _scroll,
      onBack: () => context.leave(fallback: WaxRoute.stats),
      actions: <Widget>[
        WaxChoice<String>(
          value: filter ?? _allClients,
          options: clients,
          labelFor: (client) => client == _allClients ? 'All clients' : client,
          label: 'Reported by',
          semanticsId: SemanticsIds.listenLogClientFilter,
          onChanged: (client) => ref
              .read(listenLogClientProvider.notifier)
              .select(client == _allClients ? null : client),
        ),
      ],
      slivers: <Widget>[
        switch (log) {
          AsyncData() when entries.isEmpty => const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'No listens recorded yet',
              message:
                  'Every session a client finishes lands here, whichever '
                  'device reported it.',
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
              title: 'Could not load the listen log',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
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
    final details = <String>[
      ?entry.artist,
      entry.client,
      _stamp(entry.startedAt),
    ];
    return MediaListRow(
      key: Key('listen-log-row-$index'),
      data: MediaTileData(
        // A session outlives the item it was about: a track deleted
        // since is still a listen that happened.
        title: entry.title ?? 'Removed item',
        subtitle: details.join(' · '),
        domain: waxDomainOf(entry.mediaType),
        shape: waxShapeOf(entry.mediaType),
        trailingText: formatListenTime(entry.msPlayed),
        // The tick is the whole of what "finished" means here, and the
        // row reads it out rather than leaving it to a glyph.
        trailingSpoken: entry.finished
            ? '${formatListenTime(entry.msPlayed)}, finished'
            : formatListenTime(entry.msPlayed),
        badge: entry.finished ? 'Finished' : null,
      ),
    );
  }
}
