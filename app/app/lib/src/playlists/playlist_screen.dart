import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../books/book_screen.dart';
import '../player/player_screen.dart';
import '../providers.dart';
import '../sharing/share_dialog.dart';
import 'name_dialog.dart';
import 'playlists_controller.dart';
import 'rule_editor_screen.dart';

/// One playlist: header, member list, and owner affordances. Manual
/// playlists reorder by drag and remove per row; smart playlists show
/// their evaluation and edit through the rule editor.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.pid});

  final String pid;

  void _openItem(BuildContext context, ItemSummary item) {
    if (item.mediaType == MediaType.audiobook) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BookScreen(pid: item.pid)),
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(item: item)));
  }

  Future<void> _editRule(
    BuildContext context,
    WidgetRef ref,
    PlaylistView view,
  ) async {
    final navigator = Navigator.of(context);
    final next = await navigator.push<Playlist>(
      MaterialPageRoute<Playlist>(
        builder: (_) => RuleEditorScreen(editing: view.playlist),
      ),
    );
    // A rule replace reissued the pid; this screen's pid is retired, so
    // swap to the successor.
    if (next != null && next.pid != pid) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => PlaylistScreen(pid: next.pid)),
      );
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PlaylistView view,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NamePromptDialog(
        title: 'Rename playlist',
        confirmLabel: 'Rename',
        fieldKey: const Key('playlist-rename-field'),
        confirmKey: const Key('playlist-rename-confirm'),
        initial: view.playlist.name,
      ),
    );
    if (name != null && name.isNotEmpty && name != view.playlist.name) {
      await ref.read(playlistDetailProvider(pid).notifier).edit(name: name);
    }
  }

  /// Fetches the playlist as M3U8 and offers it for copying; the web
  /// build has no file-save surface, and the clipboard round-trips
  /// into every player that reads M3U.
  Future<void> _exportM3u(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final String content;
    try {
      content = await ref.read(repositoryProvider).exportPlaylistM3u(pid);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export M3U'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              key: const Key('m3u-export-content'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('m3u-export-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Playlist copied as M3U')),
                );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  /// Exports the playlist as portable refs and copies the JSON, for
  /// re-importing on another WaxDeck server through the portable
  /// import source.
  Future<void> _exportPortable(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final PortablePlaylist portable;
    try {
      portable = await ref.read(repositoryProvider).exportPlaylistPortable(pid);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: _portableJson(portable)));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Portable playlist copied')));
  }

  static String _portableJson(PortablePlaylist portable) => jsonEncode({
    'name': portable.name,
    'refs': [
      for (final ref in portable.refs)
        {
          'kind': ref.kind,
          if (ref.essence != null) 'essence': ref.essence,
          if (ref.fingerprint != null) 'fingerprint': ref.fingerprint,
          if (ref.fingerprintAlgo != null)
            'fingerprintAlgo': ref.fingerprintAlgo,
          if (ref.mbid != null) 'mbid': ref.mbid,
          if (ref.asin != null) 'asin': ref.asin,
          if (ref.isbn != null) 'isbn': ref.isbn,
          if (ref.isrc != null) 'isrc': ref.isrc,
          if (ref.artist != null) 'artist': ref.artist,
          'title': ref.title,
          if (ref.album != null) 'album': ref.album,
          if (ref.durationMs != null) 'durationMs': ref.durationMs,
        },
    ],
  });

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: const Text(
          'The playlist is removed for everyone it is '
          'shared with. Library items are never touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('playlist-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(playlistDetailProvider(pid).notifier).delete();
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(playlistDetailProvider(pid));
    final view = detail.value;
    final playlist = view?.playlist;
    final isOwner = playlist?.isOwner ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          if (view != null && isOwner && playlist!.isSmart)
            Semantics(
              identifier: 'playlist-edit-rule',
              label: 'Edit rules',
              button: true,
              child: IconButton(
                key: const Key('playlist-edit-rule'),
                tooltip: 'Edit rules',
                icon: const Icon(Icons.tune),
                onPressed: () => _editRule(context, ref, view),
              ),
            ),
          if (view != null)
            PopupMenuButton<String>(
              key: const Key('playlist-menu'),
              onSelected: (choice) => switch (choice) {
                'rename' => _rename(context, ref, view),
                'visibility' =>
                  ref
                      .read(playlistDetailProvider(pid).notifier)
                      .edit(
                        visibility: view.playlist.isShared
                            ? 'private'
                            : 'shared',
                      ),
                'share-link' => showShareLinkDialog(context, pid: pid),
                'export' => _exportM3u(context, ref),
                'portable' => _exportPortable(context, ref),
                'delete' => _delete(context, ref),
                _ => Future<void>.value(),
              },
              itemBuilder: (_) => [
                if (isOwner)
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                if (isOwner)
                  PopupMenuItem(
                    value: 'visibility',
                    child: Text(
                      view.playlist.isShared ? 'Make private' : 'Share',
                    ),
                  ),
                PopupMenuItem(
                  value: 'share-link',
                  child: Semantics(
                    identifier: 'playlist-share-link',
                    child: const Text(
                      'Share link',
                      key: Key('playlist-share-link'),
                    ),
                  ),
                ),
                const PopupMenuItem(value: 'export', child: Text('Export M3U')),
                PopupMenuItem(
                  value: 'portable',
                  child: Semantics(
                    identifier: 'playlist-export-portable',
                    child: const Text(
                      'Export portable',
                      key: Key('playlist-export-portable'),
                    ),
                  ),
                ),
                if (isOwner)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _body(context, ref, value),
        AsyncError(:final error) => Center(
          child: Text(
            error is WaxDeckApiException
                ? error.message
                : 'Could not load the playlist',
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, PlaylistView view) {
    final playlist = view.playlist;
    final entries = view.entries;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        [
          if (playlist.isSmart) 'Smart playlist' else 'Manual playlist',
          '${entries.length} items',
          if (playlist.isShared)
            playlist.isOwner ? 'Shared' : 'Shared by ${playlist.ownerName}',
        ].join(' | '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Expanded(
            child: Center(
              child: Text(
                playlist.isSmart
                    ? 'No items match the rules yet'
                    : 'No items yet; add some from the player',
              ),
            ),
          ),
        ],
      );
    }
    final canReorder = playlist.isOwner && !playlist.isSmart;
    final list = canReorder
        ? ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: entries.length,
            // onReorderItem receives the destination already adjusted
            // for the removal, unlike the retired onReorder.
            onReorderItem: (from, to) async {
              final pids = [for (final e in entries) e.item.pid];
              final moved = pids.removeAt(from);
              pids.insert(to, moved);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(playlistDetailProvider(pid).notifier)
                    .reorder(pids);
              } on WaxDeckApiException catch (e) {
                // The list already animated; snap back to server
                // truth and say why instead of failing silently.
                ref.invalidate(playlistDetailProvider(pid));
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            itemBuilder: (context, index) => _row(
              context,
              ref,
              playlist,
              entries[index],
              index,
              draggable: true,
            ),
          )
        : ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) =>
                _row(context, ref, playlist, entries[index], index),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Expanded(child: list),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    PlaylistEntry entry,
    int index, {
    bool draggable = false,
  }) {
    final item = entry.item;
    final position = entry.position;
    return Semantics(
      key: ValueKey('playlist-entry-$index-${item.pid}'),
      identifier: 'playlist-entry-$index',
      label: item.title,
      button: true,
      child: ListTile(
        leading: draggable
            ? ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              )
            : const Icon(Icons.music_note),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.artist == null
            ? null
            : Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: playlist.isOwner && !playlist.isSmart && position != null
            ? Semantics(
                identifier: 'playlist-entry-remove-$index',
                label: 'Remove from playlist',
                button: true,
                child: IconButton(
                  key: ValueKey('playlist-entry-remove-$index'),
                  tooltip: 'Remove from playlist',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref
                      .read(playlistDetailProvider(pid).notifier)
                      .removeAt(position),
                ),
              )
            : null,
        onTap: () => _openItem(context, item),
      ),
    );
  }
}
