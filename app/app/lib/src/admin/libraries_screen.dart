import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The roots WaxDeck scans: what each holds, how it is matched, and
/// whether it may be written to.
///
/// A screen of its own rather than a band inside server settings, which
/// is where these controls lived: a library is a thing with state and
/// verbs, and it was previously three unrelated lists (a read-only
/// switch here, a matching mode on the review screen, an add form at the
/// bottom of a settings page) with no page saying what the set of
/// libraries even is.
class LibrariesScreen extends ConsumerWidget {
  const LibrariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final libraries = ref.watch(libraryCountsProvider);
    final l10n = context.l10n;
    return WaxScaffold(
      title: l10n.adminLibrariesTitle,
      largeTitle: false,
      semanticsId: SemanticsIds.adminLibraries,
      // No backSemanticsId: it would put the page's own handle on the
      // back control too, and a locator matching two elements is a
      // strict-mode failure in the suite rather than a choice between
      // them. The console's back affordance is not steered by name.
      onBack: adminBack(context),
      body: Padding(
        padding: sizeClass.gutter.add(
          const EdgeInsets.only(bottom: WaxSpace.s32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            switch (libraries) {
              AsyncData(:final value) => _LibraryTable(libraries: value),
              AsyncError(:final error) => ErrorState(
                title: l10n.adminLibrariesLoadError,
                message: context.explain(error),
                onRetry: () => ref.invalidate(libraryCountsProvider),
              ),
              _ => const SkeletonShapes(shape: SkeletonShape.list),
            },
            const SizedBox(height: WaxSpace.s32),
            const _AddLibraryForm(),
          ],
        ),
      ),
    );
  }
}

class _LibraryTable extends ConsumerWidget {
  const _LibraryTable({required this.libraries});

