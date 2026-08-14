import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';

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
      // A defect, not a hiccup. Release the paging guard first or it
      // wedges paging silently, then let the error out.
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

/// The file-diagnostics dashboard: counts by code over a filtered table
/// of the files behind them. Administrators only.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final list = ref.watch(diagnosticsProvider);
    return WaxScaffold(
      title: l10n.adminSectionDiagnostics,
      largeTitle: false,
      semanticsId: SemanticsIds.adminDiagnostics,
      onBack: adminBack(context),
      onRefresh: () async {
        ref
          ..invalidate(diagnosticSummaryProvider)
          ..invalidate(diagnosticsProvider);
        await ref.read(diagnosticsProvider.future);
      },
      slivers: <Widget>[
        SliverPadding(
          padding: sizeClass.gutter,
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SummaryChips(),
                switch (list) {
                  AsyncData(:final value) => _Table(state: value),
                  AsyncError(:final error) => ErrorState(
                    title: l10n.healthDiagnosticsLoadError,
                    message: context.explain(error),
                    onRetry: () => ref.invalidate(diagnosticsProvider),
                  ),
                  _ => const SkeletonShapes(shape: SkeletonShape.list),
                },
                const SizedBox(height: WaxSpace.s32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A chip per code with its count; tapping filters the table. Summary
/// and filter at once, because a count nobody can act on is wallpaper.
class _SummaryChips extends ConsumerWidget {
  const _SummaryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(diagnosticSummaryProvider);
    final selected = ref.watch(diagnosticCodeFilterProvider);
    final counts = summary.value ?? const <DiagnosticCount>[];
    if (counts.isEmpty) return const SizedBox.shrink();
    // Aggregate per code: several origin/severity buckets can share a
    // code.
    final byCode = <String, int>{};
    for (final c in counts) {
      byCode[c.code] = (byCode[c.code] ?? 0) + c.count;
    }
    final codes = byCode.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s16),
      child: FilterChipRow(
        padding: EdgeInsets.zero,
        // A second press on the lit chip clears the filter, so the row
        // has no "all" chip of its own: the cleared state is the one
        // where nothing is lit.
        selected: selected ?? '',
        onSelect: (code) =>
            ref.read(diagnosticCodeFilterProvider.notifier).toggle(code),
        chips: <WaxFilterChip>[
          for (final code in codes)
            WaxFilterChip(
              name: code,
              label: context.l10n.healthDiagnosticsChip(code, byCode[code]!),
              semanticsId: SemanticsIds.diagnosticCode(code),
            ),
        ],
      ),
    );
  }
}

class _Table extends ConsumerWidget {
  const _Table({required this.state});

  final DiagnosticsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Paged by a button: the table draws eagerly, so a scroll
        // listener would keep growing a frame nobody asked to grow.
        WaxTable<FileDiagnostic>(
          rows: state.diagnostics,
          rowId: (diagnostic) => diagnostic.path,
          rowSemanticsId: SemanticsIds.diagnosticRow,
          rowDetailSemanticsId: SemanticsIds.diagnosticDetail,
          caption: state.hasMore
              ? l10n.healthDiagnosticsMore(state.diagnostics.length)
              : null,
          empty: EmptyState(
            glyph: WaxIcons.success,
            title: l10n.healthDiagnosticsEmptyTitle,
            message: l10n.healthDiagnosticsEmptyMessage,
          ),
          columns: <WaxColumn<FileDiagnostic>>[
            WaxColumn<FileDiagnostic>(
              label: l10n.healthColumnFile,
              priority: WaxColumnPriority.primary,
              text: (diagnostic) => diagnostic.path,
              cell: (context, diagnostic) => Text(
                diagnostic.path,
                style: WaxType.monoData.copyWith(color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            WaxColumn<FileDiagnostic>(
              label: l10n.healthColumnCode,
              width: 180,
              text: (diagnostic) => diagnostic.code,
              cell: (context, diagnostic) => Text(
                diagnostic.code,
                style: WaxType.monoData.copyWith(color: colors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            WaxColumn<FileDiagnostic>(
              label: l10n.healthColumnOrigin,
              width: 108,
              text: (diagnostic) => diagnostic.origin,
              cell: (context, diagnostic) => Text(
                diagnostic.origin,
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
            WaxColumn<FileDiagnostic>(
              label: l10n.healthColumnSeverity,
              width: 96,
              text: (diagnostic) => _severityLabel(l10n, diagnostic.severity),
              cell: (context, diagnostic) => Text(
                _severityLabel(l10n, diagnostic.severity),
                style: WaxType.label.copyWith(
                  color: _severityTone(colors, diagnostic.severity),
                ),
              ),
            ),
          ],
        ),
        if (state.hasMore) ...<Widget>[
          const SizedBox(height: WaxSpace.s16),
          WaxButton(
            label: state.loadingMore ? l10n.commonLoading : l10n.healthLoadMore,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.expand,
            semanticsId: SemanticsIds.diagnosticsMore,
            onPressed: state.loadingMore
                ? null
                : () => ref.read(diagnosticsProvider.notifier).loadMore(),
          ),
        ],
      ],
    );
  }

  /// How serious a finding is, in words. The code and the origin beside
  /// it stay as the server wrote them: both name things - an observation
  /// and the pass that recorded it - rather than describing one.
  static String _severityLabel(AppLocalizations l10n, String severity) =>
      switch (severity) {
        'info' => l10n.healthSeverityInfo,
        'warn' => l10n.healthSeverityWarn,
        'error' => l10n.healthSeverityError,
        _ => severity,
      };

  static Color _severityTone(WaxColors colors, String severity) =>
      switch (severity) {
        'error' => colors.error,
        'warn' => colors.accent,
        _ => colors.textTertiary,
      };
}
