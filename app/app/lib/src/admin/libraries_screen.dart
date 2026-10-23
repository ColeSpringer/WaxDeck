import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../organize/organize_screen.dart';
import '../providers.dart';
import '../shell/pending_actions.dart';
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
          cell: (context, library) => _LibraryName(library: library),
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
          width: 132,
          text: (library) => _mediaLabel(l10n, library.media),
          cell: (context, library) {
            final held = Text(
              _mediaLabel(l10n, library.media),
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            );
            if (library.media == 'podcast') return held;
            // Changed in the server's configuration, which refuses a
            // change made here: what it holds, and why it stays.
            if (library.mediaDeclared) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  held,
                  Text(
                    l10n.adminLibraryMediaDeclared,
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              );
            }
            return _MediaChoice(library: library);
          },
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
          cell: (context, library) => libraryTakesMatching(library)
              ? _MatchingChoice(library: library)
              : const SizedBox.shrink(),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnProfile,
          width: 148,
          cell: (context, library) => library.managed
              ? _ProfileChoice(library: library)
              : Text(
                  l10n.adminLibraryProfileInPlace,
                  style: WaxType.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnReadOnly,
          width: 108,
          // Episode fetching needs the podcast library writable.
          cell: (context, library) => library.media == 'podcast'
              ? const SizedBox.shrink()
              : _LibraryFlagSwitch(
                  value: library.readOnly,
                  label: l10n.adminLibraryReadOnlyLabel(library.name),
                  semanticsId: SemanticsIds.libraryReadOnly(library.pid),
                  save: (repository, on) =>
                      repository.setLibraryReadOnly(library.pid, on),
                ),
        ),
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnFolders,
          width: 132,
          // A managed library's folders are the catalog's own rendering,
          // and an episode's names come from its feed.
          cell: (context, library) =>
              library.managed || library.media == 'podcast'
              ? const SizedBox.shrink()
              // Files already scanned take it on a rescan that re-reads
              // them, which the message says.
              : _LibraryFlagSwitch(
                  value: library.folderFallback,
                  label: l10n.adminLibraryFolderFallbackLabel(library.name),
                  semanticsId: SemanticsIds.libraryFolderFallback(library.pid),
                  save: (repository, on) =>
                      repository.setLibraryFolderFallback(library.pid, on),
                  afterSave: (messenger, on) {
                    if (!on) return;
                    messenger.show(l10n.adminLibraryFolderFallbackRescan);
                  },
                ),
        ),
        // The row's menu, a column of its own: the trailing slot holds
        // the rescan button alone. The podcast library follows the
        // podcast folder and is never removed here. Aligned, so a card's
        // row does not stretch the button across it.
        WaxColumn<LibraryInfo>(
          label: l10n.adminLibrariesColumnActions,
          width: 80,
          cell: (context, library) => library.media == 'podcast'
              ? const SizedBox.shrink()
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _LibraryMenu(library: library),
                ),
        ),
      ],
      // A rescan reads every root but the podcast library, whose episodes
      // the podcast engine catalogs.
      trailing: (context, library) => library.media == 'podcast'
          ? const SizedBox.shrink()
          : _RescanButton(library: library),
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

/// A library's name, with what the server says of it beside its policy:
/// that its configuration names it, that its folder was not there at the
/// last scan, or that it is managed and refuses the server's writes.
class _LibraryName extends StatelessWidget {
  const _LibraryName({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    Widget caption(String text, Color color) =>
        Text(text, style: WaxType.caption.copyWith(color: color));
    final captions = <Widget>[
      if (library.configured)
        caption(l10n.adminLibraryConfigured, colors.textTertiary),
      if (library.unreachable)
        caption(l10n.adminLibraryUnreachable, colors.error),
      if (library.managed && library.writable == false)
        caption(l10n.adminLibraryUnwritable, colors.error),
    ];
    final name = Text(
      library.name,
      style: WaxType.titleItem.copyWith(color: colors.textPrimary),
      overflow: TextOverflow.ellipsis,
    );
    if (captions.isEmpty) return name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[name, ...captions],
    );
  }
}

