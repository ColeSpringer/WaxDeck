import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'metadata_controller.dart';

/// The per-item metadata editor: a scalar-field form built from the
/// server's vocabulary, credits, custom tags, lyrics, release status,
/// and the rematch and enrichment actions. Deep-linkable at
/// `/metadata/<pid>` for tools and tests.
class MetadataScreen extends ConsumerStatefulWidget {
  const MetadataScreen({super.key, required this.pid});

  static const routePrefix = '/metadata/';

  static String routeFor(String pid) => '$routePrefix$pid';

  final String pid;

  @override
  ConsumerState<MetadataScreen> createState() => _MetadataScreenState();
}

class _MetadataScreenState extends ConsumerState<MetadataScreen> {
  final _fieldControllers = <String, TextEditingController>{};
  final _lyricsController = TextEditingController();
  final _creditNamesController = TextEditingController();
  final _tagKeyController = TextEditingController();
  final _tagValuesController = TextEditingController();
  String? _creditRole;
  var _lyricsSeeded = false;

  var _writeBack = false;
  var _lock = true;
  var _force = false;
  var _busy = false;

  /// Write-back failures from the last save, rendered as a warning
  /// list; a partial tag write is not an error.
  List<WriteBackFailure> _writeBackFailures = const [];

  @override
  void dispose() {
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    _lyricsController.dispose();
    _creditNamesController.dispose();
    _tagKeyController.dispose();
    _tagValuesController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String field, String initial) {
    return _fieldControllers.putIfAbsent(field, () {
      final controller = TextEditingController(text: initial);
      // Recompute dirtiness (and the Save button) as the user types.
      controller.addListener(() => setState(() {}));
      return controller;
    });
  }

