import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../review/review_controller.dart';
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
      identifier: 'admin-settings-section',
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
              identifier: 'setting-signup-enabled',
              child: SwitchListTile(
                key: const Key('setting-signup-enabled'),
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
              identifier: 'setting-read-only',
              child: SwitchListTile(
                key: const Key('setting-read-only'),
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
          ],
          const SizedBox(height: 8),
          const _TranscodingFields(),
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
