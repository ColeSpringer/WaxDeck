import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';

/// The configured file organization profiles.
final organizeProfilesProvider = FutureProvider<List<OrganizeProfile>>(
  (ref) => ref.watch(repositoryProvider).listOrganizeProfiles(),
);

/// Pick a profile, preview the moves, apply behind a typed confirmation:
/// this rewrites the library's on-disk layout.
class OrganizeScreen extends ConsumerStatefulWidget {
  const OrganizeScreen({super.key});

  @override
  ConsumerState<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends ConsumerState<OrganizeScreen> {
  String? _profile;
  OrganizePlan? _plan;
  OrganizeReport? _report;
  var _busy = false;

  Future<void> _preview(String profile) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _report = null;
    });
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final plan = await ref
          .read(repositoryProvider)
          .previewOrganize(profile: profile);
      if (mounted) setState(() => _plan = plan);
    } on WaxDeckApiException catch (e) {
      // The profile came off the server's own list rather than out of a
      // field, so the table's sentence is the right one.
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(String profile) async {
    if (_busy) return;
    final l10n = context.l10n;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.organizeConfirmTitle,
      message: l10n.organizeConfirmMessage,
      confirmWord: profile,
      confirmLabel: l10n.organizeApply,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.organizeConfirm,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final report = await ref
          .read(repositoryProvider)
          .applyOrganize(profile: profile);
      if (mounted) {
        setState(() {
          _report = report;
          _plan = null;
        });
      }
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final profiles = ref.watch(organizeProfilesProvider);
    return WaxScaffold(
      title: l10n.organizeTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminOrganize,
      onBack: adminBack(context),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: switch (profiles) {
          AsyncData(:final value) => _body(context, value),
          AsyncError(:final error) => ErrorState(
            title: l10n.organizeLoadError,
            message: context.explain(error),
            onRetry: () => ref.invalidate(organizeProfilesProvider),
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<OrganizeProfile> profiles) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    if (profiles.isEmpty) {
      return EmptyState(
        glyph: WaxIcons.sort,
        title: l10n.organizeEmptyTitle,
        message: l10n.organizeEmptyMessage,
      );
    }
    final profile = _profile ?? profiles.first.name;
    final plan = _plan;
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.organizeProfileTitle,
          overline: l10n.organizeProfileOverline,
        ),
        WaxChoice<String>(
          label: l10n.organizeProfileLabel,
          value: profile,
          semanticsId: SemanticsIds.organizeProfile,
          options: <String>[for (final p in profiles) p.name],
          labelFor: (name) => name,
          onChanged: (value) => setState(() {
            _profile = value;
            _plan = null;
            _report = null;
          }),
        ),
        const SizedBox(height: WaxSpace.s16),
        Row(
          children: <Widget>[
            WaxButton(
              label: l10n.organizePreview,
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.search,
              semanticsId: SemanticsIds.organizePreview,
              onPressed: _busy ? null : () => _preview(profile),
            ),
            const SizedBox(width: WaxSpace.s8),
            WaxButton(
              label: l10n.organizeApply,
              icon: WaxIcons.sort,
              semanticsId: SemanticsIds.organizeApply,
              // No plan, no apply: a run without one rewrites the
              // library on trust.
              onPressed: _busy || plan == null ? null : () => _apply(profile),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        if (plan != null)
          _PlanTable(plan: plan)
        else if (report != null)
          _ReportView(report: report)
        else
          Text(
            l10n.organizeHint,
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

/// The dry run: what would move, and where to.
class _PlanTable extends StatelessWidget {
  const _PlanTable({required this.plan});

  final OrganizePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.organizePlan,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: l10n.organizePlannedMoves(plan.totalActions),
            overline: plan.tagWrite ? l10n.organizeTagWrite : null,
          ),
          if (plan.actions.isEmpty)
            EmptyState(
              glyph: WaxIcons.success,
              title: l10n.organizeNothingTitle,
              message: l10n.organizeNothingMessage,
            )
          else
            WaxTable<OrganizeAction>(
              rows: plan.actions,
              rowId: (action) => action.from,
              rowSemanticsId: SemanticsIds.organizeRow,
              rowDetailSemanticsId: SemanticsIds.organizeRowDetail,
              caption: plan.actions.length < plan.totalActions
                  ? l10n.organizeShowingFirst(
                      plan.actions.length,
                      plan.totalActions,
                    )
                  : null,
              columns: <WaxColumn<OrganizeAction>>[
                WaxColumn<OrganizeAction>(
                  label: l10n.organizeColumnFrom,
                  priority: WaxColumnPriority.primary,
                  text: (action) => action.from,
                  cell: (context, action) => Text(
                    action.from,
                    style: WaxType.monoData.copyWith(
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                WaxColumn<OrganizeAction>(
                  label: l10n.organizeColumnTo,
                  text: (action) => action.to,
                  cell: (context, action) => Text(
                    action.to,
                    style: WaxType.monoData.copyWith(color: colors.accent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// What actually happened, once it has.
class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final OrganizeReport report;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.organizeReport,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.organizeResultTitle),
          Wrap(
            spacing: WaxSpace.s12,
            runSpacing: WaxSpace.s12,
            children: <Widget>[
              StatTile(label: l10n.organizeMoved, value: '${report.moved}'),
              StatTile(label: l10n.organizeSkipped, value: '${report.skipped}'),
              StatTile(
                label: l10n.organizeFailed,
                value: '${report.failed}',
                tone: report.failed == 0 ? null : colors.error,
              ),
            ],
          ),
          if (report.failures.isNotEmpty) ...<Widget>[
            const SizedBox(height: WaxSpace.s16),
            for (final failure in report.failures)
              MonoDetailRow(label: failure.path, value: failure.reason),
          ],
        ],
      ),
    );
  }
}
