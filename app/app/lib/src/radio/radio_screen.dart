import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'radio_controller.dart';

/// The shared internet radio library: play or stop stations, add them
/// by directory search or by hand, remove them.
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(radioStationsProvider);
    final playback = ref.watch(radioPlaybackProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      floatingActionButton: Semantics(
        identifier: SemanticsIds.radioAdd,
        label: 'Add station',
        button: true,
        child: FloatingActionButton(
          key: const Key(SemanticsIds.radioAdd),
          tooltip: 'Add station',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _AddStationDialog(),
          ),
          child: const Icon(Icons.add),
        ),
      ),
      body: switch (stations) {
        AsyncData(:final value) =>
          value.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No stations yet; add one to start listening'),
                  ),
                )
              : ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) =>
                      _StationRow(station: value[index], playback: playback),
                ),
        AsyncError(:final error) => Center(
          child: Text(
            error is WaxDeckApiException
                ? error.message
                : 'Could not load stations',
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _StationRow extends ConsumerWidget {
  const _StationRow({required this.station, required this.playback});

  final RadioStation station;
  final RadioPlayback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = playback.station?.pid == station.pid;
    final controller = ref.read(radioPlaybackProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    return Semantics(
      identifier: SemanticsIds.radio(station.pid),
      label: station.name,
      button: true,
      child: ListTile(
        key: ValueKey(SemanticsIds.radio(station.pid)),
        leading: Icon(active ? Icons.radio : Icons.radio_outlined),
        title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: active
            ? Text(
                playback.starting
                    ? 'Tuning in'
                    : (playback.nowPlaying == null
                          ? 'Playing'
                          : 'Playing: ${playback.nowPlaying}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: PopupMenuButton<String>(
          key: ValueKey('radio-menu-${station.pid}'),
          onSelected: (choice) async {
            if (choice == 'delete') {
              await ref
                  .read(radioStationsProvider.notifier)
                  .remove(station.pid);
              if (active) await controller.stop();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'delete', child: Text('Remove station')),
          ],
        ),
        onTap: () async {
          try {
            if (active) {
              await controller.stop();
            } else {
              await controller.play(station);
            }
          } on WaxDeckApiException catch (e) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      ),
    );
  }
}

/// Directory search with a manual fallback.
class _AddStationDialog extends ConsumerStatefulWidget {
  const _AddStationDialog();

  @override
  ConsumerState<_AddStationDialog> createState() => _AddStationDialogState();
}

class _AddStationDialogState extends ConsumerState<_AddStationDialog> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  var _manual = false;
  var _busy = false;
  List<RadioDirectoryEntry>? _results;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2 || _busy) return;
    setState(() {
      _busy = true;
      _searchError = null;
    });
    try {
      final results = await ref
          .read(repositoryProvider)
          .searchRadioDirectory(query, limit: 15);
      if (mounted) setState(() => _results = results);
    } on WaxDeckApiException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(radioStationsProvider.notifier)
          .add(
            name: name,
            streamUrl: streamUrl,
            homepageUrl: homepageUrl,
            logoUrl: logoUrl,
          );
      navigator.pop();
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
      title: const Text('Add station'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Search')),
                ButtonSegment(value: true, label: Text('By URL')),
              ],
              selected: {_manual},
              onSelectionChanged: (selection) =>
                  setState(() => _manual = selection.first),
            ),
            const SizedBox(height: 12),
            if (!_manual) ...[
              TextField(
                key: const Key('radio-search-field'),
                controller: _searchController,
                decoration: const InputDecoration(labelText: 'Station name'),
                onSubmitted: (_) => _search(),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('radio-search-run'),
                onPressed: _busy ? null : _search,
                child: const Text('Search directory'),
              ),
              if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _searchError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_results != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: _results!.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No matches'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final entry in _results!)
                              ListTile(
                                dense: true,
                                title: Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: entry.country == null
                                    ? null
                                    : Text(entry.country!),
                                onTap: _busy
                                    ? null
                                    : () => _add(
                                        name: entry.name,
                                        streamUrl: entry.streamUrl,
                                        homepageUrl: entry.homepageUrl,
                                        logoUrl: entry.logoUrl,
                                      ),
                              ),
                          ],
                        ),
                ),
            ] else ...[
              TextField(
                key: const Key('radio-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Station name'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('radio-url-field'),
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'Stream URL'),
                keyboardType: TextInputType.url,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_manual)
          Semantics(
            identifier: SemanticsIds.radioAddConfirm,
            label: 'Add station',
            button: true,
            child: FilledButton(
              key: const Key(SemanticsIds.radioAddConfirm),
              onPressed: _busy
                  ? null
                  : () => _add(
                      name: _nameController.text.trim(),
                      streamUrl: _urlController.text.trim(),
                    ),
              child: const Text('Add'),
            ),
          ),
      ],
    );
  }
}
