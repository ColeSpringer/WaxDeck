import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../review/review_controller.dart';
import '../shell/semantics_ids.dart';
import 'admin_providers.dart';

/// Server-wide switches on the settings screen: signup, read-only mode,
/// transcoding limits, and per-library read-only flags. Administrators
/// only; the settings screen gates its inclusion.
class ServerSettingsSection extends ConsumerWidget {
  const ServerSettingsSection({super.key});

  Future<void> _saveSettings(
    BuildContext context,
    WidgetRef ref,
    AdminSettings settings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminSettingsProvider.notifier).save(settings);
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final settings = ref.watch(adminSettingsProvider).value;
    final libraries = ref.watch(librariesProvider).value ?? const [];
    return Semantics(
      identifier: SemanticsIds.adminSettingsSection,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          if (settings == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Semantics(
              identifier: SemanticsIds.settingSignupEnabled,
              child: SwitchListTile(
                key: const Key(SemanticsIds.settingSignupEnabled),
                title: const Text('Open signup'),
                subtitle: const Text(
                  'Anyone may request an account; requests await approval',
                ),
                value: settings.signupEnabled,
                onChanged: (value) => _saveSettings(
                  context,
                  ref,
                  settings.copyWith(signupEnabled: value),
                ),
              ),
            ),
            Semantics(
              identifier: SemanticsIds.settingReadOnly,
              child: SwitchListTile(
                key: const Key(SemanticsIds.settingReadOnly),
                title: const Text('Read-only mode'),
                subtitle: const Text(
                  'Refuse every change to library content, server-wide',
                ),
                value: settings.readOnly,
                onChanged: (value) => _saveSettings(
                  context,
                  ref,
                  settings.copyWith(readOnly: value),
                ),
              ),
            ),
            Semantics(
              identifier: SemanticsIds.settingSonicAnalysis,
              child: SwitchListTile(
                key: const Key(SemanticsIds.settingSonicAnalysis),
                title: const Text('Sonic analysis'),
                subtitle: const Text(
                  'Analyze the library in the background for instant '
                  'mixes, similar tracks, and sonic paths',
                ),
                value: settings.sonicAnalysis,
                onChanged: (value) => _saveSettings(
                  context,
                  ref,
                  settings.copyWith(sonicAnalysis: value),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const _TranscodingFields(),
          const SizedBox(height: 8),
          const _TrashRetentionField(),
          const SizedBox(height: 8),
          const _AddLibraryField(),
          if (libraries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Library read-only', style: textTheme.titleSmall),
            for (final library in libraries)
              _LibraryReadOnlyRow(library: library),
          ],
        ],
      ),
    );
  }
}

class _TranscodingFields extends ConsumerStatefulWidget {
  const _TranscodingFields();

  @override
  ConsumerState<_TranscodingFields> createState() => _TranscodingFieldsState();
}

class _TranscodingFieldsState extends ConsumerState<_TranscodingFields> {
  final _maxConcurrent = TextEditingController();
  final _maxPerUser = TextEditingController();
  final _defaultKbps = TextEditingController();
  var _seeded = false;
  var _busy = false;

  @override
  void dispose() {
    _maxConcurrent.dispose();
    _maxPerUser.dispose();
    _defaultKbps.dispose();
    super.dispose();
  }

  void _seed(TranscodingLimits limits) {
    if (_seeded) return;
    _seeded = true;
    _maxConcurrent.text = '${limits.maxConcurrent}';
    _maxPerUser.text = '${limits.maxConcurrentPerUser}';
    _defaultKbps.text = '${limits.defaultMaxBitrateKbps}';
  }

  Future<void> _save(TranscodingLimits current) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(transcodingLimitsProvider.notifier)
          .save(
            TranscodingLimits(
              maxConcurrent:
                  int.tryParse(_maxConcurrent.text.trim()) ??
                  current.maxConcurrent,
              maxConcurrentPerUser:
                  int.tryParse(_maxPerUser.text.trim()) ??
                  current.maxConcurrentPerUser,
              defaultMaxBitrateKbps:
                  int.tryParse(_defaultKbps.text.trim()) ??
                  current.defaultMaxBitrateKbps,
            ),
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Transcoding limits saved')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final limits = ref.watch(transcodingLimitsProvider).value;
    if (limits == null) return const SizedBox.shrink();
    _seed(limits);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transcoding', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        TextField(
          key: const Key('transcoding-max-concurrent'),
          controller: _maxConcurrent,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Max concurrent transcodes',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('transcoding-max-per-user'),
          controller: _maxPerUser,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Max per user'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('transcoding-default-kbps'),
          controller: _defaultKbps,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Default max bitrate (kbps)',
            helperText: '0 means unlimited',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('transcoding-save'),
          onPressed: _busy ? null : () => _save(limits),
          child: const Text('Save transcoding limits'),
        ),
      ],
    );
  }
}

