import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

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
            label: 'Import M3U',
            button: true,
            child: IconButton(
              key: const Key('playlist-import'),
              tooltip: 'Import M3U',
              icon: const Icon(Icons.playlist_add_circle_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _ImportM3uDialog(),
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
        leading: Icon(
          playlist.isSmart ? Icons.auto_awesome : Icons.queue_music,
        ),
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

/// Paste-an-M3U import: the server matches entries against the
/// library by path and title and reports what it could not place.
class _ImportM3uDialog extends ConsumerStatefulWidget {
  const _ImportM3uDialog();

  @override
  ConsumerState<_ImportM3uDialog> createState() => _ImportM3uDialogState();
}

class _ImportM3uDialogState extends ConsumerState<_ImportM3uDialog> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import M3U'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('m3u-name-field'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Playlist name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('m3u-content-field'),
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: 'M3U contents',
                helperText: 'Paste the playlist file here',
                border: OutlineInputBorder(),
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
        Semantics(
          identifier: 'm3u-import-confirm',
          label: 'Import',
          button: true,
          child: FilledButton(
            key: const Key('m3u-import-confirm'),
            onPressed: _busy ? null : _import,
            child: const Text('Import'),
          ),
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
