import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../library/item_delete.dart';
import '../shell/semantics_ids.dart';
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
  String _mode = 'mirror';
  int _intervalHours = 6;
  bool _busy = false;
  // The binding the fields were last seeded from, so a background
  // rebuild never overtypes what someone is editing.
  bool _seeded = false;

  static const _intervals = [1, 3, 6, 12, 24];

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _seedFrom(PlaylistSource? src) {
    if (_seeded) return;
    _seeded = true;
    if (src == null) return;
    _url.text = src.url ?? '';
    _mode = src.mode;
    _intervalHours = src.intervalHours ?? 6;
  }

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

  Future<void> _save() => _run(refusal: true, () async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    await ref
        .read(playlistSyncProvider(widget.pid).notifier)
        .bind(
          mode: _mode,
          url: _url.text.trim(),
          intervalHours: _intervalHours,
        );
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
    // A live form previews what the fields say; a matched binding has
    // no form to speak of and previews what is stored.
    final live = bound == null || bound.live;
    final preview = live
        ? await notifier.preview(
            mode: _mode,
            url: _url.text.trim(),
            intervalHours: _intervalHours,
          )
        : await notifier.preview();
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
    final live = bound == null || bound.live;
    final mayTrash = canDeleteItems(ref);
    final modes = [
      'append',
      'mirror',
      if (mayTrash || _mode == 'mirror-trash') 'mirror-trash',
    ];
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
              if (live) ...<Widget>[
                WaxTextField(
                  label: l10n.playlistSyncUrlLabel,
                  hint: l10n.playlistSyncUrlHint,
                  controller: _url,
                  keyboardType: TextInputType.url,
                  semanticsId: SemanticsIds.playlistSyncUrl,
                ),
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
                  _modeHelp(l10n),
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                ),
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
              ] else ...<Widget>[
                Text(
                  l10n.playlistSyncMatchedNote(bound.source),
                  style: WaxType.body.copyWith(color: colors.textSecondary),
                ),
                if (bound.refCount != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s4),
                  Text(
                    l10n.playlistSyncRefCount(bound.refCount!),
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
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
                    onPressed: _busy ? null : () => unawaited(_preview(bound)),
                  ),
                  if (live)
                    WaxButton(
                      label: l10n.playlistSyncSave,
                      semanticsId: SemanticsIds.playlistSyncSave,
                      onPressed: _busy ? null : () => unawaited(_save()),
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