class _TrashRetentionField extends ConsumerStatefulWidget {
  const _TrashRetentionField();

  @override
  ConsumerState<_TrashRetentionField> createState() =>
      _TrashRetentionFieldState();
}

class _TrashRetentionFieldState extends ConsumerState<_TrashRetentionField> {
  final _days = TextEditingController();
  var _seeded = false;
  var _busy = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _save(AdminSettings current) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    // Reject non-numeric or negative input outright rather than silently
    // falling back to the stored value and still reporting success.
    final parsed = int.tryParse(_days.text.trim());
    if (parsed == null || parsed < 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter a whole number of days (0 disables retention)'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminSettingsProvider.notifier)
          .save(current.copyWith(trashRetentionDays: parsed));
      // Reflect what was saved so the field never disagrees with stored
      // state (e.g. a padded "007" shows back as "7").
      _days.text = '$parsed';
      messenger.showSnackBar(
        const SnackBar(content: Text('Trash retention saved')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(adminSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    if (!_seeded) {
      _seeded = true;
      _days.text = '${settings.trashRetentionDays}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trash', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        TextField(
          key: const Key('trash-retention-days'),
          controller: _days,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Auto-purge trashed files after (days)',
            helperText: '0 keeps trashed files until emptied by hand',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('trash-retention-save'),
          onPressed: _busy ? null : () => _save(settings),
          child: const Text('Save trash retention'),
        ),
      ],
    );
  }
}

/// Registers a new library root at runtime. The catalog scans it in the
/// background, so browsing and downloading its files work once indexed;
/// streaming through the WaxFlow sidecar additionally needs the sidecar to
/// mount the same-named root.
class _AddLibraryField extends ConsumerStatefulWidget {
  const _AddLibraryField();

  @override
  ConsumerState<_AddLibraryField> createState() => _AddLibraryFieldState();
}

class _AddLibraryFieldState extends ConsumerState<_AddLibraryField> {
  final _name = TextEditingController();
  final _path = TextEditingController();
  String _media = 'mixed';
  bool _managed = false;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    final path = _path.text.trim();
    if (name.isEmpty || path.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A name and an absolute path are required'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .createLibrary(
            name: name,
            path: path,
            media: _media,
            managed: _managed,
          );
      // The widget may have been disposed while the create was in flight;
      // touching ref or setState after that throws.
      if (!mounted) return;
      // Refresh the library list so the new root shows in the read-only
      // section and everywhere else the list feeds.
      ref.invalidate(librariesProvider);
      _name.clear();
      _path.clear();
      setState(() {
        _media = 'mixed';
        _managed = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Library "$name" created; scanning started')),
      );
    } on WaxDeckApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add library', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        TextField(
          key: const Key('add-library-name'),
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'Also the WaxFlow root name serving this directory',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('add-library-path'),
          controller: _path,
          decoration: const InputDecoration(
            labelText: 'Absolute path on the server',
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('add-library-media'),
          initialValue: _media,
          decoration: const InputDecoration(labelText: 'Content'),
          items: const [
            DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
            DropdownMenuItem(value: 'music', child: Text('Music')),
            DropdownMenuItem(value: 'audiobook', child: Text('Audiobooks')),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _media = value ?? 'mixed'),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const Key('add-library-managed'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Catalog-managed'),
          subtitle: const Text(
            'Let uploads and organizing place files in this root',
          ),
          value: _managed,
          onChanged: _busy ? null : (value) => setState(() => _managed = value),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('add-library-create'),
          onPressed: _busy ? null : _create,
          child: const Text('Create library'),
        ),
      ],
    );
  }
}

class _LibraryReadOnlyRow extends ConsumerWidget {
  const _LibraryReadOnlyRow({required this.library});

  final LibraryInfo library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(libraryReadOnlyProvider(library.pid));
    final messenger = ScaffoldMessenger.of(context);
    return SwitchListTile(
      key: Key('library-read-only-${library.pid}'),
      title: Text(library.name),
      subtitle: const Text('Read-only'),
      value: readOnly.value ?? false,
      onChanged: readOnly.value == null
          ? null
          : (value) async {
              try {
                await ref
                    .read(libraryReadOnlyProvider(library.pid).notifier)
                    .set(value);
              } on WaxDeckApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
    );
  }
}
