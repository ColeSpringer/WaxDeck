import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final plan = await ref
          .read(repositoryProvider)
          .previewOrganize(profile: profile);
      if (mounted) setState(() => _plan = plan);
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(String profile) async {
    if (_busy) return;
    final confirmed = await showTypedConfirm(
      context,
      title: 'Apply organize profile?',
      message:
          'Files move to their new locations on the server. The catalog '
          'follows them, but anything else pointing at the old paths does '
          'not.',
      confirmWord: profile,
      confirmLabel: 'Apply',
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
      messenger.show(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final profiles = ref.watch(organizeProfilesProvider);
    return WaxScaffold(
      title: 'Organize files',
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
            title: 'Could not load organize profiles',
            message: error is WaxDeckApiException
                ? error.message
                : 'The server did not answer.',
            onRetry: () => ref.invalidate(organizeProfilesProvider),
          ),
          _ => const SkeletonShapes(shape: SkeletonShape.list),
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<OrganizeProfile> profiles) {
    final colors = WaxColors.of(context);
    if (profiles.isEmpty) {
      return const EmptyState(
        glyph: WaxIcons.sort,
        title: 'No organize profiles',
        message:
            'Profiles are part of the server configuration. Add one there '
            'and it appears here.',
      );
    }
    final profile = _profile ?? profiles.first.name;
    final plan = _plan;
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Profile',
          overline: 'The naming scheme to move into',
        ),
        WaxChoice<String>(
          label: 'Organize profile',
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
              label: 'Preview',
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.search,
              semanticsId: SemanticsIds.organizePreview,
              onPressed: _busy ? null : () => _preview(profile),
            ),
            const SizedBox(width: WaxSpace.s8),
            WaxButton(
              label: 'Apply',
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
            'Preview shows where the selected profile would move files '
            'before anything happens.',
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
    return Semantics(
      identifier: SemanticsIds.organizePlan,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title:
                '${plan.totalActions} planned '
                '${plan.totalActions == 1 ? 'move' : 'moves'}',
            overline: plan.tagWrite ? 'Tags are rewritten too' : null,
          ),
          if (plan.actions.isEmpty)
            const EmptyState(
              glyph: WaxIcons.success,
              title: 'Everything is already in place',
              message: 'This profile would move nothing.',
            )
          else
            WaxTable<OrganizeAction>(
              rows: plan.actions,
              rowId: (action) => action.from,
              rowSemanticsId: SemanticsIds.organizeRow,
              rowDetailSemanticsId: SemanticsIds.organizeRowDetail,
              caption: plan.actions.length < plan.totalActions
                  ? 'Showing the first ${plan.actions.length} of '
                        '${plan.totalActions}'
                  : null,
              columns: <WaxColumn<OrganizeAction>>[
                WaxColumn<OrganizeAction>(
                  label: 'Now at',
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
                  label: 'Moves to',
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
    return Semantics(
      identifier: SemanticsIds.organizeReport,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Result'),
          Wrap(
            spacing: WaxSpace.s12,
            runSpacing: WaxSpace.s12,
            children: <Widget>[
              StatTile(label: 'Moved', value: '${report.moved}'),
              StatTile(label: 'Skipped', value: '${report.skipped}'),
              StatTile(
                label: 'Failed',
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
