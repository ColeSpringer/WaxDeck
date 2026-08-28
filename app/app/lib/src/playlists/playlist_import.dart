import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'playlists_controller.dart';

/// Where a pasted playlist comes from. M3U rides its own endpoint; the
/// others go through the export-import endpoint and its resolve ladder.
enum PlaylistImportSource {
  m3u('m3u'),
  spotify('spotify'),
  applemusic('applemusic'),
  ytmusic('ytmusic'),
  csv('csv'),
  text('text'),
  portable('portable');

  const PlaylistImportSource(this.wire);

  /// The `source` value the import endpoint takes.
  final String wire;

  String labelOf(AppLocalizations l10n) => switch (this) {
    PlaylistImportSource.m3u => l10n.playlistImportSourceM3u,
    PlaylistImportSource.spotify => l10n.playlistImportSourceSpotify,
    PlaylistImportSource.applemusic => l10n.playlistImportSourceAppleMusic,
    PlaylistImportSource.ytmusic => l10n.playlistImportSourceYtMusic,
    PlaylistImportSource.csv => l10n.playlistImportSourceCsv,
    PlaylistImportSource.text => l10n.playlistImportSourceText,
    PlaylistImportSource.portable => l10n.playlistImportSourcePortable,
  };

  /// What the paste box says it wants; the shapes differ too much for
  /// one sentence to cover them. The four service exports share one,
  /// because for those it is the same sentence.
  String hintOf(AppLocalizations l10n) => switch (this) {
    PlaylistImportSource.m3u => l10n.playlistImportHintM3u,
    PlaylistImportSource.spotify ||
    PlaylistImportSource.applemusic ||
    PlaylistImportSource.ytmusic ||
    PlaylistImportSource.csv => l10n.playlistImportHintExport,
    PlaylistImportSource.text => l10n.playlistImportHintText,
    PlaylistImportSource.portable => l10n.playlistImportHintPortable,
  };

  /// Only M3U insists on a name: the rest carry one.
  bool get needsName => this == PlaylistImportSource.m3u;

  /// Whether the created playlist can be bound to what was pasted.
  /// M3U alone cannot: it is not in the binding's source enum, because
  /// a file of paths is not something to re-match against.
  bool get canBind => this != PlaylistImportSource.m3u;
}

/// One menu, one entry per source, each opening its own paste box.
/// Choosing the source decides what the box wants, so it is the first
/// question rather than a control beside the answer.
class PlaylistImportMenu extends StatelessWidget {
  const PlaylistImportMenu({super.key});

