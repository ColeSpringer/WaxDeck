import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'playback_session.dart';

/// One book's bookmarks, in timeline order.
///
/// A live read rather than mirrored state, and deliberately: a book
/// holds a handful of these, the sheet that shows them is opened on
/// purpose, and a mirror table for them would be a sync kind, a delta
/// shape, and an offline write queue for a feature nobody uses offline
/// today. Marking a place needs the server, and so far that is the
/// whole of it.
/// Auto-disposed, which is what makes "on open" true: the button that
/// watches it goes with the player, so the next book player fetches
/// again and a mark made on another device is there when it does. Kept
/// alive, the first read would be the only one this process ever made.
final bookmarksProvider = AsyncNotifierProvider.autoDispose
    .family<BookmarksController, List<Bookmark>, String>(
      BookmarksController.new,
    );

class BookmarksController extends AsyncNotifier<List<Bookmark>> {
  BookmarksController(this.pid);

  final String pid;

  @override
  Future<List<Bookmark>> build() =>
      ref.watch(repositoryProvider).listBookmarks(pid);

  /// Marks [positionMs] on the book timeline. Errors propagate so the
  /// caller can say what the server refused (a full book, a position
  /// past the end).
  Future<void> add(int positionMs, {String? note}) async {
    await _settled();
    final created = await ref
        .read(repositoryProvider)
        .createBookmark(pid, positionMs, note: note);
    // Placed rather than refetched: the answer carries the whole row,
    // and a listener marking a passage mid-listen should not wait out a
    // round trip to see it land.
    final marks = <Bookmark>[...?state.value, created]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    state = AsyncData(marks);
  }

  Future<void> remove(String bookmarkId) async {
    await _settled();
    await ref.read(repositoryProvider).deleteBookmark(pid, bookmarkId);
    state = AsyncData(<Bookmark>[
      for (final mark in state.value ?? const <Bookmark>[])
        if (mark.id != bookmarkId) mark,
    ]);
  }

  /// Waits for the first read to land before editing what it will
  /// publish.
  ///
  /// The button that opens the sheet is drawn while that read is still
  /// in flight, so a quick tap-and-mark reaches here first. Without
  /// this, the edit places itself on an empty list and the read - which
  /// was issued before the mark existed and cannot carry it - lands
  /// afterwards and takes it straight back off the screen.
  ///
  /// A failed read is not this call's to report: the edit goes ahead
  /// and the sheet already draws the error the read left behind.
  Future<void> _settled() async {
    try {
      await future;
    } on Object {
      // The edit stands on its own; what the listing could not fetch is
      // the listing's problem to show.
    }
  }
}

/// The bookmark button and its sheet.
///
/// Books only: a bookmark is a place in something long enough to lose
/// your place in, and the endpoints are the book's own.
class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({required this.session, super.key});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marks = ref.watch(bookmarksProvider(session.item.pid)).value;
    final count = marks?.length ?? 0;
    return WaxIconButton(
      glyph: WaxIcons.bookmark,
      label: count == 0
          ? context.l10n.playerBookmarks
          : context.l10n.playerBookmarksCount(count),
      badge: count == 0 ? null : '$count',
      semanticsId: SemanticsIds.playerBookmarks,
      onPressed: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _BookmarkSheet(session: session),
        ),
      ),
    );
  }
}

class _BookmarkSheet extends ConsumerStatefulWidget {
  const _BookmarkSheet({required this.session});

  final PlaybackSession session;

