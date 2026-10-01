import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_console.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'profile_editor_sheet.dart';

/// The server's file organization profiles, and how many libraries
/// they can lay out.
final organizeProfilesProvider = FutureProvider<OrganizeProfiles>(
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
  /// The chosen profile; empty lays out each library by its own.
  var _profile = '';
  OrganizePlan? _plan;

  /// The profiles the plan was laid out under: once they change, Apply
  /// would not do what it shows.
  String? _planProfiles;
  OrganizeReport? _report;
  var _busy = false;

  /// The apply is the request in flight, not the preview.
  var _applying = false;

  Future<void> _preview(String profile) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _report = null;
    });
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final under = _profilesKey(ref.read(organizeProfilesProvider).value);
    try {
      final plan = await ref
          .read(repositoryProvider)
          .previewOrganize(profile: profile.isEmpty ? null : profile);
      if (mounted) {
        setState(() {
          _plan = plan;
          _planProfiles = under;
        });
      }
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
      confirmWord: profile.isEmpty ? l10n.organizeConfirmOwnWord : profile,
      confirmLabel: l10n.organizeApply,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.organizeConfirm,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = _applying = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final report = await ref
          .read(repositoryProvider)
          .applyOrganize(profile: profile.isEmpty ? null : profile);
      if (mounted) {
        setState(() {
          _report = report;
          _plan = null;
        });
      }
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = _applying = false);
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

  static String _profilesKey(OrganizeProfiles? listing) => jsonEncode([
    for (final p in listing?.profiles ?? const <OrganizeProfile>[])
      [
        p.name,
        p.musicTemplate,
        p.audiobookTemplate,
        p.podcastTemplate,
        p.tagWrite,
      ],
  ]);

  Widget _body(BuildContext context, OrganizeProfiles listing) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final profiles = listing.profiles;
    if (profiles.isEmpty) {
      return EmptyState(
        glyph: WaxIcons.sort,
        title: l10n.organizeEmptyTitle,
        message: l10n.organizeEmptyMessage,
      );
    }
    // The catalog lays out managed roots only, so with none a preview
    // could only be refused.
    if (listing.managedLibraries == 0) {
      return EmptyState(
        glyph: WaxIcons.sort,
        title: l10n.organizeNoManagedTitle,
        message: l10n.organizeNoManagedMessage,
      );
    }
    // A profile deleted since it was chosen falls back to each library's.
    final chosen = profiles.where((p) => p.name == _profile).firstOrNull;
    final profile = chosen?.name ?? '';
    final stale =
        (_profile.isNotEmpty && chosen == null) ||
        _planProfiles != _profilesKey(listing);
    final plan = stale ? null : _plan;
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.organizeProfileTitle,
          overline: l10n.organizeProfileOverline,
        ),
        Semantics(
          container: true,
          label: l10n.organizeProfileLabel,
          child: WaxRadioGroup<String>(
            value: profile,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _profile = value;
                    _plan = null;
                    _report = null;
                  }),
            options: <WaxRadioOption<String>>[
              WaxRadioOption(
                value: '',
                label: l10n.organizeOwnProfiles,
                help: l10n.organizeOwnProfilesHelp,
                semanticsId: SemanticsIds.organizeProfileOwn,
              ),
              for (final p in profiles)
                WaxRadioOption(
                  value: p.name,
                  label: p.builtIn
                      ? l10n.organizeBuiltInProfile(p.name)
                      : p.name,
                  help: p.sample.music.isEmpty ? null : p.sample.music,
                  semanticsId: SemanticsIds.organizeProfileOption(p.name),
                ),
            ],
          ),
        ),
        const SizedBox(height: WaxSpace.s8),
        Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[
            WaxButton(
              label: l10n.organizeProfileNew,
              kind: WaxButtonKind.text,
              icon: WaxIcons.add,
              semanticsId: SemanticsIds.organizeProfileNew,
              onPressed: _busy
                  ? null
                  : () => unawaited(showOrganizeProfileEditor(context)),
            ),
            if (chosen != null)
              WaxButton(
                label: l10n.organizeProfileEdit,
                kind: WaxButtonKind.text,
                icon: WaxIcons.edit,
                semanticsId: SemanticsIds.organizeProfileEdit(chosen.name),
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        showOrganizeProfileEditor(context, profile: chosen),
                      ),
              ),
          ],
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
              busy: _applying,
              // No plan, no apply: a run without one rewrites the
              // library on trust.
              onPressed: _busy || plan == null ? null : () => _apply(profile),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        if (plan != null)
          _PlanTable(
            plan: plan,
            onDiscard: _busy ? null : () => setState(() => _plan = null),
          )
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
  const _PlanTable({required this.plan, required this.onDiscard});

  final OrganizePlan plan;
  final VoidCallback? onDiscard;

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
            actionLabel: l10n.organizeDiscard,
            onAction: onDiscard,
            semanticsId: SemanticsIds.organizeDiscard,
          ),
          // Out of place but not moving, so not "already in place".
          if (plan.held > 0) ...<Widget>[
            Text(
              l10n.organizeHeld(plan.held),
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WaxSpace.s12),
          ],
          if (plan.readOnlyLibraries > 0) ...<Widget>[
            Text(
              l10n.organizeReadOnlyLibraries(plan.readOnlyLibraries),
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WaxSpace.s12),
          ],
          if (plan.actions.isEmpty && plan.held == 0)
            EmptyState(
              glyph: WaxIcons.success,
              title: l10n.organizeNothingTitle,
              message: l10n.organizeNothingMessage,
            )
          else if (plan.actions.isNotEmpty)
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
              if (report.held > 0)
                StatTile(label: l10n.organizeHeldTile, value: '${report.held}'),
              StatTile(
                label: l10n.organizeFailed,
                value: '${report.failed}',
                tone: report.failed == 0 ? null : colors.error,
              ),
            ],
          ),
          if (report.readOnlyLibraries > 0) ...<Widget>[
            const SizedBox(height: WaxSpace.s12),
            Text(
              l10n.organizeReadOnlyLibraries(report.readOnlyLibraries),
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
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
