import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../home/pin_action.dart';
import '../l10n/l10n.dart';
import '../metadata/artwork_manager.dart';
import '../providers.dart';
import '../sharing/share_dialog.dart';
import '../shell/semantics_ids.dart';
import '../uploads/file_picker_port.dart';
import 'playlist_create.dart';
import 'playlist_play.dart';
import 'playlist_sync_sheet.dart';
import 'playlists_controller.dart';
import 'rule_vocabulary.dart';

/// What a playlist's menus can do. The screen's overflow offers all but
/// play and shuffle, which are its header's buttons.
enum PlaylistAction {
  play,
  shuffle,
  pin,
  rename,
  visibility,
  shareLink,
  setCover,
  resetCover,
  syncSettings,
  exportM3u,
  exportNsp,
  exportPortable,
  delete,
}

/// How an action reads in either menu. Null for the pin, whose words
/// follow its state, so each menu draws that row itself.
({String label, WaxGlyph glyph, String? semanticsId})? _describe(
  AppLocalizations l10n,
  Playlist playlist,
  PlaylistAction action,
) => switch (action) {
  PlaylistAction.pin => null,
  PlaylistAction.play => (
    label: l10n.playlistPlay,
    glyph: WaxIcons.play,
    semanticsId: null,
  ),
  PlaylistAction.shuffle => (
    label: l10n.playlistShuffle,
    glyph: WaxIcons.shuffle,
    semanticsId: null,
  ),
  PlaylistAction.rename => (
    label: l10n.playlistRename,
    glyph: WaxIcons.edit,
    semanticsId: SemanticsIds.playlistRename,
  ),
  PlaylistAction.visibility => (
    label: playlist.isShared
        ? l10n.playlistMakePrivate
        : l10n.playlistShareWithEveryone,
    glyph: WaxIcons.share,
    semanticsId: SemanticsIds.playlistVisibility,
  ),
  PlaylistAction.shareLink => (
    label: l10n.playlistShareLink,
    glyph: WaxIcons.share,
    semanticsId: SemanticsIds.playlistShareLink,
  ),
  PlaylistAction.setCover => (
    label: l10n.playlistSetCover,
    glyph: WaxIcons.albums,
    semanticsId: SemanticsIds.playlistSetCover,
  ),
  PlaylistAction.resetCover => (
    label: l10n.playlistResetCover,
    glyph: WaxIcons.refresh,
    semanticsId: SemanticsIds.playlistResetCover,
  ),
  PlaylistAction.syncSettings => (
    label: l10n.playlistSyncSettings,
    glyph: WaxIcons.refresh,
    semanticsId: SemanticsIds.playlistSyncSettings,
  ),
  PlaylistAction.exportM3u => (
    label: l10n.playlistExportM3u,
    glyph: WaxIcons.downloads,
    semanticsId: SemanticsIds.playlistExportM3u,
  ),
  PlaylistAction.exportNsp => (
    label: l10n.playlistExportNsp,
    glyph: WaxIcons.downloads,
    semanticsId: SemanticsIds.playlistExportNsp,
  ),
  PlaylistAction.exportPortable => (
    label: l10n.playlistExportPortable,
    glyph: WaxIcons.share,
    semanticsId: SemanticsIds.playlistExportPortable,
  ),
  PlaylistAction.delete => (
    label: l10n.playlistDelete,
    glyph: WaxIcons.delete,
    semanticsId: SemanticsIds.playlistDelete,
  ),
};

