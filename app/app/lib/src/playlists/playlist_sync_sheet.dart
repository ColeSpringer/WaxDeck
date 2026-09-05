import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../library/item_delete.dart';
import '../shell/semantics_ids.dart';
import 'playlist_import.dart';
import 'playlist_sync_controller.dart';

/// The synced-playlist settings sheet: bind a manual playlist to a
/// source URL, pick the mode and interval, dry-run what a sync would
/// do, run one now, or stop syncing.
Future<void> showPlaylistSyncSheet(BuildContext context, String pid) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlaylistSyncSheet(pid: pid),
    );

class _PlaylistSyncSheet extends ConsumerStatefulWidget {
  const _PlaylistSyncSheet({required this.pid});

  final String pid;

  @override
  ConsumerState<_PlaylistSyncSheet> createState() => _PlaylistSyncSheetState();
}

class _PlaylistSyncSheetState extends ConsumerState<_PlaylistSyncSheet> {
  final _url = TextEditingController();
  final _payload = TextEditingController();
  String _mode = 'mirror';
  int _intervalHours = 6;
  bool _busy = false;
  // Which form an unbound playlist is being bound through. A bound one
  // reads its arm off the binding instead.
  bool _liveArm = true;
  PlaylistImportSource _source = PlaylistImportSource.spotify;
  // The binding the fields were last seeded from, so a background
  // rebuild never overtypes what someone is editing.
  bool _seeded = false;
  // The URL the live form was seeded with. A form whose URL still says
  // this is a settings-only save; an edited one rebinds.
  String _seededUrl = '';

  static const _intervals = [1, 3, 6, 12, 24];

  /// The exports a binding can name. M3U is absent from the binding's
  /// source enum, because a file of paths is not something to re-match
  /// against.
  static final _sources = PlaylistImportSource.values
      .where((s) => s.canBind)
      .toList(growable: false);

  @override
  void dispose() {
    _url.dispose();
    _payload.dispose();
    super.dispose();
  }

  void _seedFrom(PlaylistSource? src) {
    if (_seeded) return;
    _seeded = true;
    if (src == null) return;
    _url.text = src.url ?? '';
    _seededUrl = _url.text;
    _mode = src.mode;
    _intervalHours = src.intervalHours ?? 6;
    _liveArm = src.live;
  }

  /// Which form this sheet is on: the binding's where there is one,
  /// the arm choice where there is not.
  ///
  /// One reading, used by the build, the body and both buttons. Two
  /// would drift: a playlist that gains a matched binding underneath an
  /// open sheet renders as matched off `bound` while a body built off
  /// `_liveArm` keeps sending an interval, which the server refuses for
  /// as long as the sheet stays open.
  bool _live(PlaylistSource? bound) => bound?.live ?? _liveArm;

  /// Whether Save would send settings alone: a binding already stored,
  /// and nothing typed that would replace it.
  ///
  /// A live form counts as untouched while its URL still reads what it
  /// was seeded with, which is what keeps a mode flip off the network.
  /// A cleared URL is not untouched: it is a rebind nobody has finished
  /// typing, and the server refuses it rather than re-saving settings
  /// onto the binding it was meant to replace.
  bool _settingsOnly(PlaylistSource? bound) {
    if (bound == null) return false;
    if (!bound.live) return true;
    return _url.text.trim() == _seededUrl.trim() && _url.text.trim().isNotEmpty;
  }

  /// The modes this form offers. A matched binding downloads nothing
  /// and so has nothing to trash; a live one offers it to whoever holds
  /// the delete right, and to anyone already on it, so a binding is not
  /// silently re-saved onto a different mode.
  List<String> _modesFor({required bool live}) => <String>[
    'append',
    'mirror',
    if (live && (canDeleteItems(ref) || _mode == 'mirror-trash'))
      'mirror-trash',
  ];

  String _modeLabel(AppLocalizations l10n, String mode) => switch (mode) {
    'append' => l10n.playlistSyncModeAppend,
    'mirror-trash' => l10n.playlistSyncModeMirrorTrash,
    _ => l10n.playlistSyncModeMirror,
  };

  String _modeHelp(AppLocalizations l10n) => switch (_mode) {
    'append' => l10n.playlistSyncModeHelpAppend,
    'mirror-trash' => l10n.playlistSyncModeHelpMirrorTrash,
    _ => l10n.playlistSyncModeHelpMirror,
  };

