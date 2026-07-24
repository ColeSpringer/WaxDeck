import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'playlist_cover.dart';
import 'playlist_screen.dart';
import 'playlists_controller.dart';
import 'rule_editor_screen.dart';

/// The caller's playlists plus every shared one, with a create dialog.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          Semantics(
            identifier: 'playlist-import',
            label: 'Import playlist',
            button: true,
            child: IconButton(
              key: const Key('playlist-import'),
              tooltip: 'Import playlist',
              icon: const Icon(Icons.playlist_add_circle_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _ImportPlaylistDialog(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Semantics(
        identifier: 'playlist-add',
        label: 'New playlist',
        button: true,
        child: FloatingActionButton(
          key: const Key('playlist-add'),
          tooltip: 'New playlist',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _CreatePlaylistDialog(),
          ),
          child: const Icon(Icons.add),
        ),
      ),
      body: switch (playlists) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(playlistsProvider.future),
          child: value.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No playlists yet')),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) =>
                      _PlaylistRow(playlist: value[index]),
                ),
        ),
        AsyncError(:final error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is WaxDeckApiException
                    ? error.message
                    : 'Could not load playlists',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(playlistsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final count = playlist.itemCount;
    final details = <String>[
      if (playlist.isSmart) 'Smart' else 'Manual',
      if (count != null) '$count items',
      if (playlist.isShared) 'Shared by ${playlist.ownerName}',
    ];
    return Semantics(
      identifier: 'playlist-${playlist.pid}',
      label: playlist.name,
      button: true,
      child: ListTile(
        key: ValueKey('playlist-${playlist.pid}'),
        leading: PlaylistCover(playlist: playlist, size: 40),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(details.join(' | ')),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaylistScreen(pid: playlist.pid),
          ),
        ),
      ),
    );
  }
}

/// Where a pasted playlist comes from. M3U rides its own endpoint; the
/// others go through the export-import endpoint and its resolve ladder.
enum _ImportSource {
  m3u('m3u', 'M3U'),
  spotify('spotify', 'Spotify CSV'),
  applemusic('applemusic', 'Apple Music'),
  ytmusic('ytmusic', 'YouTube Music CSV'),
  csv('csv', 'Generic CSV'),
  text('text', 'Text list'),
  portable('portable', 'Portable JSON');

  const _ImportSource(this.wire, this.label);

  final String wire;
  final String label;
}

/// Parses the JSON that "Export portable" copied on another server
/// back into refs. The shape mirrors the exporter exactly; anything
/// else throws [FormatException] for the dialog to show.
(String?, List<PortableRef>) parsePortablePlaylistJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This is not the copied portable JSON');
  }
  if (decoded is! Map<String, Object?> || decoded['refs'] is! List) {
    throw const FormatException(
      'This is not a portable playlist (expected a name and a refs list)',
    );
  }
  final refs = <PortableRef>[];
  for (final entry in decoded['refs'] as List) {
    if (entry is! Map<String, Object?>) continue;
    final title = entry['title'];
    if (title is! String || title.isEmpty) continue;
    refs.add(
      PortableRef(
        kind: entry['kind'] as String? ?? 'track',
        essence: entry['essence'] as String?,
        fingerprint: entry['fingerprint'] as String?,
        fingerprintAlgo: (entry['fingerprintAlgo'] as num?)?.toInt(),
        mbid: entry['mbid'] as String?,
        asin: entry['asin'] as String?,
        isbn: entry['isbn'] as String?,
        isrc: entry['isrc'] as String?,
        artist: entry['artist'] as String?,
        title: title,
        album: entry['album'] as String?,
        durationMs: (entry['durationMs'] as num?)?.toInt(),
      ),
    );
  }
  if (refs.isEmpty) {
    throw const FormatException('The portable playlist carries no entries');
  }
  return (decoded['name'] as String?, refs);
}

/// Paste-a-playlist import: a source choice plus the pasted export.
/// M3U matches by path and title as before; the other sources resolve
/// entries against the library and report what they could not place.
class _ImportPlaylistDialog extends ConsumerStatefulWidget {
  const _ImportPlaylistDialog();