  @override
  Widget build(BuildContext context) => WaxMenuButton<PlaylistImportSource>(
    glyph: WaxIcons.downloads,
    label: context.l10n.playlistImportMenu,
    semanticsId: SemanticsIds.playlistImport,
    items: <WaxMenuItem<PlaylistImportSource>>[
      for (final source in PlaylistImportSource.values)
        WaxMenuItem<PlaylistImportSource>(
          value: source,
          label: source.labelOf(context.l10n),
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

/// Parses the JSON that "Export portable" copied on another server back
/// into refs. Anything else throws [FormatException] for the dialog to
/// show, which is why the table comes in as an argument.
(String?, List<PortableRef>) parsePortablePlaylistJson(
  AppLocalizations l10n,
  String text,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw FormatException(l10n.playlistImportNotJson);
  }
  if (decoded is! Map<String, Object?> || decoded['refs'] is! List) {
    throw FormatException(l10n.playlistImportNotPortable);
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
    throw FormatException(l10n.playlistImportNoEntries);
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

  /// Whether the created playlist is bound to what was pasted. Off by
  /// default: an import is a copy until somebody says otherwise.
  var _keepMatched = false;

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
    final l10n = context.l10n;
    if (payload.trim().isEmpty) {
      setState(() => _error = l10n.playlistImportPasteFirst);
      return;
    }
    if (_source.needsName && name.isEmpty) {
      setState(() => _error = l10n.playlistImportNeedsName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Read here, beside the navigator and messenger and for the same
    // reason: the bind happens after an await, and `ref` is only good
    // while this dialog is mounted - which a dismissal ends. The
    // import already ran, so the binding somebody asked for should not
    // depend on the dialog still being up.
    final repository = ref.read(repositoryProvider);
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
                    ? l10n.playlistImportedAll(
                        result.playlist.name,
                        result.matched,
                      )
                    : l10n.playlistImportedPartial(
                        result.playlist.name,
                        result.matched,
                        result.unmatched,
                      ),
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
          (exportedName, refs) = parsePortablePlaylistJson(l10n, payload);
        } on FormatException catch (e) {
          setState(() {
            _error = e.message;
            _busy = false;
          });
          return;
        }
      }
      // Decided once: the binding's whole meaning is that it is what
      // was imported, so both calls send the same body.
      final exportPayload = refs == null ? payload : null;
      final result = await ref
          .read(playlistsProvider.notifier)
          .importExport(
            source: _source.wire,
            name: name.isEmpty ? exportedName : name,
            payload: exportPayload,
            refs: refs,
          );
      // Bound here, before the pop, because this is where the parsed
      // export and the created pid are both still in hand; only the
      // outcome crosses into the report.
      final binding = await _bind(
        repository,
        l10n,
        result.playlistPid,
        payload: exportPayload,
        refs: refs,
      );
      if (mounted) navigator.pop();
      // This dialog's own context died with the pop; the navigator's
      // context hosts the report.
      if (!navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (_) => _ImportReportDialog(result: result, binding: binding),
      );
    } on WaxDeckApiException catch (e) {
      // What was pasted is what was refused, so the server's own words.
      if (mounted) setState(() => _error = explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Binds the created playlist to what was just pasted, and answers
  /// what the report should say about it - null when nobody asked, or
  /// when nothing was created to bind.
  ///
  /// Mode `mirror`, because the binding's meaning is "this playlist is
  /// that export": membership converges on the export and a later
  /// re-match fills what this pass missed. A failure is reported rather
  /// than raised - the playlist exists either way, and the import is
  /// what the dialog is closing on.
  Future<_BindOutcome?> _bind(
    WaxDeckRepository repository,
    AppLocalizations l10n,
    String? playlistPid, {
    String? payload,
    List<PortableRef>? refs,
  }) async {
    if (!_keepMatched || playlistPid == null) return null;
    try {
      // The repository rather than the playlist's sync notifier: this
      // pid is seconds old, so writing through one would start a
      // binding read whose not-found can land after the write and cache
      // a bound playlist as unbound.
      await repository.setPlaylistSource(
        playlistPid,
        mode: 'mirror',
        source: _source.wire,
        payload: payload,
        refs: refs,
      );
      return const _BindOutcome.kept();
    } on Object catch (e) {
      return _BindOutcome.refused(explainRefusal(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final source = _source.labelOf(l10n);
    return AlertDialog(
      title: Text(l10n.playlistImportTitle(source)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              WaxTextField(
                label: _source.needsName
                    ? l10n.playlistNameLabel
                    : l10n.playlistNameOptional,
                controller: _name,
                autofocus: _source.needsName,
                semanticsId: SemanticsIds.playlistImportName,
              ),
              const SizedBox(height: WaxSpace.s12),
              // A paste box, not a field: an export is many lines and
              // the house field has no multiline shape.
              Semantics(
                identifier: SemanticsIds.playlistImportPayload,
                label: l10n.playlistImportPayloadLabel(source),
                child: TextField(
                  controller: _payload,
                  autofocus: !_source.needsName,
                  maxLines: 8,
                  style: WaxType.monoData.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: _source.hintOf(l10n),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (_source.canBind)
                WaxSettingRow(
                  title: l10n.playlistImportKeepMatched,
                  help: l10n.playlistImportKeepMatchedHelp,
                  control: WaxSwitch(
                    value: _keepMatched,
                    label: l10n.playlistImportKeepMatched,
                    semanticsId: SemanticsIds.playlistImportKeepMatched,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _keepMatched = value),
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
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: l10n.playlistImportRun,
          semanticsId: SemanticsIds.playlistImportRun,
          onPressed: _busy ? null : () => unawaited(_import()),
        ),
      ],
    );
  }
}

/// What binding the created playlist to the pasted export did, worded
/// for the report. The dialog carries the outcome, not the request, so
/// nothing about the bind has to be re-derived there.
class _BindOutcome {
  const _BindOutcome.kept() : message = null, refused = false;
  const _BindOutcome.refused(String this.message) : refused = true;

  /// The server's own sentence for a refusal; null when it worked, and
  /// the report says so in the table's words.
  final String? message;

  final bool refused;

  String lineOf(AppLocalizations l10n) => refused
      ? l10n.playlistImportBindFailed(message!)
      : l10n.playlistImportBound;
}

/// The import report: what was created, how much resolved, whether it
/// stayed matched to the export, and the entries with no library match.
class _ImportReportDialog extends StatelessWidget {
  const _ImportReportDialog({required this.result, this.binding});

  final PlaylistImportResult result;

  /// What the keep-matched switch did, or null when it was off.
  final _BindOutcome? binding;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final made = result.playlistPid != null;
    return AlertDialog(
      title: Semantics(
        identifier: SemanticsIds.playlistImportReport,
        child: Text(
          made ? l10n.playlistImportComplete : l10n.playlistImportNothing,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              made
                  ? l10n.playlistImportCreated(
                      result.name,
                      result.resolved,
                      result.requested,
                    )
                  : l10n.playlistImportNoMatches,
              style: WaxType.body.copyWith(color: colors.textPrimary),
            ),
            if (binding != null) ...<Widget>[
              const SizedBox(height: WaxSpace.s8),
              Text(
                binding!.lineOf(l10n),
                style: WaxType.bodySmall.copyWith(
                  color: binding!.refused ? colors.error : colors.textSecondary,
                ),
              ),
            ],
            if (result.missing.isNotEmpty) ...<Widget>[
              const SizedBox(height: WaxSpace.s12),
              Text(
                l10n.playlistImportMissingHeading,
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
                          padding: const EdgeInsets.symmetric(
                            vertical: WaxSpace.s4,
                          ),
                          child: Text(
                            miss.artist == null
                                ? miss.title
                                : l10n.playlistImportMissingRow(
                                    miss.artist!,
                                    miss.title,
                                  ),
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
        WaxButton(
          label: l10n.commonClose,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