  final List<LibraryInfo> libraries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return WaxTable<LibraryInfo>(
      rows: libraries,
      rowId: (library) => library.pid,
      rowSemanticsId: SemanticsIds.libraryRow,
      rowDetailSemanticsId: SemanticsIds.libraryDetail,
      empty: EmptyState(
        glyph: WaxIcons.albums,
        title: l10n.adminLibrariesEmptyTitle,
        message: l10n.adminLibrariesEmptyMessage,
      ),
      columns: <WaxColumn<LibraryInfo>>[
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnName,
          priority: WaxColumnPriority.primary,
          text: (library) => library.name,
          cell: (context, library) => Text(
            library.name,
            style: WaxType.titleItem.copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnPath,
          text: (library) => library.path ?? '',
          cell: (context, library) => Text(
            library.path ?? l10n.adminLibraryUnnamedPath,
            style: WaxType.monoData.copyWith(color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnHolds,
          width: 96,
          text: (library) => _mediaLabel(l10n, library.media),
          cell: (context, library) => Text(
            _mediaLabel(l10n, library.media),
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnItems,
          width: 80,
          numeric: true,
          text: (library) => '${library.itemCount ?? 0}',
          cell: (context, library) => Text(
            '${library.itemCount ?? 0}',
            style: WaxType.monoData.copyWith(color: colors.textSecondary),
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnMatching,
          width: 148,
          cell: (context, library) => _MatchingChoice(library: library),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnReadOnly,
          width: 108,
          cell: (context, library) => _ReadOnlySwitch(library: library),
        ),
      ],
      trailing: (context, library) => _RescanButton(library: library),
    );
  }

  static String _mediaLabel(AppLocalizations l10n, String? media) =>
      switch (media) {
        'music' => l10n.adminLibraryMediaMusic,
        'audiobook' => l10n.adminLibraryMediaBooks,
        'podcast' => l10n.adminLibraryMediaPodcasts,
        _ => l10n.adminLibraryMediaMixed,
      };
}

/// What the matching engine does with what this root holds.
class _MatchingChoice extends ConsumerWidget {
  const _MatchingChoice({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matching = ref.watch(libraryMatchingProvider(library.pid));
    final l10n = context.l10n;
    return WaxChoice<String>(
      label: l10n.adminLibraryMatchingLabel(library.name),
      value: matching.value?.mode ?? 'auto',
      semanticsId: SemanticsIds.libraryMatching(library.pid),
      options: const <String>['auto', 'review', 'off'],
      labelFor: (mode) => _matchingLabel(l10n, mode),
      onChanged: matching.value == null
          ? null
          : (value) => _set(context, ref, value),
    );
  }

  /// The modes in the words an administrator decides in, not the
  /// contract's. "off" is not "no matching happens" but "this collection
  /// is already curated, leave it as it is".
  static String _matchingLabel(AppLocalizations l10n, String mode) =>
      switch (mode) {
        'review' => l10n.adminLibraryMatchingAsk,
        'off' => l10n.adminLibraryMatchingLeave,
        _ => l10n.adminLibraryMatchingAuto,
      };

  Future<void> _set(BuildContext context, WidgetRef ref, String mode) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(libraryMatchingProvider(library.pid).notifier)
          .setMode(mode);
    } on WaxDeckApiException catch (error) {
      ref.read(shellMessengerProvider.notifier).show(explainError(l10n, error));
    }
  }
}

class _ReadOnlySwitch extends ConsumerWidget {
  const _ReadOnlySwitch({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(libraryReadOnlyProvider(library.pid));
    return WaxSwitch(
      label: context.l10n.adminLibraryReadOnlyLabel(library.name),
      value: readOnly.value ?? false,
      semanticsId: SemanticsIds.libraryReadOnly(library.pid),
      onChanged: readOnly.value == null
          ? null
          : (value) => _set(context, ref, value),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool readOnly) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(libraryReadOnlyProvider(library.pid).notifier)
          .set(readOnly);
    } on WaxDeckApiException catch (error) {
      ref.read(shellMessengerProvider.notifier).show(explainError(l10n, error));
    }
  }
}

/// Rescans every root, not just this one: the contract has one scan
/// verb. The button sits on the row because that is where somebody looks
/// for it, and the message says what actually happened.
class _RescanButton extends ConsumerWidget {
  const _RescanButton({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WaxIconButton(
      glyph: WaxIcons.refresh,
      label: context.l10n.adminLibraryRescan,
      semanticsId: SemanticsIds.libraryRescan(library.pid),
      onPressed: () => _rescan(context, ref),
    );
  }

  Future<void> _rescan(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    // Confirmed first, because the button sits on one row and the scan
    // covers everything; the dialog is also where the repair pass
    // lives. The dashboard's quick action stays plain - it never
    // pretended to be about one library.
    final force = await showDialog<bool>(
      context: context,
      builder: (_) => const _RescanDialog(),
    );
    if (force == null || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).rescanLibrary(force: force);
      ref
        ..invalidate(adminJobsProvider)
        ..invalidate(librariesProvider)
        ..invalidate(libraryCountsProvider);
      messenger.show(l10n.adminLibraryScanning);
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
    }
  }
}

/// The rescan confirm: says the scan covers every root, and carries
/// the force option. Pops the chosen force flag, or null on cancel.
class _RescanDialog extends StatefulWidget {
  const _RescanDialog();

  @override
  State<_RescanDialog> createState() => _RescanDialogState();
}

class _RescanDialogState extends State<_RescanDialog> {
  var _force = false;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: colors.surface2,
      title: Text(l10n.adminLibraryRescan),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.adminLibraryRescanBody),
          const SizedBox(height: WaxSpace.s12),
          WaxSettingRow(
            title: l10n.adminLibraryRescanForce,
            help: l10n.adminLibraryRescanForceHelp,
            control: WaxSwitch(
              value: _force,
              label: l10n.adminLibraryRescanForce,
              semanticsId: SemanticsIds.libraryRescanForce,
              onChanged: (value) => setState(() => _force = value),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.adminLibraryRescanStart,
          semanticsId: SemanticsIds.libraryRescanConfirm,
          onPressed: () => Navigator.of(context).pop(_force),
        ),
      ],
    );
  }
}