  Map<String, String> _changedFields(MetadataEditorState state) {
    final changed = <String, String>{};
    for (final field in state.kindFields.fields) {
      final controller = _fieldControllers[field.name];
      if (controller == null) continue;
      final stored = state.metadata.fields[field.name] ?? '';
      if (controller.text != stored) changed[field.name] = controller.text;
    }
    return changed;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on WaxDeckApiException catch (e) {
      final hint = e.statusCode == 409
          ? ' Check "Force" to overwrite locked fields.'
          : '';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${e.message}.$hint')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showResult(MetadataEditResult result) {
    if (!mounted) return;
    setState(() => _writeBackFailures = result.writeBackFailures);
    if (result.warnings.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.warnings.join('\n'))));
    }
  }

  Future<void> _save(MetadataEditorState state) => _run(() async {
    final changed = _changedFields(state);
    if (changed.isEmpty) return;
    final result = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .saveFields(changed, writeBack: _writeBack, lock: _lock, force: _force);
    _showResult(result);
  });

  Future<void> _rematch() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    final entryId = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .rematch();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Queued for identification ($entryId)')),
      );
  });

  static List<String> _wantsFor(MediaType mediaType) => switch (mediaType) {
    MediaType.music => const ['cover', 'genres'],
    MediaType.audiobook => const ['cover', 'book'],
    MediaType.podcast => const ['cover'],
  };

  Future<void> _enrich(MetadataEditorState state) => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(metadataControllerProvider(widget.pid).notifier)
        .enrich(_wantsFor(state.metadata.mediaType));
    final parts = [
      if (result.applied.isNotEmpty) 'Applied: ${result.applied.join(', ')}',
      if (result.skipped.isNotEmpty) 'Skipped: ${result.skipped.join(', ')}',
    ];
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(parts.isEmpty ? 'Nothing to fetch' : parts.join('. ')),
        ),
      );
  });

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(metadataControllerProvider(widget.pid));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit metadata')),
      body: switch (editor) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => _errorView(context, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _errorView(BuildContext context, Object error) {
    final message = error is WaxDeckApiException
        ? error.message
        : 'Could not load the metadata';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                ref.invalidate(metadataControllerProvider(widget.pid)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, MetadataEditorState state) {
    if (!_lyricsSeeded) {
      _lyricsSeeded = true;
      _lyricsController.text = state.metadata.lyrics?.lrc ?? '';
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldsCard(context, state),
          if (_writeBackFailures.isNotEmpty) _writeBackWarnings(context),
          _creditsCard(context, state),
          _artworkCard(context, state),
          _tagsCard(context, state),
          _lyricsCard(context),
          _releaseStatusCard(context, state),
          _actionsCard(context, state),
        ],
      ),
    );
  }

  Widget _fieldsCard(BuildContext context, MetadataEditorState state) {
    final textTheme = Theme.of(context).textTheme;
    final changed = _changedFields(state);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fields', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final field in state.kindFields.fields) ...[
              _FieldRow(
                field: field,
                controller: _controllerFor(
                  field.name,
                  state.metadata.fields[field.name] ?? '',
                ),
                locked: state.isLocked(field.name),
                provenance: state.provenanceFor(field.name),
                onToggleLock: () => _run(
                  () => ref
                      .read(metadataControllerProvider(widget.pid).notifier)
                      .setLock(field.name, locked: !state.isLocked(field.name)),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _flagBox(
                  id: 'metadata-writeback',
                  label: 'Write tags to files',
                  value: _writeBack,
                  onChanged: (v) => setState(() => _writeBack = v),
                ),
                _flagBox(
                  id: 'metadata-lock',
                  label: 'Lock edited fields',
                  value: _lock,
                  onChanged: (v) => setState(() => _lock = v),
                ),
                _flagBox(
                  id: 'metadata-force',
                  label: 'Force',
                  value: _force,
                  onChanged: (v) => setState(() => _force = v),
                ),
                Semantics(
                  identifier: 'metadata-save',
                  label: 'Save changed fields',
                  button: true,
                  child: FilledButton(
                    key: const Key('metadata-save'),
                    onPressed: changed.isEmpty || _busy
                        ? null
                        : () => _save(state),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _flagBox({
    required String id,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Semantics(
      identifier: id,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: Key(id),
            value: value,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Text(label),
        ],
      ),
    );
  }

  Widget _writeBackWarnings(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: const Key('metadata-writeback-warnings'),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved, but some files kept their old tags',
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final failure in _writeBackFailures)
              Text(
                '${failure.path ?? failure.filePid}: ${failure.reason}',
                style: textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _artworkCard(BuildContext context, MetadataEditorState state) {
    final textTheme = Theme.of(context).textTheme;
    final meta = state.metadata;
    final (String status, IconData icon) = meta.hasOwnArtwork
        ? ('Has its own cover', Icons.image)
        : meta.hasArtwork
        ? ('Inherits a cover from its album or artist', Icons.image_outlined)
        : ('No cover', Icons.hide_image_outlined);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artwork', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              key: const Key('artwork-status'),
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(child: Text(status)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _creditsCard(BuildContext context, MetadataEditorState state) {
    final textTheme = Theme.of(context).textTheme;
    final roles = state.kindFields.creditRoles;
    final role = _creditRole ?? (roles.isEmpty ? null : roles.first.name);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Credits', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final credit in state.metadata.credits)
              Text('${credit.role}: ${credit.names.join(', ')}'),
            if (roles.isEmpty)
              Text('No credit roles for this kind', style: textTheme.bodySmall)
            else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Semantics(
                    identifier: 'credits-role',
                    child: DropdownButton<String>(
                      key: const Key('credits-role'),
                      value: role,
                      onChanged: (v) => setState(() => _creditRole = v),
                      items: [
                        for (final r in roles)
                          DropdownMenuItem(value: r.name, child: Text(r.name)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('credits-names'),
                      controller: _creditNamesController,
                      decoration: const InputDecoration(
                        labelText: 'Names, comma separated',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'credits-save',
                    label: 'Save credits',
                    button: true,
                    child: FilledButton.tonal(
                      key: const Key('credits-save'),
                      onPressed: role == null || _busy
                          ? null
                          : () => _run(() async {
                              final names = _creditNamesController.text
                                  .split(',')
                                  .map((n) => n.trim())
                                  .where((n) => n.isNotEmpty)
                                  .toList();
                              final result = await ref
                                  .read(
                                    metadataControllerProvider(
                                      widget.pid,
                                    ).notifier,
                                  )
                                  .saveCredits(role, names);
                              _showResult(result);
                            }),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tagsCard(BuildContext context, MetadataEditorState state) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Custom tags', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final tag in state.metadata.customTags)
              Row(
                children: [
                  Expanded(child: Text('${tag.key}: ${tag.values.join(', ')}')),
                  Semantics(
                    identifier: 'tag-remove-${tag.key}',
                    label: 'Remove tag ${tag.key}',
                    button: true,
                    child: IconButton(
                      key: ValueKey('tag-remove-${tag.key}'),
                      tooltip: 'Remove tag',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _run(
                        () => ref
                            .read(
                              metadataControllerProvider(widget.pid).notifier,
                            )
                            .removeTag(tag.key),
                      ),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const Key('tag-key'),
                    controller: _tagKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('tag-values'),
                    controller: _tagValuesController,
                    decoration: const InputDecoration(
                      labelText: 'Values, comma separated',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  identifier: 'tag-add',
                  label: 'Add tag',
                  button: true,
                  child: FilledButton.tonal(
                    key: const Key('tag-add'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final key = _tagKeyController.text.trim();
                            if (key.isEmpty) return;
                            final values = _tagValuesController.text
                                .split(',')
                                .map((v) => v.trim())
                                .where((v) => v.isNotEmpty)
                                .toList();
                            await ref
                                .read(
                                  metadataControllerProvider(
                                    widget.pid,
                                  ).notifier,
                                )
                                .setTag(key, values);
                            _tagKeyController.clear();
                            _tagValuesController.clear();
                          }),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lyricsCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lyrics (LRC)', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              key: const Key('lyrics-field'),
              controller: _lyricsController,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '[00:12.00] First line',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  identifier: 'lyrics-clear',
                  label: 'Clear lyrics',
                  button: true,
                  child: TextButton(
                    key: const Key('lyrics-clear'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await ref
                                .read(
                                  metadataControllerProvider(
                                    widget.pid,
                                  ).notifier,
                                )
                                .clearLyrics();
                            _lyricsController.clear();
                          }),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  identifier: 'lyrics-save',
                  label: 'Save lyrics',
                  button: true,
                  child: FilledButton.tonal(
                    key: const Key('lyrics-save'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final result = await ref
                                .read(
                                  metadataControllerProvider(
                                    widget.pid,
                                  ).notifier,
                                )
                                .saveLyrics(_lyricsController.text);
                            _showResult(result);
                          }),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _releaseStatusCard(BuildContext context, MetadataEditorState state) {
    return Card(
      child: Semantics(
        identifier: 'unofficial-switch',
        child: SwitchListTile(
          key: const Key('unofficial-switch'),
          title: const Text('Unofficial release'),
          subtitle: const Text(
            'Marks this release as a bootleg or other unofficial issue.',
          ),
          value: state.metadata.unofficial,
          onChanged: _busy
              ? null
              : (v) => _run(
                  () => ref
                      .read(metadataControllerProvider(widget.pid).notifier)
                      .setUnofficial(unofficial: v),
                ),
        ),
      ),
    );
  }

  Widget _actionsCard(BuildContext context, MetadataEditorState state) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Identification', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Semantics(
                  identifier: 'metadata-rematch',
                  label: 'Rematch',
                  button: true,
                  child: OutlinedButton.icon(
                    key: const Key('metadata-rematch'),
                    onPressed: _busy ? null : _rematch,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('Rematch'),
                  ),
                ),
                Semantics(
                  identifier: 'metadata-enrich',
                  label: 'Fetch metadata',
                  button: true,
                  child: OutlinedButton.icon(
                    key: const Key('metadata-enrich'),
                    onPressed: _busy ? null : () => _enrich(state),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Fetch metadata'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.controller,
    required this.locked,
    required this.provenance,
    required this.onToggleLock,
  });

  final EditableField field;
  final TextEditingController controller;
  final bool locked;
  final FieldProvenance? provenance;
  final VoidCallback onToggleLock;

  String get _provenanceText {
    final p = provenance;
    if (p == null) return 'Source unknown';
    final provider = p.provider;
    return provider == null
        ? 'Source: ${p.source}'
        : 'Source: ${p.source} ($provider)';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: Key('field-${field.name}'),
            controller: controller,
            decoration: InputDecoration(
              labelText: field.name,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Tooltip(
          message: _provenanceText,
          child: Semantics(
            identifier: 'field-lock-${field.name}',
            label: locked ? 'Unlock ${field.name}' : 'Lock ${field.name}',
            button: true,
            child: IconButton(
              key: Key('field-lock-${field.name}'),
              icon: Icon(locked ? Icons.lock : Icons.lock_open, size: 18),
              onPressed: onToggleLock,
            ),
          ),
        ),
      ],
    );
  }
}