  @override
  ConsumerState<_ImportPlaylistDialog> createState() =>
      _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends ConsumerState<_ImportPlaylistDialog> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  var _source = _ImportSource.m3u;
  var _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _importM3u() async {
    final name = _nameController.text.trim();
    final content = _contentController.text;
    if (name.isEmpty || content.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(playlistsProvider.notifier)
          .importM3u(name: name, content: content);
      navigator.pop();
      final summary = result.unmatched == 0
          ? 'Imported "${result.playlist.name}" with ${result.matched} items'
          : 'Imported "${result.playlist.name}": ${result.matched} matched, '
                '${result.unmatched} not in the library';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(summary)));
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importExport() async {
    final payload = _contentController.text;
    if (payload.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameController.text.trim();
    try {
      // The portable source carries structured refs, not export text:
      // the pasted JSON is what "Export portable" copied elsewhere.
      String? exportedName;
      List<PortableRef>? refs;
      if (_source == _ImportSource.portable) {
        try {
          (exportedName, refs) = parsePortablePlaylistJson(payload);
        } on FormatException catch (e) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
          return;
        }
      }
      final result = await ref
          .read(playlistsProvider.notifier)
          .importExport(
            source: _source.wire,
            name: name.isEmpty ? exportedName : name,
            payload: refs == null ? payload : null,
            refs: refs,
          );
      navigator.pop();
      // This dialog's own context died with the pop; the navigator's
      // context hosts the report.
      if (!navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (_) => _ImportReportDialog(result: result),
      );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isM3u = _source == _ImportSource.m3u;
    return AlertDialog(
      title: const Text('Import playlist'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Source'),
              trailing: Semantics(
                identifier: 'playlist-import-source',
                child: DropdownButton<_ImportSource>(
                  key: const Key('playlist-import-source'),
                  value: _source,
                  onChanged: (source) {
                    if (source != null) setState(() => _source = source);
                  },
                  items: [
                    for (final source in _ImportSource.values)
                      DropdownMenuItem(
                        value: source,
                        child: Text(source.label),
                      ),
                  ],
                ),
              ),
            ),
            TextField(
              key: Key(isM3u ? 'm3u-name-field' : 'playlist-import-name'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: isM3u ? 'Playlist name' : 'Playlist name (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: Key(isM3u ? 'm3u-content-field' : 'playlist-import-payload'),
              controller: _contentController,
              decoration: InputDecoration(
                labelText: isM3u ? 'M3U contents' : '${_source.label} export',
                helperText: isM3u
                    ? 'Paste the playlist file here'
                    : _source == _ImportSource.portable
                    ? 'Paste the JSON that Export portable copied'
                    : 'Paste the exported playlist here',
                border: const OutlineInputBorder(),
              ),
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (isM3u)
          Semantics(
            identifier: 'm3u-import-confirm',
            label: 'Import',
            button: true,
            child: FilledButton(
              key: const Key('m3u-import-confirm'),
              onPressed: _busy ? null : _importM3u,
              child: const Text('Import'),
            ),
          )
        else
          Semantics(
            identifier: 'playlist-import-run',
            label: 'Import',
            button: true,
            child: FilledButton(
              key: const Key('playlist-import-run'),
              onPressed: _busy ? null : _importExport,
              child: const Text('Import'),
            ),
          ),
      ],
    );
  }
}

/// The import report: what was created, how much resolved, and the
/// entries with no library match.
class _ImportReportDialog extends StatelessWidget {
  const _ImportReportDialog({required this.result});

  final PlaylistImportResult result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('playlist-import-report'),
      title: Text(
        result.playlistPid == null ? 'Nothing imported' : 'Import complete',
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.playlistPid == null
                  ? 'No entries matched the library, so no playlist '
                        'was created.'
                  : 'Created "${result.name}" with ${result.resolved} of '
                        '${result.requested} entries.',
              key: const Key('playlist-import-summary'),
            ),
            if (result.missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Not in the library:', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final miss in result.missing)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            miss.artist == null
                                ? miss.title
                                : '${miss.artist} - ${miss.title}',
                            style: textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('playlist-import-report-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Name plus a manual-or-smart choice and a shared switch. A smart
/// choice continues into the rule editor instead of creating here.
class _CreatePlaylistDialog extends ConsumerStatefulWidget {
  const _CreatePlaylistDialog();

  @override
  ConsumerState<_CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<_CreatePlaylistDialog> {
  final _nameController = TextEditingController();
  var _kind = 'static';
  var _shared = false;
  var _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _busy) return;
    final navigator = Navigator.of(context);
    if (_kind == 'smart') {
      // The rule editor owns smart creation: a smart playlist without a
      // rule cannot exist.
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              RuleEditorScreen(createName: name, createShared: _shared),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await ref
          .read(playlistsProvider.notifier)
          .create(
            name: name,
            kind: 'static',
            visibility: _shared ? 'shared' : null,
          );
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(pid: created.pid),
        ),
      );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No Semantics identifier wrapper: on the web it would mint a
          // second, disabled text-field node beside the real input.
          // Tests locate the field by its label, like the login form.
          TextField(
            key: const Key('playlist-name-field'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Playlist name'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'static', label: Text('Manual')),
              ButtonSegment(value: 'smart', label: Text('Smart')),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          SwitchListTile(
            key: const Key('playlist-shared-switch'),
            title: const Text('Shared with everyone'),
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Semantics(
          identifier: 'playlist-create-confirm',
          label: 'Create',
          button: true,
          child: FilledButton(
            key: const Key('playlist-create-confirm'),
            onPressed: _busy ? null : _create,
            child: Text(_kind == 'smart' ? 'Next' : 'Create'),
          ),
        ),
      ],
    );
  }
}
