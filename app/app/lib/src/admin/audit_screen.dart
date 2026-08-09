import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'admin_console.dart';

/// The action-prefix filter above the audit list.
class AuditFilterController extends Notifier<String> {
  @override
  String build() => '';

  void set(String prefix) => state = prefix;
}

final auditFilterProvider = NotifierProvider<AuditFilterController, String>(
  AuditFilterController.new,
);

/// Accumulated pages of audit events, newest first.
class AuditState {
  const AuditState({
    required this.events,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<AuditEvent> events;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  AuditState copyWith({bool? loadingMore}) => AuditState(
    events: events,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the audit log with keyset cursors, filtered by action prefix.
class AuditController extends AsyncNotifier<AuditState> {
  static const pageSize = 50;

  var _generation = 0;

  @override
  Future<AuditState> build() async {
    _generation++;
    final filter = ref.watch(auditFilterProvider);
    final page = await ref
        .watch(repositoryProvider)
        .listAuditEvents(
          action: filter.isEmpty ? null : filter,
          limit: pageSize,
        );
    return AuditState(events: page.events, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final filter = ref.read(auditFilterProvider);
      final page = await ref
          .read(repositoryProvider)
          .listAuditEvents(
            action: filter.isEmpty ? null : filter,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        AuditState(
          events: [...current.events, ...page.events],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure,
      // a bad cast. Release the paging guard first - loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently - then let the error
      // reach the zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final auditProvider = AsyncNotifierProvider<AuditController, AuditState>(
  AuditController.new,
);

/// The audit log: who did what, newest first, with the stored detail
/// behind each row.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  late final TextEditingController _filter = TextEditingController(
    text: ref.read(auditFilterProvider),
  );

  /// Which row has its detail open. One at a time: the detail is a JSON
  /// block, and several expanded at once turns the log into a wall.
  String? _expanded;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final audit = ref.watch(auditProvider);
    return WaxScaffold(
      title: 'Audit log',
      largeTitle: false,
      semanticsId: SemanticsIds.adminAudit,
      onBack: adminBack(context),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: sizeClass.gutter.add(
              const EdgeInsets.only(bottom: WaxSpace.s12),
            ),
            // `ReadingColumn` rather than a `ConstrainedBox`: a sliver
            // hands down a tight width and padding keeps it tight, so
            // the cap here was resolving straight back to the window
            // and the filter box ran the width of the page.
            child: ReadingColumn(
              maxWidth: 480,
              child: SearchField(
                label: 'Filter by action',
                hint: 'user. or backup.create',
                controller: _filter,
                semanticsId: SemanticsIds.auditFilter,
                clearSemanticsId: SemanticsIds.auditFilterClear,
                // Submitting applies it: each keystroke would be a
                // request, and an action prefix is typed whole. The
                // change handler is what redraws the clear control as
                // the field fills, and clearing the field applies the
                // empty filter without a second press.
                onChanged: (value) {
                  if (value.isEmpty) {
                    ref.read(auditFilterProvider.notifier).set('');
                  }
                  setState(() {});
                },
                onSubmitted: (value) =>
                    ref.read(auditFilterProvider.notifier).set(value.trim()),
              ),
            ),
          ),
        ),
        switch (audit) {
          AsyncData(:final value) when value.events.isEmpty =>
            const SliverToBoxAdapter(
              child: EmptyState(
                glyph: WaxIcons.info,
                title: 'Nothing logged yet',
                message:
                    'Administrative actions are recorded here as they happen.',
              ),
            ),
          AsyncData(:final value) => _list(sizeClass, value),
          AsyncError(:final error) => SliverToBoxAdapter(
            child: ErrorState(
              title: 'Could not load the audit log',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'Something went wrong reading it.',
              onRetry: () => ref.invalidate(auditProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
      ],
    );
  }

  Widget _list(WaxSizeClass sizeClass, AuditState state) {
    return SliverPadding(
      padding: sizeClass.gutter.add(
        const EdgeInsets.only(bottom: WaxSpace.s32),
      ),
      sliver: SliverList.builder(
        itemCount: state.events.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.events.length) {
            return const Padding(
              padding: EdgeInsets.all(WaxSpace.s16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          // Paging asks from the tail rather than from a scroll
          // listener: the list is a sliver inside the page's own scroll
          // view now, so building the last row is what says "near the
          // end". The controller's own guards make a repeat a no-op.
          if (index == state.events.length - 1) {
            // Guarded: the callback runs after the frame, and navigating
            // away as the last row builds disposes this State first -
            // touching ref then throws. The NotificationListener this
            // replaced could not outlive the widget and needed no guard.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref.read(auditProvider.notifier).loadMore();
            });
          }
          final event = state.events[index];
          return _AuditRow(
            event: event,
            expanded: _expanded == event.id,
            onToggle: () => setState(
              () => _expanded = _expanded == event.id ? null : event.id,
            ),
          );
        },
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({
    required this.event,
    required this.expanded,
    required this.onToggle,
  });

  final AuditEvent event;
  final bool expanded;
  final VoidCallback onToggle;

  /// Rough relative age, enough to scan the log by eye.
  static String relativeTime(DateTime at, {DateTime? now}) {
    final delta = (now ?? DateTime.now().toUtc()).difference(at.toUtc());
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 30) return '${delta.inDays}d ago';
    return '${delta.inDays ~/ 30}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final subtitle = StringBuffer(event.actorName ?? 'system');
    if (event.targetName != null) subtitle.write(', ${event.targetName}');
    subtitle.write(', ${relativeTime(event.createdAt)}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WaxTappable(
          label: '${event.action}, $subtitle',
          semanticsId: SemanticsIds.auditRow(event.id),
          selected: expanded,
          borderRadius: WaxRadius.chip,
          onPressed: onToggle,
          child: Material(
            color: Colors.transparent,
            borderRadius: WaxRadius.chip,
            child: InkWell(
              onTap: onToggle,
              borderRadius: WaxRadius.chip,
              child: Padding(
                padding: const EdgeInsets.all(WaxSpace.s8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            event.action,
                            style: WaxType.monoData.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            subtitle.toString(),
                            style: WaxType.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    WaxIcon(
                      expanded ? WaxIcons.collapse : WaxIcons.expand,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(
              left: WaxSpace.s8,
              bottom: WaxSpace.s8,
            ),
            padding: const EdgeInsets.all(WaxSpace.s12),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: WaxRadius.chip,
            ),
            // Detail is one JSON block and stays tabular: it scrolls
            // sideways in its own box rather than wrapping into
            // something nobody can read.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                event.detail.isEmpty
                    ? 'No further detail'
                    : const JsonEncoder.withIndent('  ').convert(event.detail),
                style: WaxType.monoData.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}
