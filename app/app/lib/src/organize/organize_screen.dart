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
import 'organize_labels.dart';
import 'profile_editor_sheet.dart';

/// The server's file organization profiles, and how many libraries
/// they can lay out.
final organizeProfilesProvider = FutureProvider<OrganizeProfiles>(
  (ref) => ref.watch(repositoryProvider).listOrganizeProfiles(),
);

/// The organize runs the server can still undo, newest first, a page at a
/// time. Read again each time the screen opens: runs are also made from
/// Health, by other sessions, and by a request this screen left before
/// its run ended.
final organizeHistoryProvider =
    AsyncNotifierProvider.autoDispose<
      OrganizeHistoryController,
      OrganizeHistoryState
    >(OrganizeHistoryController.new, retry: retryUnlessRefused);

/// How many runs a page of the history lists.
const organizeHistoryPageSize = 50;

/// The pages of the organize history read so far.
class OrganizeHistoryState {
  const OrganizeHistoryState({
    required this.runs,
    this.nextCursor,
    this.loadingMore = false,
  });

  final List<OrganizeBatch> runs;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;
}

/// Pages the organize history, newest first: the first page as the screen
/// opens, each older one when asked for.
class OrganizeHistoryController extends AsyncNotifier<OrganizeHistoryState> {
  var _generation = 0;

  @override
  Future<OrganizeHistoryState> build() async {
    _generation++;
    final page = await ref
        .watch(repositoryProvider)
        .listOrganizeHistory(limit: organizeHistoryPageSize);
    return OrganizeHistoryState(runs: page.runs, nextCursor: page.nextCursor);
  }

  /// Appends the next, older page. A no-op while one is being read or
  /// once the oldest run is listed; a failed read keeps what is shown and
  /// throws on to the caller, which says why, and asking again retries.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(
      OrganizeHistoryState(
        runs: current.runs,
        nextCursor: current.nextCursor,
        loadingMore: true,
      ),
    );
    try {
      final page = await ref
          .read(repositoryProvider)
          .listOrganizeHistory(
            cursor: current.nextCursor,
            limit: organizeHistoryPageSize,
          );
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        OrganizeHistoryState(
          runs: [...current.runs, ...page.runs],
          nextCursor: page.nextCursor,
        ),
      );
    } on WaxDeckApiException {
      // A list read again meanwhile asked for nothing that failed.
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current);
      rethrow;
    } catch (_) {
      // A defect, not a hiccup: the paging guard is let go first, or no
      // older page could be asked for again, and the error goes on.
      if (ref.mounted && generation == _generation) state = AsyncData(current);
      rethrow;
    }
  }
}

/// Pick a profile, preview the moves, apply behind a typed confirmation:
/// this rewrites the library's on-disk layout. Every run is listed with
/// an undo while the server keeps its journal.
class OrganizeScreen extends ConsumerStatefulWidget {
  const OrganizeScreen({super.key, this.previewOnOpen = false});

  /// Dry-runs each library's own profile as the screen opens, which is
  /// where the path rule's fix sends an administrator.
  final bool previewOnOpen;

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

  /// The preview is the request in flight.
  var _previewing = false;

  @override
  void initState() {
    super.initState();
    if (widget.previewOnOpen) unawaited(_previewOnOpen());
  }

  @override
  void didUpdateWidget(OrganizeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The location asked for its dry run over the page already showing:
    // the console keeps the page, and with it this state.
    if (widget.previewOnOpen && !oldWidget.previewOnOpen) {
      unawaited(_previewOnOpen());
    }
  }

  /// Once the profiles are in: a plan made before them would read as laid
  /// out under a set that changed.
  Future<void> _previewOnOpen() async {
    final OrganizeProfiles listing;
    try {
      listing = await ref.read(organizeProfilesProvider.future);
    } on Object {
      // The screen says the listing failed, and offers its retry.
      return;
    }
    if (mounted && listing.managedLibraries > 0) await _preview('');
  }

  Future<void> _preview(String profile) async {
    if (_busy) return;
    setState(() {
      _busy = _previewing = true;
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
          // The choice moves with the plan, so Apply runs what is shown:
          // a dry run the location asked for plans each library's own
          // whatever was chosen, and one that fails changes neither.
          _profile = profile;
          _plan = plan;
          _planProfiles = under;
        });
      }
    } on WaxDeckApiException catch (e) {
      // The profile came off the server's own list rather than out of a
      // field, so the table's sentence is the right one.
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = _previewing = false);
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
      if (mounted) {
        ref.invalidate(organizeHistoryProvider);
        setState(() => _busy = _applying = false);
      }
    }
  }

  Future<void> _undo(OrganizeBatch run) async {
    if (_busy) return;
    final l10n = context.l10n;
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.organizeUndoConfirmTitle,
      message: l10n.organizeUndoConfirmMessage,
      confirmWord: l10n.organizeUndoWord,
      confirmLabel: l10n.organizeUndo,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.organizeUndoConfirm,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      final report = await ref
          .read(repositoryProvider)
          .undoOrganize(run.jobPid);
      messenger.show(l10n.organizeUndone(report.moved));
      if (mounted) {
        setState(() {
          _report = report;
          _plan = null;
        });
      }
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    } finally {
      if (mounted) {
        ref.invalidate(organizeHistoryProvider);
        setState(() => _busy = false);
      }
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
              busy: _previewing,
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
        _HistorySection(onUndo: _busy ? null : _undo),
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
          // Out of place but not moving, so not "already in place". A
          // read-only server is named only when it is the whole cause; the
          // table below counts any other, once.
          if (plan.held > 0 &&
              (plan.heldByCode['read-only'] == plan.held ||
                  plan.holds.isEmpty)) ...<Widget>[
            Text(
              plan.heldByCode['read-only'] == plan.held
                  ? l10n.organizeHeld(plan.held)
                  : l10n.organizeHeldBack(plan.held),
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
          if (plan.holds.isNotEmpty) ...<Widget>[
            const SizedBox(height: WaxSpace.s24),
            _HoldsTable(holds: plan.holds, held: plan.held, planned: true),
          ],
        ],
      ),
    );
  }
}