/// The playlist screen's overflow, gated by who owns the list and what
/// the platform can pick.
List<WaxMenuItem<PlaylistAction>> playlistMenuItems(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) {
  final isOwner = playlist.isOwner;
  final hasPicker = ref.watch(filePickerProvider) != null;
  final l10n = context.l10n;
  return <WaxMenuItem<PlaylistAction>>[
    for (final action in <PlaylistAction>[
      PlaylistAction.pin,
      if (isOwner) ...<PlaylistAction>[
        PlaylistAction.rename,
        PlaylistAction.visibility,
      ],
      PlaylistAction.shareLink,
      // Hidden where the platform has no picker, which is the port
      // answering null.
      if (isOwner && hasPicker) PlaylistAction.setCover,
      // Offered whenever a cover shows: the wire does not say whether
      // it was uploaded, and resetting a generated one rebuilds it.
      if (isOwner && playlist.artUrl != null) PlaylistAction.resetCover,
      // Manual lists only: a smart playlist's membership is its rule,
      // so there is nothing for a source to reconcile.
      if (isOwner && !playlist.isSmart) PlaylistAction.syncSettings,
      PlaylistAction.exportM3u,
      // Smart only, but not owner only: neither export beside it is,
      // and the server gates none of the three.
      if (playlist.isSmart) PlaylistAction.exportNsp,
      PlaylistAction.exportPortable,
      if (isOwner) PlaylistAction.delete,
    ])
      if (_describe(l10n, playlist, action) case final entry?)
        WaxMenuItem<PlaylistAction>(
          value: action,
          label: entry.label,
          glyph: entry.glyph,
          destructive: action == PlaylistAction.delete,
          semanticsId: entry.semanticsId,
        )
      else
        pinMenuItem<PlaylistAction>(
          context,
          ref,
          playlist.pid,
          value: action,
          semanticsId: SemanticsIds.playlistPin,
        ),
  ];
}

/// A playlist card's sheet: play, shuffle, pin and the share link, plus
/// rename and delete for its owner. Covers, sync and exports stay on the
/// playlist's own screen, where their dialogs live.
Future<void> showPlaylistMenuSheet(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final l10n = context.l10n;
  final action = await showWaxOptionSheet<PlaylistAction>(
    context,
    builder: (sheetContext) => Consumer(
      builder: (_, sheetRef, _) {
        void choose(PlaylistAction action) =>
            Navigator.of(sheetContext).pop(action);
        return Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.itemMenuSheet(playlist.pid),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final action in <PlaylistAction>[
                PlaylistAction.play,
                PlaylistAction.shuffle,
                PlaylistAction.pin,
                PlaylistAction.shareLink,
                if (playlist.isOwner) ...<PlaylistAction>[
                  PlaylistAction.rename,
                  PlaylistAction.delete,
                ],
              ])
                if (_describe(l10n, playlist, action) case final entry?)
                  WaxOptionRow(
                    title: entry.label,
                    glyph: entry.glyph,
                    semanticsId: entry.semanticsId,
                    onTap: () => choose(action),
                  )
                else
                  pinSheetRow(sheetContext, sheetRef, (
                    pid: playlist.pid,
                    what: 'playlist',
                    name: playlist.name,
                  ), onTap: () => choose(action)),
            ],
          ),
        );
      },
    ),
  );
  if (action == null || !context.mounted) return;
  await runPlaylistAction(context, ref, playlist, action);
}

/// Runs [action] on [playlist]. [onDeleted] runs once a confirmed delete
/// has landed and [context] is still up: the screen leaves, a card stays.
Future<void> runPlaylistAction(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
  PlaylistAction action, {
  VoidCallback? onDeleted,
}) async {
  switch (action) {
    case PlaylistAction.play:
      await playPlaylistPid(ref, playlist.pid);
    case PlaylistAction.shuffle:
      await playPlaylistPid(ref, playlist.pid, shuffle: true);
    case PlaylistAction.pin:
      await togglePin(context, ref, playlist.pid, label: playlist.name);
    case PlaylistAction.rename:
      await _rename(context, playlist);
    case PlaylistAction.visibility:
      await _setVisibility(context, playlist);
    case PlaylistAction.shareLink:
      await showShareLinkDialog(context, pid: playlist.pid);
    case PlaylistAction.setCover:
      await _setCover(context, ref, playlist);
    case PlaylistAction.resetCover:
      await _resetCover(context, ref, playlist);
    case PlaylistAction.syncSettings:
      await showPlaylistSyncSheet(context, playlist.pid);
    case PlaylistAction.exportM3u:
      await _exportM3u(context, ref, playlist);
    case PlaylistAction.exportNsp:
      await _exportNsp(context, ref, playlist);
    case PlaylistAction.exportPortable:
      await _exportPortable(context, ref, playlist);
    case PlaylistAction.delete:
      await _delete(context, playlist, onDeleted);
  }
}