/// A library's menu: removing it, behind its name typed back. A library
/// the configuration names comes back at every start, so its row says
/// where it is removed instead.
class _LibraryMenu extends ConsumerWidget {
  const _LibraryMenu({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return WaxMenuButton<String>(
      glyph: WaxIcons.moreVertical,
      label: l10n.adminLibraryActions(library.name),
      semanticsId: SemanticsIds.libraryMenu(library.pid),
      items: <WaxMenuItem<String>>[
        WaxMenuItem<String>(
          value: 'remove',
          label: l10n.adminLibraryRemove,
          glyph: WaxIcons.delete,
          destructive: true,
          enabled: !library.configured,
          help: library.configured ? l10n.adminLibraryRemoveConfigured : null,
          semanticsId: SemanticsIds.libraryRemove(library.pid),
        ),
      ],
      onSelected: (_) => _remove(context),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final l10n = context.l10n;
    // The row is gone by the answer; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final confirmed = await showTypedConfirm(
      context,
      title: l10n.adminLibraryRemoveTitle(library.name),
      message: l10n.adminLibraryRemoveBody,
      confirmWord: library.name,
      confirmLabel: l10n.adminLibraryRemoveAction,
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.libraryRemoveConfirm,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed) return;
    try {
      await container.read(repositoryProvider).removeLibrary(library.pid);
      messenger.show(l10n.adminLibraryRemoving(library.name));
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
    }
    // A refusal for a running job proves the job list stale too.
    container
      ..invalidate(librariesProvider)
      ..invalidate(libraryCountsProvider)
      ..invalidate(adminJobsProvider)
      ..invalidate(organizeProfilesProvider);
  }
}

/// What a library holds, changed in place after saying what the change
/// does to the files already there.
class _MediaChoice extends ConsumerWidget {
  const _MediaChoice({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = switch (library.media) {
      'music' || 'audiobook' => library.media!,
      _ => 'mixed',
    };
    return WaxChoice<String>(
      label: l10n.adminLibraryMediaChoiceLabel(library.name),
      value: current,
      semanticsId: SemanticsIds.libraryMediaChoice(library.pid),
      options: const <String>['music', 'audiobook', 'mixed'],
      labelFor: (media) => _LibraryTable._mediaLabel(l10n, media),
      onChanged: (media) {
        if (media != current) _set(context, media);
      },
    );
  }

  Future<void> _set(BuildContext context, String media) async {
    final l10n = context.l10n;
    // The row can be gone by the answer; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final books = media == 'audiobook';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminLibraryMediaChange),
        content: WaxProse(
          books
              ? l10n.adminLibraryMediaToBooksBody(library.name)
              : l10n.adminLibraryMediaRereadBody(library.name),
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.adminLibraryMediaConfirm,
            semanticsId: SemanticsIds.libraryMediaConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final scanning = await container
          .read(repositoryProvider)
          .setLibraryMedia(library.pid, media);
      container
        ..invalidate(libraryCountsProvider)
        ..invalidate(librariesProvider);
      // The scan it started belongs in the job list, as a rescan's does.
      if (scanning) container.invalidate(adminJobsProvider);
      messenger.show(
        scanning
            ? l10n.adminLibraryMediaChanged(library.name)
            : books
            ? l10n.adminLibraryMediaScanWaits(library.name)
            : l10n.adminLibraryMediaScanWaitsReread(library.name),
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(explainRefusal(l10n, error));
    }
  }
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

/// The organize profile a managed library is laid out by.
class _ProfileChoice extends ConsumerWidget {
  const _ProfileChoice({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = library.profile ?? '';
    final names = <String>[
      for (final p
          in ref.watch(organizeProfilesProvider).value?.profiles ??
              const <OrganizeProfile>[])
        p.name,
    ];
    return WaxChoice<String>(
      label: l10n.adminLibraryProfileLabel(library.name),
      value: current,
      semanticsId: SemanticsIds.libraryProfile(library.pid),
      options: names.contains(current) ? names : <String>[current, ...names],
      labelFor: (name) => name,
      onChanged: names.isEmpty ? null : (name) => _set(context, ref, name),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, String name) async {
    final l10n = context.l10n;
    // The row can be gone by the answer; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    try {
      await container
          .read(repositoryProvider)
          .setLibraryProfile(library.pid, name);
      container
        ..invalidate(libraryCountsProvider)
        ..invalidate(librariesProvider);
    } on WaxDeckApiException catch (error) {
      messenger.show(explainError(l10n, error));
    }
  }
}

/// One flag the server stores per library: drawn at the value set here
/// until the reloaded listing carries it, put back where the server
/// refused it, and the listings read again once it lands.
class _LibraryFlagSwitch extends ConsumerStatefulWidget {
  const _LibraryFlagSwitch({
    required this.value,
    required this.label,
    required this.semanticsId,
    required this.save,
    this.afterSave,
  });

  /// What the listing says.
  final bool value;
  final String label;
  final String semanticsId;

  /// Stores the flag.
  final Future<void> Function(WaxDeckRepository repository, bool on) save;

  /// Run once [save] lands, for a word about what the change does.
  final void Function(ShellMessenger messenger, bool on)? afterSave;

  @override
  ConsumerState<_LibraryFlagSwitch> createState() => _LibraryFlagSwitchState();
}

class _LibraryFlagSwitchState extends ConsumerState<_LibraryFlagSwitch> {
  /// The value set here, shown until the reloaded listing carries it.
  bool? _set;

  @override
  void didUpdateWidget(covariant _LibraryFlagSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _set) _set = null;
  }

  @override
  Widget build(BuildContext context) {
    return WaxSwitch(
      label: widget.label,
      value: _set ?? widget.value,
      semanticsId: widget.semanticsId,
      onChanged: _flip,
    );
  }

  Future<void> _flip(bool on) async {
    final l10n = context.l10n;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final afterSave = widget.afterSave;
    setState(() => _set = on);
    try {
      await widget.save(container.read(repositoryProvider), on);
    } on WaxDeckApiException catch (error) {
      if (mounted) setState(() => _set = null);
      messenger.show(explainError(l10n, error));
      return;
    }
    afterSave?.call(messenger, on);
    container
      ..invalidate(libraryCountsProvider)
      ..invalidate(librariesProvider);
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
      busy:
          ref.watch(pendingActionsProvider).contains(PendingAction.scan) ||
          ref.watch(scanRunningProvider),
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
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(pendingActionsProvider.notifier).run(
      PendingAction.scan,
      () async {
        try {
          await container.read(repositoryProvider).rescanLibrary(force: force);
          container
            ..invalidate(adminJobsProvider)
            ..invalidate(librariesProvider)
            ..invalidate(libraryCountsProvider);
          messenger.show(l10n.adminLibraryScanning);
        } on WaxDeckApiException catch (error) {
          // A job already running proves the job list stale too.
          if (error.code == 'conflict') container.invalidate(adminJobsProvider);
          messenger.show(
            error.code == 'conflict'
                ? l10n.adminScanBusy
                : explainError(l10n, error),
          );
        }
      },
    );
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
          WaxProse(l10n.adminLibraryRescanBody),
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
  bool _absent = false;
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
            allowAbsent: _absent,
          );
      // The form may have gone while the create was in flight.
      if (!mounted) return;
      ref
        ..invalidate(librariesProvider)
        ..invalidate(libraryCountsProvider)
        // Organize counts the managed libraries it can lay out.
        ..invalidate(organizeProfilesProvider)
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
        _absent = false;
        _warning = created.streamingWarning;
      });
      messenger.show(
        created.scanStarted == false
            ? l10n.adminLibraryCreatedNoScan(name)
            : l10n.adminLibraryCreated(name),
      );
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
              WaxSettingRow(
                title: l10n.adminLibraryAbsentTitle,
                help: l10n.adminLibraryAbsentHelp,
                control: WaxSwitch(
                  label: l10n.adminLibraryAbsentTitle,
                  value: _absent,
                  semanticsId: SemanticsIds.libraryAbsent,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _absent = value),
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