/// Registers a root at runtime. The catalog scans it in the background,
/// so browsing and downloading work once it is indexed; streaming needs
/// the WaxFlow sidecar to mount the same-named root, and the create
/// reports when it could not be brought to it.
class _AddLibraryForm extends ConsumerStatefulWidget {
  const _AddLibraryForm();

  @override
  ConsumerState<_AddLibraryForm> createState() => _AddLibraryFormState();
}

class _AddLibraryFormState extends ConsumerState<_AddLibraryForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _path = TextEditingController();
  String _media = 'mixed';
  bool _managed = false;
  bool _busy = false;

  /// What the last create said about streaming, kept on screen until the
  /// next one. A snackbar would carry it for four seconds, and this is a
  /// sentence about a thing that is now permanently half-working.
  String? _warning;

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider.notifier);
    final name = _name.text.trim();
    final path = _path.text.trim();
    if (name.isEmpty || path.isEmpty) {
      messenger.show(l10n.adminLibraryNamePathRequired);
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(repositoryProvider)
          .createLibrary(
            name: name,
            path: path,
            media: _media,
            managed: _managed,
          );
      // The form may have gone while the create was in flight.
      if (!mounted) return;
      ref
        ..invalidate(librariesProvider)
        ..invalidate(libraryCountsProvider)
        // The create starts a scan of the new root server-side, so the
        // job list is stale the moment it returns - the same three the
        // rescan button invalidates, for the same reason. Left out, the
        // first-run wizard reads an empty job list, offers a scan that
        // is already running, and takes the server's refusal as the
        // answer with nothing left to refresh it.
        ..invalidate(adminJobsProvider);
      _name.clear();
      _path.clear();
      setState(() {
        _media = 'mixed';
        _managed = false;
        _warning = created.streamingWarning;
      });
      messenger.show(l10n.adminLibraryCreated(name));
    } on WaxDeckApiException catch (error) {
      // The path somebody just typed: the server names the root that
      // already covers it, which a translated conflict cannot.
      messenger.show(explainRefusal(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.adminLibraryAddGroup),
        if (_warning != null)
          Padding(
            padding: const EdgeInsets.only(bottom: WaxSpace.s12),
            child: WaxBanner(
              message: _warning!,
              tone: WaxBannerTone.caution,
              semanticsId: SemanticsIds.libraryWarning,
              onDismiss: () => setState(() => _warning = null),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaxTextField(
                label: l10n.adminLibraryNameLabel,
                hint: l10n.adminLibraryNameHint,
                controller: _name,
                semanticsId: SemanticsIds.libraryName,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: l10n.adminLibraryPathLabel,
                hint: l10n.adminLibraryPathHint,
                controller: _path,
                semanticsId: SemanticsIds.libraryPath,
              ),
              const SizedBox(height: WaxSpace.s16),
              WaxSettingRow(
                title: l10n.adminLibraryHoldsTitle,
                help: l10n.adminLibraryHoldsHelp,
                control: WaxChoice<String>(
                  label: l10n.adminLibraryContentClass,
                  value: _media,
                  semanticsId: SemanticsIds.libraryMedia,
                  options: const <String>['mixed', 'music', 'audiobook'],
                  labelFor: (media) => _LibraryTable._mediaLabel(l10n, media),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _media = value),
                ),
              ),
              WaxSettingRow(
                title: l10n.adminLibraryManagedTitle,
                help: l10n.adminLibraryManagedHelp,
                control: WaxSwitch(
                  label: l10n.adminLibraryManagedTitle,
                  value: _managed,
                  semanticsId: SemanticsIds.libraryManaged,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _managed = value),
                ),
              ),
              const SizedBox(height: WaxSpace.s16),
              WaxButton(
                label: l10n.adminLibraryCreate,
                icon: WaxIcons.add,
                semanticsId: SemanticsIds.librarySubmit,
                onPressed: _busy ? null : _create,
              ),
              const SizedBox(height: WaxSpace.s8),
              Text(
                l10n.adminLibraryPathRule,
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
