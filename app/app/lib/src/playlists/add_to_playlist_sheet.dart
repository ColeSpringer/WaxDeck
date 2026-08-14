import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'playlist_create.dart';
import 'playlists_controller.dart';

/// Opens the add-to-playlist sheet for [item]. A sheet because it is a
/// list to pick from, opened from a row's menu on a phone.
Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required ItemSummary item,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => AddToPlaylistSheet(item: item),
);

/// Picks a manual playlist to append [item] to, marking the ones that
/// already hold it, with an inline new-playlist row.
class AddToPlaylistSheet extends ConsumerStatefulWidget {
  const AddToPlaylistSheet({required this.item, super.key});

  final ItemSummary item;

  @override
  ConsumerState<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<AddToPlaylistSheet> {
  /// The playlists already holding this item, or null while the probe is
  /// out; both draw the same.
  Set<String>? _holding;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // Marks the lists that already hold it; a failure leaves the marks
    // off, since the sheet's job is adding.
    unawaited(_probe());
  }

  Future<void> _probe() async {
    try {
      final page = await ref
          .read(repositoryProvider)
          .listPlaylists(containsItem: widget.item.pid, limit: 200);
      if (!mounted) return;
      setState(
        () => _holding = <String>{for (final pl in page.playlists) pl.pid},
      );
    } on WaxDeckApiException {
      // Nothing to say: the sheet works without the marks.
    }
  }

  Future<void> _add(Playlist playlist) async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(playlistsProvider.notifier).appendTo(playlist, <String>[
        widget.item.pid,
      ]);
      // A request outlives a sheet somebody swiped away, and popping
      // then takes the screen underneath.
      if (mounted) navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.playlistAddedTo(widget.item.title, playlist.name),
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAdd() async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final name = await promptPlaylistName(
      context,
      title: l10n.playlistsNew,
      confirmLabel: l10n.playlistCreateAction,
    );
    if (name == null || name.isEmpty || !mounted) return;
    // Held across the create so a second confirm posts nothing.
    setState(() => _busy = true);
    try {
      await ref
          .read(playlistsProvider.notifier)
          .create(
            name: name,
            kind: 'static',
            itemPids: <String>[widget.item.pid],
          );
      if (mounted) navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.playlistAddedTo(widget.item.title, name)),
          ),
        );
    } on WaxDeckApiException catch (e) {
      // A name somebody just typed, so the server's own refusal.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final playlists = ref.watch(playlistsProvider);
    // Only the lists this caller can append to: a smart playlist's
    // membership is its rule, and somebody else's is theirs.
    final targets = <Playlist>[
      for (final pl in playlists.value ?? const <Playlist>[])
        if (pl.isOwner && !pl.isSmart) pl,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WaxSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
              child: Text(
                l10n.playlistAddToTitle,
                style: WaxType.headline.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: WaxSpace.s8),
            switch (playlists) {
              AsyncData() when targets.isEmpty => Padding(
                padding: const EdgeInsets.fromLTRB(
                  WaxSpace.s16,
                  WaxSpace.s8,
                  WaxSpace.s16,
                  WaxSpace.s8,
                ),
                child: Text(
                  l10n.playlistNoManualLists,
                  style: WaxType.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              AsyncData() => Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: targets.length,
                  itemBuilder: (context, index) {
                    final playlist = targets[index];
                    final held = _holding?.contains(playlist.pid) ?? false;
                    return WaxOptionRow(
                      title: playlist.name,
                      // Said, not only ticked: a check mark is a fact
                      // only sighted people get.
                      subtitle: held ? l10n.playlistAlreadyIn : null,
                      glyph: WaxIcons.playlists,
                      selected: held,
                      semanticsId: SemanticsIds.addToPlaylistTarget(
                        playlist.pid,
                      ),
                      trailing: held
                          ? WaxIcon(
                              WaxIcons.check,
                              size: 16,
                              color: colors.accent,
                            )
                          : null,
                      // Still tappable: the contract allows a playlist
                      // to repeat a track.
                      onTap: _busy ? null : () => unawaited(_add(playlist)),
                    );
                  },
                ),
              ),
              AsyncError() => Padding(
                padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                child: Text(
                  l10n.playlistsLoadErrorSentence,
                  style: WaxType.bodySmall.copyWith(color: colors.error),
                ),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(WaxSpace.s16),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
            const SizedBox(height: WaxSpace.s8),
            WaxOptionRow(
              title: l10n.playlistsNew,
              glyph: WaxIcons.add,
              semanticsId: SemanticsIds.addToPlaylistNew,
              onTap: _busy ? null : () => unawaited(_createAndAdd()),
            ),
          ],
        ),
      ),
    );
  }
}
