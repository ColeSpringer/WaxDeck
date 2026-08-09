import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

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
    return WaxScaffold(
      title: 'Libraries',
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
                title: 'Could not load the libraries',
                message: error is WaxDeckApiException
                    ? error.message
                    : 'Something went wrong reading them.',
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
    return WaxTable<LibraryInfo>(
      rows: libraries,
      rowId: (library) => library.pid,
      rowSemanticsId: SemanticsIds.libraryRow,
      rowDetailSemanticsId: SemanticsIds.libraryDetail,
      empty: const EmptyState(
        glyph: WaxIcons.albums,
        title: 'No libraries yet',
        message: 'Add a root below and WaxDeck scans what is in it.',
      ),
      columns: <WaxColumn<LibraryInfo>>[
        WaxColumn<LibraryInfo>(
          label: 'Name',
          priority: WaxColumnPriority.primary,
          text: (library) => library.name,
          cell: (context, library) => Text(
            library.name,
            style: WaxType.titleItem.copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: 'Path',
          text: (library) => library.path ?? '',
          cell: (context, library) => Text(
            library.path ?? 'unnamed on this filesystem',
            style: WaxType.monoData.copyWith(color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: 'Holds',
          width: 96,
          text: (library) => library.media ?? 'mixed',
          cell: (context, library) => Text(
            _mediaLabel(library.media),
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: 'Items',
          width: 80,
          numeric: true,
          text: (library) => '${library.itemCount ?? 0}',
          cell: (context, library) => Text(
            '${library.itemCount ?? 0}',
            style: WaxType.monoData.copyWith(color: colors.textSecondary),
          ),
        ),
        WaxColumn<LibraryInfo>(
          label: 'Matching',
          width: 148,
          cell: (context, library) => _MatchingChoice(library: library),
        ),
        WaxColumn<LibraryInfo>(
          label: 'Read-only',
          width: 108,
          cell: (context, library) => _ReadOnlySwitch(library: library),
        ),
      ],
      trailing: (context, library) => _RescanButton(library: library),
    );
  }

  static String _mediaLabel(String? media) => switch (media) {
    'music' => 'Music',
    'audiobook' => 'Books',
    'podcast' => 'Podcasts',
    _ => 'Mixed',
  };
}

/// What the matching engine does with what this root holds.
class _MatchingChoice extends ConsumerWidget {
  const _MatchingChoice({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryMatchingProvider(library.pid));
    return WaxChoice<String>(
      label: 'Matching for ${library.name}',
      value: mode.value ?? 'auto',
      semanticsId: SemanticsIds.libraryMatching(library.pid),
      options: const <String>['auto', 'review', 'off'],
      labelFor: _matchingLabel,
      onChanged: mode.value == null ? null : (value) => _set(ref, value),
    );
  }

  /// The modes in the words an administrator decides in, not the
  /// contract's. "off" is not "no matching happens" but "this collection
  /// is already curated, leave it as it is".
  static String _matchingLabel(String mode) => switch (mode) {
    'review' => 'Ask me',
    'off' => 'Leave alone',
    _ => 'Automatic',
  };

  Future<void> _set(WidgetRef ref, String mode) async {
    try {
      await ref.read(libraryMatchingProvider(library.pid).notifier).set(mode);
    } on WaxDeckApiException catch (error) {
      ref.read(shellMessengerProvider.notifier).show(error.message);
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
      label: 'Read-only: ${library.name}',
      value: readOnly.value ?? false,
      semanticsId: SemanticsIds.libraryReadOnly(library.pid),
      onChanged: readOnly.value == null ? null : (value) => _set(ref, value),
    );
  }

  Future<void> _set(WidgetRef ref, bool readOnly) async {
    try {
      await ref
          .read(libraryReadOnlyProvider(library.pid).notifier)
          .set(readOnly);
    } on WaxDeckApiException catch (error) {
      ref.read(shellMessengerProvider.notifier).show(error.message);
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
      label: 'Rescan libraries',
      semanticsId: SemanticsIds.libraryRescan(library.pid),
      onPressed: () => _rescan(ref),
    );
  }

  Future<void> _rescan(WidgetRef ref) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(repositoryProvider).rescanLibrary();
      ref
        ..invalidate(adminJobsProvider)
        ..invalidate(librariesProvider)
        ..invalidate(libraryCountsProvider);
      messenger.show('Scanning every library root');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    }
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
    final messenger = ref.read(shellMessengerProvider.notifier);
    final name = _name.text.trim();
    final path = _path.text.trim();
    if (name.isEmpty || path.isEmpty) {
      messenger.show('A name and an absolute path are required');
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
      messenger.show('Library "$name" created; scanning started');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Add a library'),
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
                label: 'Name',
                hint: 'Also the WaxFlow root name serving this directory',
                controller: _name,
                semanticsId: SemanticsIds.libraryName,
              ),
              const SizedBox(height: WaxSpace.s12),
              WaxTextField(
                label: 'Absolute path on the server',
                hint: '/srv/media/music',
                controller: _path,
                semanticsId: SemanticsIds.libraryPath,
              ),
              const SizedBox(height: WaxSpace.s16),
              WaxSettingRow(
                title: 'Holds',
                help: 'What kind of content the root carries',
                control: WaxChoice<String>(
                  label: 'Content class',
                  value: _media,
                  semanticsId: SemanticsIds.libraryMedia,
                  options: const <String>['mixed', 'music', 'audiobook'],
                  labelFor: _LibraryTable._mediaLabel,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _media = value),
                ),
              ),
              WaxSettingRow(
                title: 'Catalog-managed',
                help: 'Let uploads and organizing place files in this root',
                control: WaxSwitch(
                  label: 'Catalog-managed',
                  value: _managed,
                  semanticsId: SemanticsIds.libraryManaged,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _managed = value),
                ),
              ),
              const SizedBox(height: WaxSpace.s16),
              WaxButton(
                label: 'Create library',
                icon: WaxIcons.add,
                semanticsId: SemanticsIds.librarySubmit,
                onPressed: _busy ? null : _create,
              ),
              const SizedBox(height: WaxSpace.s8),
              Text(
                'The path must be absolute, and must not overlap an existing '
                'root, the upload inbox, or the podcast download directory.',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
