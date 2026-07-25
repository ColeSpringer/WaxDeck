import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

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
      // a bad cast. Release the paging guard first — loadingMore is
      // what keeps two fetches from racing, so leaving it set would
      // wedge paging permanently and silently — then let the error
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

/// The audit log: who did what, newest first, with expandable detail.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  late final TextEditingController _filter = TextEditingController(
    text: ref.read(auditFilterProvider),
  );

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audit = ref.watch(auditProvider);
    final filter = ref.watch(auditFilterProvider);
    return Semantics(
      identifier: 'admin-audit',
      container: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Audit log')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Semantics(
                identifier: 'audit-filter',
                child: TextField(
                  key: const Key('audit-filter'),
                  controller: _filter,
                  decoration: InputDecoration(
                    labelText: 'Filter by action',
                    hintText: 'user. or backup.create',
                    prefixIcon: const Icon(Icons.filter_alt_outlined),
                    suffixIcon: filter.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('audit-filter-clear'),
                            tooltip: 'Clear filter',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _filter.clear();
                              ref.read(auditFilterProvider.notifier).set('');
                            },
                          ),
                  ),
                  onSubmitted: (value) =>
                      ref.read(auditFilterProvider.notifier).set(value.trim()),
                ),
              ),
            ),
            Expanded(
              child: switch (audit) {
                AsyncData(:final value) => _list(value),
                AsyncError(:final error) => _errorView(error),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load the audit log';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(auditProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _list(AuditState state) {
    if (state.events.isEmpty) {
      return const Center(child: Text('Nothing logged yet'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(auditProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.events.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.events.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _AuditRow(event: state.events[index]);
        },
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event});

  final AuditEvent event;

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
    final textTheme = Theme.of(context).textTheme;
    final subtitle = StringBuffer(event.actorName ?? 'system');
    if (event.targetName != null) {
      subtitle.write(', ${event.targetName}');
    }
    subtitle.write(', ${relativeTime(event.createdAt)}');
    return Semantics(
      identifier: 'audit-row-${event.id}',
      child: ExpansionTile(
        key: ValueKey('audit-row-${event.id}'),
        title: Text(event.action, style: textTheme.titleSmall),
        subtitle: Text(subtitle.toString()),
        children: [
          if (event.detail.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No further detail'),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  const JsonEncoder.withIndent('  ').convert(event.detail),
                  style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