Future<void> _rename(BuildContext context, Playlist playlist) async {
  // Captured before the prompt: reading one off this context after it
  // is a use across the gap.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  final name = await promptPlaylistName(
    context,
    title: l10n.playlistRenameTitle,
    confirmLabel: l10n.playlistRename,
    initial: playlist.name,
  );
  if (name == null || name.isEmpty || name == playlist.name) return;
  await _guard(
    messenger,
    l10n,
    () => _edit(container, playlist.pid, name: name),
    // A name somebody just typed: the server's refusal names what was
    // wrong with it, and the table's sentence would not.
    refusal: true,
  );
}

Future<void> _setVisibility(BuildContext context, Playlist playlist) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _guard(
    ScaffoldMessenger.of(context),
    context.l10n,
    () => _edit(
      container,
      playlist.pid,
      visibility: playlist.isShared ? 'private' : 'shared',
    ),
  );
}

/// Renames or re-shares [pid] through the container rather than a
/// widget's ref, which a card's sheet can outlive.
Future<void> _edit(
  ProviderContainer container,
  String pid, {
  String? name,
  String? visibility,
}) async {
  await container
      .read(repositoryProvider)
      .updatePlaylist(pid, name: name, visibility: visibility);
  container
    ..invalidate(playlistDetailProvider(pid))
    ..invalidate(playlistsProvider);
}

Future<void> _delete(
  BuildContext context,
  Playlist playlist,
  VoidCallback? onDeleted,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.playlistDeleteTitle),
      content: Text(l10n.playlistDeleteBody),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        WaxButton(
          label: l10n.playlistDelete,
          semanticsId: SemanticsIds.playlistDeleteConfirm,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;
  var deleted = false;
  await _guard(messenger, l10n, () async {
    await container.read(repositoryProvider).deletePlaylist(playlist.pid);
    container.invalidate(playlistsProvider);
    deleted = true;
  });
  // Only while the asker is up: a back gesture during the delete would
  // otherwise have the screen it landed on leave instead.
  if (deleted && context.mounted) onDeleted?.call();
}

/// Offers the playlist as M3U for copying: the web build has no
/// file-save surface and the clipboard reaches every M3U player.
Future<void> _exportM3u(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final String content;
  try {
    content = await ref
        .read(repositoryProvider)
        .exportPlaylistM3u(playlist.pid);
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    return;
  }
  if (!context.mounted) return;
  await _showDocument(
    context,
    messenger: messenger,
    title: l10n.playlistExportM3u,
    document: content,
    copied: l10n.playlistCopiedM3u,
  );
}

/// Offers a smart playlist's rule as a Navidrome document. A lossy
/// conversion is reported first, so only somebody who has seen what
/// would go asks for the export that drops it.
Future<void> _exportNsp(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final repository = ref.read(repositoryProvider);
  final pid = playlist.pid;
  final NspReport report;
  try {
    report = await repository.reportPlaylistNspExport(pid);
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    return;
  }
  var partial = false;
  if (!report.isLossless) {
    if (!context.mounted) return;
    // Gaps and notes together: the difference between a loss that
    // refuses and one that does not is the converter's business, and
    // somebody deciding whether to accept the loss wants the list.
    final proceed = await _confirmNspLoss(context, report.all);
    if (proceed != true) return;
    // Only the gaps need it. A report of notes alone describes a loss
    // the strict export makes anyway, and asking for the lossy path
    // to get the same document would say the wrong thing.
    partial = report.gaps.isNotEmpty;
  }
  final Map<String, Object?> document;
  try {
    document = await repository.exportPlaylistNsp(pid, partial: partial);
  } on WaxDeckApiException catch (e) {
    // The server's sentence: this endpoint's 501 is about the rule,
    // and the table's general wording would blame the server.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
    return;
  }
  if (!context.mounted) return;
  await _showDocument(
    context,
    messenger: messenger,
    title: l10n.playlistExportNsp,
    // Indented, because this one is read before it is pasted: the
    // dialog above said what the document loses, and a single line
    // would make checking what it kept impossible.
    document: const JsonEncoder.withIndent('  ').convert(document),
    copied: l10n.playlistCopiedNsp,
  );
}

