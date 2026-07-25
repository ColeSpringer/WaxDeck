import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The active per-code filter over the diagnostics list; null shows all.
class DiagnosticCodeFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String code) => state = state == code ? null : code;
}

final diagnosticCodeFilterProvider =
    NotifierProvider<DiagnosticCodeFilterController, String?>(
      DiagnosticCodeFilterController.new,
    );

/// Grouped diagnostic counts, for the at-a-glance summary chips.
final diagnosticSummaryProvider = FutureProvider<List<DiagnosticCount>>(
  (ref) => ref.watch(repositoryProvider).getDiagnosticSummary(),
);

/// Accumulated pages of per-file diagnostics.
class DiagnosticsState {
  const DiagnosticsState({
    required this.diagnostics,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<FileDiagnostic> diagnostics;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  DiagnosticsState copyWith({bool? loadingMore}) => DiagnosticsState(
    diagnostics: diagnostics,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Pages the diagnostics list with keyset cursors, filtered by code.
class DiagnosticsController extends AsyncNotifier<DiagnosticsState> {
  static const pageSize = 100;

  var _generation = 0;

  @override
  Future<DiagnosticsState> build() async {
    _generation++;
    final code = ref.watch(diagnosticCodeFilterProvider);
    final page = await ref
        .watch(repositoryProvider)
        .listFileDiagnostics(code: code, limit: pageSize);
    return DiagnosticsState(
      diagnostics: page.diagnostics,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final code = ref.read(diagnosticCodeFilterProvider);
      final page = await ref
          .read(repositoryProvider)
          .listFileDiagnostics(
            code: code,
            cursor: current.nextCursor,
            limit: pageSize,
          );
      if (generation != _generation) return;
      state = AsyncData(
        DiagnosticsState(
          diagnostics: [...current.diagnostics, ...page.diagnostics],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what we have;
      // scrolling near the end again retries.
      if (generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
    } catch (_) {
      // Anything else is a defect, not a hiccup: a decode failure, a
      // bad cast. Release the paging guard first -- loadingMore is what
      // keeps two fetches from racing, so leaving it set would wedge
      // paging permanently and silently -- then let the error reach the
      // zone's handler instead of vanishing here.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

final diagnosticsProvider =
    AsyncNotifierProvider<DiagnosticsController, DiagnosticsState>(
      DiagnosticsController.new,
    );

/// The file-diagnostics dashboard: summary counts by code with a filtered,
/// paginated list of the individual files. Administrators only.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(diagnosticsProvider);
    return Semantics(
      identifier: 'admin-diagnostics',
      container: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Diagnostics')),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(diagnosticSummaryProvider);
            ref.invalidate(diagnosticsProvider);
            await ref.read(diagnosticsProvider.future);
          },
          child: switch (list) {
            AsyncData(:final value) => _body(context, ref, value),
            AsyncError(:final error) => _errorView(context, ref, error),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, DiagnosticsState state) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _SummaryChips()),
        if (state.diagnostics.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No diagnostics recorded')),
          )
        else
          SliverList.builder(
            itemCount: state.diagnostics.length + (state.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= state.diagnostics.length) {
                ref.read(diagnosticsProvider.notifier).loadMore();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _DiagnosticRow(diagnostic: state.diagnostics[index]);
            },
          ),
      ],
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load diagnostics';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(diagnosticsProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// A chip per diagnostic code with its total count; tapping filters the list.
class _SummaryChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(diagnosticSummaryProvider);
    final selected = ref.watch(diagnosticCodeFilterProvider);
    final counts = summary.value ?? const [];
    if (counts.isEmpty) return const SizedBox.shrink();
    // Aggregate per code: several origin/severity buckets can share a code.
    final byCode = <String, int>{};
    for (final c in counts) {
      byCode[c.code] = (byCode[c.code] ?? 0) + c.count;
    }
    final codes = byCode.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final code in codes)
            FilterChip(
              key: Key('diagnostic-chip-$code'),
              label: Text('$code · ${byCode[code]}'),
              selected: selected == code,
              onSelected: (_) =>
                  ref.read(diagnosticCodeFilterProvider.notifier).toggle(code),
            ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.diagnostic});

  final FileDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (diagnostic.severity) {
      'error' => scheme.error,
      'warn' => scheme.tertiary,
      _ => scheme.outline,
    };
    return ListTile(
      key: Key('diagnostic-row-${diagnostic.path}'),
      dense: true,
      leading: Icon(Icons.report_outlined, color: color),
      title: Text(
        diagnostic.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${diagnostic.code} · ${diagnostic.origin} · ${diagnostic.severity}',
      ),
    );
  }
}