/// The moves the dry run holds back, each with why: the catalog's code in
/// words, and its own account under it.
class _HoldsTable extends StatelessWidget {
  const _HoldsTable({
    required this.holds,
    required this.held,
    this.planned = false,
  });

  final List<OrganizeHold> holds;
  final int held;

  /// A dry run's holds, rather than a run's.
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      identifier: SemanticsIds.organizeHolds,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.organizeHoldsTitle(held)),
          WaxTable<OrganizeHold>(
            rows: holds,
            rowId: (hold) => hold.from,
            rowSemanticsId: SemanticsIds.organizeHold,
            caption: holds.length < held
                ? l10n.organizeShowingFirst(holds.length, held)
                : null,
            columns: <WaxColumn<OrganizeHold>>[
              WaxColumn<OrganizeHold>(
                label: l10n.organizeColumnFrom,
                priority: WaxColumnPriority.primary,
                text: (hold) => hold.from,
                cell: (context, hold) => Text(
                  hold.from,
                  style: WaxType.monoData.copyWith(color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              WaxColumn<OrganizeHold>(
                label: l10n.organizeColumnWhy,
                text: (hold) =>
                    organizeHoldLabel(l10n, hold.code, planned: planned),
                cell: (context, hold) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      organizeHoldLabel(l10n, hold.code, planned: planned),
                      style: WaxType.bodySmall.copyWith(
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      hold.reason,
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
          if (report.dirsPruned > 0) ...<Widget>[
            const SizedBox(height: WaxSpace.s12),
            Text(
              l10n.organizeDirsPruned(report.dirsPruned),
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
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
          // Which files stayed, and why: for an undo, the ones moved again
          // since or no longer in the catalog.
          if (report.holds.isNotEmpty) ...<Widget>[
            const SizedBox(height: WaxSpace.s24),
            _HoldsTable(holds: report.holds, held: report.held),
          ],
        ],
      ),
    );
  }
}

/// The runs the server can still undo, each with its undo while one takes
/// it. Absent until there is a run.
class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.onUndo});

  /// Null while something else is in flight.
  final void Function(OrganizeBatch run)? onUndo;

  /// Asks for the next, older page; one that does not come says why.
  Future<void> _loadOlder(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(organizeHistoryProvider.notifier).loadMore();
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final history = ref.watch(organizeHistoryProvider);
    final List<Widget> body;
    switch (history) {
      case AsyncData(:final value) when value.runs.isNotEmpty:
        // Keyed by run, so a run arriving on top moves the rows under it
        // rather than handing each row the next run's identifier.
        body = <Widget>[
          for (final run in value.runs)
            _HistoryRow(key: ValueKey(run.jobPid), run: run, onUndo: onUndo),
          if (value.hasMore)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WaxButton(
                label: l10n.organizeHistoryMore,
                kind: WaxButtonKind.text,
                semanticsId: SemanticsIds.organizeHistoryMore,
                busy: value.loadingMore,
                onPressed: value.loadingMore
                    ? null
                    : () => unawaited(_loadOlder(context, ref)),
              ),
            ),
        ];
      case AsyncError(:final error):
        body = <Widget>[
          Text(
            context.explain(error),
            style: WaxType.bodySmall.copyWith(color: colors.error),
          ),
        ];
      default:
        return const SizedBox.shrink();
    }
    return Semantics(
      identifier: SemanticsIds.organizeHistory,
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: WaxSpace.s32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: l10n.organizeHistoryTitle,
              overline: l10n.organizeHistoryOverline,
            ),
            ...body,
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({super.key, required this.run, required this.onUndo});

  final OrganizeBatch run;
  final void Function(OrganizeBatch run)? onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final undo = onUndo;
    final when = l10n.formatStamp(run.startedAt);
    return Semantics(
      identifier: SemanticsIds.organizeHistoryRow(run.jobPid),
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                run.isUndo
                    ? l10n.organizeHistoryUndoRow(run.committed, when)
                    : l10n.organizeHistoryRow(run.committed, when),
                style: WaxType.body.copyWith(color: colors.textPrimary),
              ),
            ),
            if (run.undoable)
              WaxButton(
                label: l10n.organizeUndo,
                kind: WaxButtonKind.text,
                semanticsId: SemanticsIds.organizeUndo(run.jobPid),
                onPressed: undo == null ? null : () => undo(run),
              ),
          ],
        ),
      ),
    );
  }
}