/// Lists what the export would drop, in the converter's own sentences,
/// each under the rule editor's name for the field it is about, and
/// offers to do it anyway.
Future<bool?> _confirmNspLoss(BuildContext context, List<NspGap> gaps) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      // The dialog's own context: it is a route of its own, so the
      // theme it draws under is the one below it rather than the
      // screen's.
      final colors = WaxColors.of(context);
      return AlertDialog(
        title: Text(l10n.playlistExportNspLossTitle),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Semantics(
              identifier: SemanticsIds.playlistExportNspLoss,
              container: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.playlistExportNspLossCount(gaps.length),
                    style: WaxType.body.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: WaxSpace.s12),
                  for (final (index, gap) in gaps.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: WaxSpace.s12),
                      child: Semantics(
                        identifier: SemanticsIds.playlistExportNspLossRow(
                          index,
                        ),
                        container: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (gap.field != null && gap.field!.isNotEmpty)
                              Text(
                                ruleFieldLabel(l10n, gap.field!),
                                style: WaxType.label.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            Text(
                              gap.reason,
                              style: WaxType.body.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WaxButton(
            label: l10n.playlistExportNspProceed,
            semanticsId: SemanticsIds.playlistExportNspProceed,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
}

/// Both text exports land in the design system's one document dialog.
Future<void> _showDocument(
  BuildContext context, {
  required ScaffoldMessengerState messenger,
  required String title,
  required String document,
  required String copied,
}) => showDocumentDialog(
  context,
  title: title,
  document: document,
  closeLabel: context.l10n.commonClose,
  copyLabel: context.l10n.playlistExportCopy,
  copySemanticsId: SemanticsIds.playlistExportCopy,
  onCopied: () => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied))),
);

/// Copies the portable refs, for importing on another server.
Future<void> _exportPortable(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final PortablePlaylist portable;
  try {
    portable = await ref
        .read(repositoryProvider)
        .exportPlaylistPortable(playlist.pid);
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    return;
  }
  await Clipboard.setData(ClipboardData(text: portableJson(portable)));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.playlistCopiedPortable)));
}

/// What the picker offers; the server decides what it accepts.
const _coverExtensions = kArtworkExtensions;

/// Uploads a picked image as the cover. Read whole rather than
/// streamed: covers are small and the server caps the body.
Future<void> _setCover(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final picker = ref.read(filePickerProvider);
  if (picker == null) return;
  final pid = playlist.pid;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Picking and reading are inside the guard: a permission error or a
  // file that vanished throws from the platform, not from the API.
  try {
    final file = await picker.pickFile(
      extensions: _coverExtensions,
      label: l10n.playlistCoverImage,
      anyLabel: l10n.uploadsFileTypeAny,
    );
    final openRead = file?.openRead;
    if (file == null || openRead == null) return;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in openRead()) {
      bytes.add(chunk);
    }
    await ref
        .read(playlistDetailProvider(pid).notifier)
        .setCover(bytes.takeBytes());
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  } on Exception catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.playlistCoverUnreadable('$e'))),
      );
  }
}

/// Drops an uploaded cover. The playlist does not go bare: the server
/// rebuilds the one it makes from the member covers.
Future<void> _resetCover(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final pid = playlist.pid;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await ref.read(playlistDetailProvider(pid).notifier).resetCover();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.playlistCoverReset)));
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}

/// Runs an edit and says why it failed. [refusal] for a write
/// carrying something just typed, where the server's own sentence
/// names the value it would not take.
Future<void> _guard(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Future<void> Function() edit, {
  bool refusal = false,
}) async {
  try {
    await edit();
  } on WaxDeckApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            refusal ? explainRefusal(l10n, e) : explainError(l10n, e),
          ),
        ),
      );
  }
}

/// The portable export, as the JSON the importer on another server reads.
String portableJson(PortablePlaylist portable) => jsonEncode(<String, Object?>{
  'name': portable.name,
  'refs': <Object?>[
    for (final ref in portable.refs)
      <String, Object?>{
        'kind': ref.kind,
        if (ref.essence != null) 'essence': ref.essence,
        if (ref.fingerprint != null) 'fingerprint': ref.fingerprint,
        if (ref.fingerprintAlgo != null) 'fingerprintAlgo': ref.fingerprintAlgo,
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
