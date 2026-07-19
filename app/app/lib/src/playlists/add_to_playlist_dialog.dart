import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'name_dialog.dart';
import 'playlists_controller.dart';

/// Picks a manual playlist to append [item] to, marking the ones that
/// already hold it, with an inline new-playlist shortcut.
class AddToPlaylistDialog extends ConsumerStatefulWidget {
  const AddToPlaylistDialog({super.key, required this.item});

  final ItemSummary item;

  @override
  ConsumerState<AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<AddToPlaylistDialog> {
  Set<String>? _containing;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // One membership probe marks playlists that already hold the item;
    // failure just leaves the marks off.
    ref
        .read(repositoryProvider)
        .listPlaylists(containsItem: widget.item.pid, limit: 200)
        .then((page) {
          if (mounted) {
            setState(
              () => _containing = {for (final pl in page.playlists) pl.pid},
            );
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _add(String pid) async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).addPlaylistItems(pid, [
        widget.item.pid,
      ]);
      ref.invalidate(playlistDetailProvider(pid));
      ref.invalidate(playlistsProvider);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Added "${widget.item.title}"')),
      );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAdd() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const NamePromptDialog(
        title: 'New playlist',
        confirmLabel: 'Create',
        fieldKey: Key('add-to-playlist-name-field'),
        confirmKey: Key('add-to-playlist-create-confirm'),
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(playlistsProvider.notifier)
          .create(name: name, kind: 'static', itemPids: [widget.item.pid]);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Added "${widget.item.title}" to "$name"')),
      );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    return AlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 360,
        child: switch (playlists) {
          AsyncData(:final value) => Builder(
            builder: (context) {
              final editable = [
                for (final pl in value)
                  if (pl.isOwner && !pl.isSmart) pl,
              ];
              if (editable.isEmpty) {
                return const Text('No manual playlists yet; create one below.');
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final pl in editable)
                      ListTile(
                        key: ValueKey('add-target-${pl.pid}'),
                        dense: true,
                        leading: const Icon(Icons.queue_music),
                        title: Text(
                          pl.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: (_containing?.contains(pl.pid) ?? false)
                            ? const Icon(Icons.check)
                            : null,
                        onTap: _busy ? null : () => _add(pl.pid),
                      ),
                  ],
                ),
              );
            },
          ),
          AsyncError() => const Text('Could not load playlists'),
          _ => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
      actions: [
        TextButton.icon(
          key: const Key('add-to-playlist-new'),
          icon: const Icon(Icons.add),
          label: const Text('New playlist'),
          onPressed: _busy ? null : _createAndAdd,
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