  Future<void> _run(
    Future<void> Function() action, {
    required bool refusal,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (e) {
      // A pasted export the parser could not read. Its own sentence,
      // for the same reason a server refusal keeps the server's: the
      // subject is what somebody just typed.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            refusal ? explainRefusal(l10n, e) : explainError(l10n, e),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The body Save and Preview both send, so the dry run is always of
  /// what the button beside it would do.
  ///
  /// A settings-only body names no source at all: the server keeps the
  /// stored one, its refs, its identity and its cover, and a save is
  /// spared the network probe a rebind costs. Only a save - a dry run
  /// enumerates the source either way, because that read is what a dry
  /// run is.
  ({String? url, String? source, String? payload, List<PortableRef>? refs})
  _body(PlaylistSource? bound, AppLocalizations l10n) {
    if (_settingsOnly(bound)) {
      return (url: null, source: null, payload: null, refs: null);
    }
    if (_live(bound)) {
      return (url: _url.text.trim(), source: null, payload: null, refs: null);
    }
    final payload = _payload.text;
    // Portable exports carry refs rather than text, parsed here the way
    // the import dialog parses them.
    if (_source == PlaylistImportSource.portable) {
      final (_, refs) = parsePortablePlaylistJson(l10n, payload);
      return (url: null, source: _source.wire, payload: null, refs: refs);
    }
    return (url: null, source: _source.wire, payload: payload, refs: null);
  }

  Future<void> _save(PlaylistSource? bound) => _run(refusal: true, () async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final body = _body(bound, l10n);
    await ref
        .read(playlistSyncProvider(widget.pid).notifier)
        .bind(
          mode: _mode,
          url: body.url,
          source: body.source,
          payload: body.payload,
          refs: body.refs,
          intervalHours: _live(bound) ? _intervalHours : null,
        );
    // What is stored now, so a second save that only moves the mode is
    // a settings-only one: the seed never ran for a binding made here.
    _seededUrl = _url.text;
    messenger.showSnackBar(SnackBar(content: Text(l10n.playlistSyncSaved)));
  });

  Future<void> _syncNow() => _run(refusal: true, () async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    await ref.read(playlistSyncProvider(widget.pid).notifier).syncNow();
    messenger.showSnackBar(SnackBar(content: Text(l10n.playlistSyncQueued)));
  });

  Future<void> _unbind() => _run(refusal: false, () async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    await ref.read(playlistSyncProvider(widget.pid).notifier).unbind();
    messenger.showSnackBar(SnackBar(content: Text(l10n.playlistSyncUnbound)));
    if (navigator.mounted) navigator.pop();
  });