  @override
  ConsumerState<_BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends ConsumerState<_BookmarkSheet> {
  final _note = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _pid => widget.session.item.pid;

  /// Adds a mark where the book stands right now.
  ///
  /// The position is read at press time rather than when the sheet
  /// opened: the book keeps playing under it, and a listener who takes
  /// twenty seconds to type a note means the place they are typing
  /// about, not the place they opened the sheet at.
  Future<void> _add() async {
    final l10n = context.l10n;
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final note = _note.text.trim();
    try {
      await ref
          .read(bookmarksProvider(_pid).notifier)
          .add(
            widget.session.displayPosition.inMilliseconds,
            note: note.isEmpty ? null : note,
          );
      // The sheet can be dismissed while the mark is in flight, and the
      // controller goes with it: clearing a disposed one throws where
      // the field is simply no longer there to clear.
      if (mounted) _note.clear();
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(bookmarksProvider(_pid).notifier).remove(id);
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
    }
  }

  void _jumpTo(int positionMs) {
    unawaited(widget.session.seek(Duration(milliseconds: positionMs)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final marks = ref.watch(bookmarksProvider(_pid));
    return SafeArea(
      child: Padding(
        // The keyboard's own inset, so the note field stays above it
        // rather than under it on a phone.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Semantics(
          // Its own handle, not the button's: both are in the tree
          // while the sheet is up, and one identifier over two nodes is
          // a spec that resolves to two elements and fails strict.
          identifier: SemanticsIds.playerBookmarkSheet,
          container: true,
          explicitChildNodes: true,
          label: l10n.playerBookmarks,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SectionHeader(title: l10n.playerBookmarks),
                    WaxTextField(
                      controller: _note,
                      label: l10n.playerBookmarkNote,
                      semanticsId: SemanticsIds.playerBookmarkNote,
                      onSubmitted: (_) => unawaited(_add()),
                    ),
                    const SizedBox(height: WaxSpace.s8),
                    WaxButton(
                      label: l10n.playerBookmarkAdd(
                        formatTimecode(widget.session.displayPosition),
                      ),
                      semanticsId: SemanticsIds.playerBookmarkAdd,
                      expand: true,
                      onPressed: _saving ? null : () => unawaited(_add()),
                    ),
                    const SizedBox(height: WaxSpace.s16),
                  ],
                ),
              ),
              Flexible(
                child: switch (marks) {
                  AsyncData(:final value) when value.isEmpty => Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WaxSpace.s24,
                      0,
                      WaxSpace.s24,
                      WaxSpace.s24,
                    ),
                    child: Text(
                      l10n.playerBookmarksEmpty,
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  AsyncData(:final value) => ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: WaxSpace.s16),
                    itemCount: value.length,
                    itemBuilder: (context, index) => _BookmarkRow(
                      mark: value[index],
                      index: index,
                      onJump: () => _jumpTo(value[index].positionMs),
                      onRemove: () => unawaited(_remove(value[index].id)),
                    ),
                  ),
                  AsyncError(:final error) => Padding(
                    padding: const EdgeInsets.all(WaxSpace.s24),
                    child: Text(
                      error is WaxDeckApiException
                          ? explainError(l10n, error)
                          : l10n.playerBookmarksError,
                      style: WaxType.caption.copyWith(color: colors.error),
                    ),
                  ),
                  _ => const Padding(
                    padding: EdgeInsets.all(WaxSpace.s24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({
    required this.mark,
    required this.index,
    required this.onJump,
    required this.onRemove,
  });

  final Bookmark mark;
  final int index;
  final VoidCallback onJump;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final stamp = formatTimecode(Duration(milliseconds: mark.positionMs));
    final note = mark.note;
    return Row(
      children: <Widget>[
        Expanded(
          child: WaxTappable(
            semanticsId: SemanticsIds.playerBookmark(index),
            label: note == null
                ? l10n.playerBookmarkPlayFrom(stamp)
                : l10n.playerBookmarkNoteAt(note, stamp),
            onPressed: onJump,
            borderRadius: WaxRadius.thumb,
            child: InkWell(
              borderRadius: WaxRadius.thumb,
              onTap: onJump,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WaxSpace.s24,
                  vertical: WaxSpace.s12,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      stamp,
                      style: WaxType.monoTime.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: WaxSpace.s12),
                    Expanded(
                      child: Text(
                        note ?? l10n.playerBookmarkNoNote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.body.copyWith(
                          color: note == null
                              ? colors.textTertiary
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: WaxSpace.s12),
          child: WaxIconButton(
            glyph: WaxIcons.delete,
            label: context.l10n.playerBookmarkRemove(stamp),
            size: 18,
            semanticsId: SemanticsIds.playerBookmarkDelete(index),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
