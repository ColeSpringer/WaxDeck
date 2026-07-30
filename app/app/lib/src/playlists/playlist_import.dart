import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import 'playlists_controller.dart';

/// Where a pasted playlist comes from. M3U rides its own endpoint; the
/// others go through the export-import endpoint and its resolve ladder.
enum PlaylistImportSource {
  m3u('m3u', 'M3U file', 'Paste the playlist file here'),
  spotify('spotify', 'Spotify CSV', 'Paste the exported playlist here'),
  applemusic('applemusic', 'Apple Music', 'Paste the exported playlist here'),
  ytmusic('ytmusic', 'YouTube Music CSV', 'Paste the exported playlist here'),
  csv('csv', 'Generic CSV', 'Paste the exported playlist here'),
  text('text', 'Text list', 'One track a line: artist - title'),
  portable('portable', 'Portable JSON', 'Paste what Export portable copied');

  const PlaylistImportSource(this.wire, this.label, this.hint);

  /// The `source` value the import endpoint takes.
  final String wire;
  final String label;

  /// What the paste box says it wants; the shapes differ too much for
  /// one sentence to cover them.
  final String hint;

  /// Only M3U insists on a name: the rest carry one.
  bool get needsName => this == PlaylistImportSource.m3u;
}

/// One menu, one entry per source, each opening its own paste box.
/// Choosing the source decides what the box wants, so it is the first
/// question rather than a control beside the answer.
class PlaylistImportMenu extends StatelessWidget {
  const PlaylistImportMenu({super.key});

  @override
  Widget build(BuildContext context) => WaxMenuButton<PlaylistImportSource>(
    glyph: WaxIcons.downloads,
    label: 'Import playlist',
    semanticsId: SemanticsIds.playlistImport,
    items: <WaxMenuItem<PlaylistImportSource>>[
      for (final source in PlaylistImportSource.values)
        WaxMenuItem<PlaylistImportSource>(
          value: source,
          label: source.label,
          semanticsId: SemanticsIds.playlistImportSource(source.wire),
        ),
    ],
    onSelected: (source) => unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => _ImportDialog(source: source),
      ),
    ),
  );
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
    // Read for the type rather than cast to it: this JSON is pasted, so
    // a cast that throws escapes as an unhandled async error.
    String? text(String key) {
      final value = entry[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    int? number(String key) {
      final value = entry[key];
      return value is num ? value.toInt() : null;
    }

    final kind = text('kind') ?? 'track';
    refs.add(
      PortableRef(
        // The wire enum is closed; a name outside it throws from the
        // serialiser rather than answering a refusal.
        kind: _portableKinds.contains(kind) ? kind : 'track',
        essence: text('essence'),
        fingerprint: text('fingerprint'),
        fingerprintAlgo: number('fingerprintAlgo'),
        mbid: text('mbid'),
        asin: text('asin'),
        isbn: text('isbn'),
        isrc: text('isrc'),
        artist: text('artist'),
        title: title,
        album: text('album'),
        durationMs: number('durationMs'),
      ),
    );
  }
  if (refs.isEmpty) {
    throw const FormatException('The portable playlist carries no entries');
  }
  final name = decoded['name'];
  return (name is String && name.isNotEmpty ? name : null, refs);
}

/// What a portable ref may be; the wire enum accepts nothing else.
const _portableKinds = <String>{'track', 'book', 'episode'};

/// The paste box for one source: an optional name, the export itself, and
/// the message the server sent back when it refused.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.source});

  final PlaylistImportSource source;

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _name = TextEditingController();
  final _payload = TextEditingController();
  var _busy = false;

  /// Inside the dialog, not a snackbar: this stays open on a refusal and
  /// a snackbar renders on the scaffold behind the modal.
  String? _error;

  PlaylistImportSource get _source => widget.source;

  @override
  void dispose() {
    _name.dispose();
    _payload.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    final name = _name.text.trim();
    final payload = _payload.text;
    if (payload.trim().isEmpty) {
      setState(() => _error = 'Paste the playlist first.');
      return;
    }
    if (_source.needsName && name.isEmpty) {
      setState(() => _error = 'An M3U import needs a name for the playlist.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_source == PlaylistImportSource.m3u) {
        final result = await ref
            .read(playlistsProvider.notifier)
            .importM3u(name: name, content: payload);
        // Only while this dialog is still up: an import outlives a
        // dialog somebody dismissed, and popping then takes the screen
        // underneath with it.
        if (mounted) navigator.pop();
        // The M3U endpoint answers with counts rather than a resolve
        // report, and it pops on success, so a toast is readable.
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                result.unmatched == 0
                    ? 'Imported "${result.playlist.name}" with '
                          '${result.matched} items'
                    : 'Imported "${result.playlist.name}": '
                          '${result.matched} matched, ${result.unmatched} '
                          'not in the library',
              ),
            ),
          );
        return;
      }
      // The portable source carries refs, not export text.
      String? exportedName;
      List<PortableRef>? refs;
      if (_source == PlaylistImportSource.portable) {
        try {
          (exportedName, refs) = parsePortablePlaylistJson(payload);
        } on FormatException catch (e) {
          setState(() {
            _error = e.message;
            _busy = false;
          });
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
      if (mounted) navigator.pop();
      // This dialog's own context died with the pop; the navigator's
      // context hosts the report.
      if (!navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (_) => _ImportReportDialog(result: result),
      );
    } on WaxDeckApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return AlertDialog(
      title: Text('Import from ${_source.label}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              WaxTextField(
                label: _source.needsName
                    ? 'Playlist name'
                    : 'Playlist name (optional)',
                controller: _name,
                autofocus: _source.needsName,
                semanticsId: SemanticsIds.playlistImportName,
              ),
              const SizedBox(height: WaxSpace.s12),
              // A paste box, not a field: an export is many lines and
              // the house field has no multiline shape.
              Semantics(
                identifier: SemanticsIds.playlistImportPayload,
                label: '${_source.label} export',
                child: TextField(
                  controller: _payload,
                  autofocus: !_source.needsName,
                  maxLines: 8,
                  style: WaxType.monoData.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: _source.hint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: WaxSpace.s8),
                  child: Text(
                    _error!,
                    style: WaxType.caption.copyWith(color: colors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: 'Import',
          semanticsId: SemanticsIds.playlistImportRun,
          onPressed: _busy ? null : () => unawaited(_import()),
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
    final colors = WaxColors.of(context);
    final made = result.playlistPid != null;
    return AlertDialog(
      title: Semantics(
        identifier: SemanticsIds.playlistImportReport,
        child: Text(made ? 'Import complete' : 'Nothing imported'),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              made
                  ? 'Created "${result.name}" with ${result.resolved} of '
                        '${result.requested} entries.'
                  : 'No entries matched the library, so no playlist '
                        'was created.',
              style: WaxType.body.copyWith(color: colors.textPrimary),
            ),
            if (result.missing.isNotEmpty) ...<Widget>[
              const SizedBox(height: WaxSpace.s12),
              Text(
                'Not in the library:',
                style: WaxType.overline.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: WaxSpace.s4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final miss in result.missing)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            miss.artist == null
                                ? miss.title
                                : '${miss.artist} - ${miss.title}',
                            style: WaxType.bodySmall.copyWith(
                              color: colors.textSecondary,
                            ),
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
      actions: <Widget>[
        WaxButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