  Future<void> _preview(PlaylistSource? bound) => _run(refusal: true, () async {
    final notifier = ref.read(playlistSyncProvider(widget.pid).notifier);
    final body = _body(bound, context.l10n);
    // Exactly what Save would send, which is what makes this a dry run
    // rather than a second question.
    final preview = await notifier.preview(
      mode: _mode,
      url: body.url,
      source: body.source,
      payload: body.payload,
      refs: body.refs,
      intervalHours: _live(bound) ? _intervalHours : null,
    );
    if (!mounted) return;
    await _showPreviewDialog(context, preview);
  });

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final async = ref.watch(playlistSyncProvider(widget.pid));
    final bound = async.value;
    // Seed only once the binding has actually answered; seeding off a
    // still-loading read would latch the defaults over stored settings.
    if (async.hasValue) _seedFrom(bound);
    final live = _live(bound);
    final modes = _modesFor(live: live);
    return SafeArea(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.playlistSyncSheet,
        child: Padding(
          padding: EdgeInsets.only(
            left: WaxSpace.s16,
            right: WaxSpace.s16,
            top: WaxSpace.s16,
            bottom: WaxSpace.s16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.playlistSyncSheetTitle,
                style: WaxType.headline.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: WaxSpace.s12),
              // Nothing to save until the read has answered. An unbound
              // playlist answers as data (null), so anything else here
              // is a read that has not landed or one that failed - and
              // this provider does not retry, so a failure is final.
              // Drawing the unbound form over either is a Save that
              // rewrites a binding this sheet never saw.
              if (async case AsyncError(:final error)) ...<Widget>[
                WaxBanner(
                  message: context.explain(error),
                  tone: WaxBannerTone.caution,
                ),
                const SizedBox(height: WaxSpace.s12),
                WaxButton(
                  label: l10n.playlistSyncRetryRead,
                  kind: WaxButtonKind.tonal,
                  onPressed: () =>
                      ref.invalidate(playlistSyncProvider(widget.pid)),
                ),
              ] else if (!async.hasValue) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.all(WaxSpace.s16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ] else ...<Widget>[
                // The first question, and only where it is still open: a
                // binding already answered it, and offering the other arm
                // over a stored one would be a way to lose it by accident.
                if (bound == null) ...<Widget>[
                  WaxChoice<bool>(
                    value: _liveArm,
                    options: const <bool>[true, false],
                    labelFor: (arm) => arm
                        ? l10n.playlistSyncArmLive
                        : l10n.playlistSyncArmMatched,
                    label: l10n.playlistSyncArmLabel,
                    semanticsId: SemanticsIds.playlistSyncArm,
                    optionSemanticsIdFor: (arm) =>
                        SemanticsIds.playlistSyncArmOption(
                          arm ? 'live' : 'matched',
                        ),
                    onChanged: _busy
                        ? null
                        : (arm) => setState(() {
                            _liveArm = arm;
                            // mirror-trash is a live-only mode, so an arm
                            // switch cannot leave the form holding it.
                            if (!arm && _mode == 'mirror-trash') {
                              _mode = 'mirror';
                            }
                          }),
                  ),
                  const SizedBox(height: WaxSpace.s12),
                ],
                if (live) ...<Widget>[
                  WaxTextField(
                    label: l10n.playlistSyncUrlLabel,
                    hint: l10n.playlistSyncUrlHint,
                    controller: _url,
                    keyboardType: TextInputType.url,
                    semanticsId: SemanticsIds.playlistSyncUrl,
                  ),
                ] else if (bound == null) ...<Widget>[
                  WaxChoice<PlaylistImportSource>(
                    value: _source,
                    options: _sources,
                    labelFor: (source) => source.labelOf(l10n),
                    label: l10n.playlistSyncSourceLabel,
                    semanticsId: SemanticsIds.playlistSyncSource,
                    optionSemanticsIdFor: (source) =>
                        SemanticsIds.playlistSyncSourceOption(source.wire),
                    onChanged: _busy
                        ? null
                        : (source) => setState(() => _source = source),
                  ),
                  const SizedBox(height: WaxSpace.s12),
                  WaxTextField(
                    label: l10n.playlistSyncPayloadLabel,
                    hint: l10n.playlistSyncPayloadHint,
                    controller: _payload,
                    maxLines: 6,
                    semanticsId: SemanticsIds.playlistSyncPayload,
                  ),
                ] else ...<Widget>[
                  Text(
                    l10n.playlistSyncMatchedNote(bound.source),
                    style: WaxType.body.copyWith(color: colors.textSecondary),
                  ),
                  if (bound.refCount != null) ...<Widget>[
                    const SizedBox(height: WaxSpace.s4),
                    Text(
                      l10n.playlistSyncRefCount(bound.refCount!),
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: WaxSpace.s12),
                WaxChoice<String>(
                  value: _mode,
                  options: modes,
                  labelFor: (mode) => _modeLabel(l10n, mode),
                  label: l10n.playlistSyncModeLabel,
                  semanticsId: SemanticsIds.playlistSyncMode,
                  optionSemanticsIdFor: SemanticsIds.playlistSyncModeOption,
                  onChanged: _busy
                      ? null
                      : (mode) => setState(() => _mode = mode),
                ),
                const SizedBox(height: WaxSpace.s4),
                Text(
                  live ? _modeHelp(l10n) : l10n.playlistSyncMatchedModeHelp,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
                if (live) ...<Widget>[
                  const SizedBox(height: WaxSpace.s12),
                  WaxChoice<int>(
                    value: _intervalHours,
                    options: _intervals,
                    labelFor: (hours) => l10n.playlistSyncIntervalHours(hours),
                    label: l10n.playlistSyncIntervalLabel,
                    semanticsId: SemanticsIds.playlistSyncInterval,
                    optionSemanticsIdFor: (hours) =>
                        SemanticsIds.playlistSyncIntervalOption(hours),
                    onChanged: _busy
                        ? null
                        : (hours) => setState(() => _intervalHours = hours),
                  ),
                ],
                if (bound != null && bound.lastRun != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s12),
                  Text(
                    _lastRunLine(l10n, bound.lastRun!),
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
                if (bound != null && bound.disabled) ...<Widget>[
                  const SizedBox(height: WaxSpace.s12),
                  WaxBanner(
                    message: l10n.playlistSyncSuspended,
                    tone: WaxBannerTone.caution,
                  ),
                ] else if (bound != null &&
                    (bound.lastError ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: WaxSpace.s12),
                  // The server's sentence framed rather than bare: the
                  // frame is translated, and the sentence is the only
                  // thing that knows what failed.
                  WaxBanner(
                    message: l10n.playlistSyncFailingBanner(bound.lastError!),
                    tone: WaxBannerTone.caution,
                  ),
                ],
                const SizedBox(height: WaxSpace.s16),
                Wrap(
                  spacing: WaxSpace.s8,
                  runSpacing: WaxSpace.s8,
                  children: <Widget>[
                    WaxButton(
                      label: l10n.playlistSyncPreviewButton,
                      kind: WaxButtonKind.tonal,
                      semanticsId: SemanticsIds.playlistSyncPreview,
                      onPressed: _busy
                          ? null
                          : () => unawaited(_preview(bound)),
                    ),
                    WaxButton(
                      label: l10n.playlistSyncSave,
                      semanticsId: SemanticsIds.playlistSyncSave,
                      onPressed: _busy ? null : () => unawaited(_save(bound)),
                    ),
                    if (bound != null)
                      WaxButton(
                        label: l10n.playlistSyncNow,
                        kind: WaxButtonKind.tonal,
                        semanticsId: SemanticsIds.playlistSyncNow,
                        onPressed: _busy ? null : () => unawaited(_syncNow()),
                      ),
                    if (bound != null)
                      WaxButton(
                        label: l10n.playlistSyncUnbind,
                        kind: WaxButtonKind.text,
                        semanticsId: SemanticsIds.playlistSyncUnbind,
                        onPressed: _busy ? null : () => unawaited(_unbind()),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The last completed run's counts as one caption line, non-zero parts
/// only; a run that changed nothing says so in words.
String _lastRunLine(AppLocalizations l10n, PlaylistSyncCounts c) {
  final parts = <String>[
    if (c.added > 0) l10n.playlistSyncCountAdded(c.added),
    if (c.removed > 0) l10n.playlistSyncCountRemoved(c.removed),
    if (c.trashed > 0) l10n.playlistSyncCountTrashed(c.trashed),
    if (c.queued > 0) l10n.playlistSyncCountQueued(c.queued),
    if (c.unavailable > 0) l10n.playlistSyncCountUnavailable(c.unavailable),
    if (c.missing > 0) l10n.playlistSyncCountMissing(c.missing),
  ];
  if (parts.isEmpty) return l10n.playlistSyncLastRunNothing;
  return l10n.playlistSyncLastRunLabel(parts.join(', '));
}

Future<void> _showPreviewDialog(
  BuildContext context,
  PlaylistSyncPreview preview,
) {
  final l10n = context.l10n;
  final lines = <String>[
    if (preview.wouldAdd > 0) l10n.playlistSyncPreviewAdd(preview.wouldAdd),
    if (preview.wouldDownload > 0)
      l10n.playlistSyncPreviewDownload(preview.wouldDownload),
    if (preview.wouldRemove > 0)
      l10n.playlistSyncPreviewRemove(preview.wouldRemove),
    if (preview.wouldTrash > 0)
      l10n.playlistSyncPreviewTrash(preview.wouldTrash),
    if (preview.pending > 0) l10n.playlistSyncPreviewPending(preview.pending),
    if (preview.unavailable > 0)
      l10n.playlistSyncPreviewUnavailable(preview.unavailable),
    if (preview.missing > 0) l10n.playlistSyncPreviewMissing(preview.missing),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) {
      final colors = WaxColors.of(context);
      return AlertDialog(
        title: Text(l10n.playlistSyncPreviewTitle),
        content: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.playlistSyncPreviewDialog,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (lines.isEmpty)
                Text(
                  l10n.playlistSyncPreviewNothing,
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                )
              else
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WaxSpace.s4),
                    child: Text(
                      line,
                      style: WaxType.body.copyWith(color: colors.textPrimary),
                    ),
                  ),
              for (final miss in preview.misses.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: WaxSpace.s4),
                  child: Text(
                    [
                      if ((miss.artist ?? '').isNotEmpty) miss.artist,
                      miss.title,
                    ].join(' - '),
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      );
    },
  );
}
