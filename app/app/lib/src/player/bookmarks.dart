import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../sync/server_event_bus.dart';
import '../sync/sync_providers.dart';
import 'playback_session.dart';

/// One book's bookmarks as this listener has them, in timeline order. On
/// native they live in the mirror, which sends what waits; on web they
/// are the server's. Auto-disposed, so the next player reads again.
final bookmarksProvider = AsyncNotifierProvider.autoDispose
    .family<BookmarksController, List<LocalBookmark>, String>(
      BookmarksController.new,
      retry: retryUnlessRefused,
    );

/// The most bookmarks a book holds per listener, as the server counts.
const bookmarkCap = 200;

/// A mark refused here because the book already holds [bookmarkCap].
class BookmarksFullException implements Exception {
  const BookmarksFullException();
}

class BookmarksController extends AsyncNotifier<List<LocalBookmark>> {
  BookmarksController(this.pid);

  final String pid;

  @override
  Future<List<LocalBookmark>> build() async {
    final engine = ref.watch(syncEngineProvider);
    final account = ref.watch(signedInAccountProvider);
    final repository = ref.watch(repositoryProvider);
    // This build's own ref: [ref] answers for whichever build is newest.
    final built = ref;
    if (engine == null || account == null) {
      final bus = ref.watch(serverEventBusProvider);
      final served = await repository.listBookmarks(pid);
      if (!built.mounted) return const [];
      // A change on another device arrives as the book's whole list.
      final changes = bus.events
          .where((e) => e.kind == 'bookmarks' && e.pid == pid)
          .listen((e) {
            if (!built.mounted) return;
            state = AsyncData([
              for (final mark in e.bookmarks ?? const <Bookmark>[])
                LocalBookmark(mark),
            ]);
          });
      built.onDispose(changes.cancel);
      return [for (final mark in served) LocalBookmark(mark)];
    }
    // Read, not watched: a link coming or going is no reason to read again.
    if (ref.read(offlineProvider)) {
      unawaited(_refresh(engine, repository, account));
    } else {
      try {
        await _take(engine, repository, account);
      } on WaxDeckApiException catch (e) {
        if (_refused(e)) rethrow;
      }
    }
    if (!built.mounted) return const [];
    final changes = engine.bookmarksChanged
        .where((book) => book == pid)
        .listen((_) => unawaited(_reread(engine, account)));
    built.onDispose(changes.cancel);
    return engine.localBookmarks(pid, owner: account);
  }

  static bool _refused(WaxDeckApiException e) =>
      (e.statusCode ?? 0) >= 400 && (e.statusCode ?? 0) < 500;

  Future<void> _take(
    SyncEngine engine,
    WaxDeckRepository repository,
    String account,
  ) async {
    final served = await repository.listBookmarks(pid);
    await engine.storeBookmarks(pid, served, owner: account);
  }

  /// Reads the server's list behind the mirror's: the link is down, but a
  /// plain request may still land.
  Future<void> _refresh(
    SyncEngine engine,
    WaxDeckRepository repository,
    String account,
  ) async {
    try {
      await _take(engine, repository, account);
    } on WaxDeckApiException {
      // The mirror stands until the next read.
    }
  }

  /// Takes up what the mirror now holds: a mark sent, refused, or pulled.
  Future<void> _reread(SyncEngine engine, String account) async {
    final marks = await engine.localBookmarks(pid, owner: account);
    if (ref.mounted) state = AsyncData(marks);
  }

  ({SyncEngine engine, String account})? _mirror() {
    final engine = ref.read(syncEngineProvider);
    final account = ref.read(signedInAccountProvider);
    return engine == null || account == null
        ? null
        : (engine: engine, account: account);
  }

  static bool _full(List<LocalBookmark> held) =>
      held.where((m) => m.sync != BookmarkSync.refused).length >= bookmarkCap;

  /// Marks [positionMs] under an id minted here, so a mark sent later is
  /// the same mark. Throws [BookmarksFullException] for a full book; on
  /// web, what the server refused.
  Future<void> add(int positionMs, {String? note}) async {
    final mark = Bookmark(
      id: 'bm-${newUlid()}',
      positionMs: positionMs,
      note: note,
      createdAt: DateTime.now(),
    );
    final mirror = _mirror();
    if (mirror == null) return _addServed(mark);
    final held = await mirror.engine.localBookmarks(pid, owner: mirror.account);
    if (_full(held)) throw const BookmarksFullException();
    // Held before it is sent: nothing the sheet or the link does loses it.
    await mirror.engine.queueBookmarkCreate(pid, mark, owner: mirror.account);
    await _send(mirror.engine);
  }

  /// Removes a mark, and any create of it still waiting to be sent.
  Future<void> remove(String bookmarkId) async {
    final mirror = _mirror();
    if (mirror == null) return _removeServed(bookmarkId);
    await mirror.engine.queueBookmarkDelete(
      pid,
      bookmarkId,
      owner: mirror.account,
    );
    await _send(mirror.engine);
  }

  /// Sends what this book has waiting. Refusals settle on their rows; a
  /// write the server cannot take now waits, shown as not sent.
  Future<void> _send(SyncEngine engine) async {
    try {
      await engine.sendBookmarks(pid);
    } on WaxDeckApiException {
      // Sent with the next flush.
    }
  }

  Future<void> _addServed(Bookmark mark) async {
    final repository = ref.read(repositoryProvider);
    await _settled();
    if (!ref.mounted) return;
    if (_full(state.value ?? const [])) throw const BookmarksFullException();
    // Placed rather than refetched, unless there is no list to place it in.
    final placed = state.hasValue;
    if (placed) _place(LocalBookmark(mark));
    try {
      final created = await repository.createBookmark(
        pid,
        mark.positionMs,
        note: mark.note,
        id: mark.id,
      );
      if (!ref.mounted) return;
      placed ? _place(LocalBookmark(created)) : ref.invalidateSelf();
    } on WaxDeckApiException {
      if (placed && ref.mounted) _drop(mark.id);
      rethrow;
    }
  }

  Future<void> _removeServed(String bookmarkId) async {
    final repository = ref.read(repositoryProvider);
    await _settled();
    if (!ref.mounted) return;
    final gone = state.value?.where((m) => m.mark.id == bookmarkId).firstOrNull;
    _drop(bookmarkId);
    try {
      await repository.deleteBookmark(pid, bookmarkId);
    } on WaxDeckApiException {
      if (gone != null && ref.mounted) _place(gone);
      rethrow;
    }
  }

  /// Puts [mark] in place of any row with its id, in timeline order.
  void _place(LocalBookmark mark) {
    state = AsyncData(
      <LocalBookmark>[
        for (final m in state.value ?? const <LocalBookmark>[])
          if (m.mark.id != mark.mark.id) m,
        mark,
      ]..sort((a, b) => a.mark.positionMs.compareTo(b.mark.positionMs)),
    );
  }

  void _drop(String id) {
    state = AsyncData(<LocalBookmark>[
      for (final m in state.value ?? const <LocalBookmark>[])
        if (m.mark.id != id) m,
    ]);
  }

  /// Waits for the first read to land before editing what it will
  /// publish, else a read issued before a mark existed takes it off the
  /// screen. A failed read is the sheet's to show; the edit goes ahead.
  Future<void> _settled() async {
    try {
      await future;
    } on Object {
      // Shown by the sheet from the state the read left.
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
        showWaxSheet<void>(
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
    } on BookmarksFullException {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.playerBookmarksFull)));
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
                      held: value[index],
                      index: index,
                      onJump: () => _jumpTo(value[index].mark.positionMs),
                      onRemove: () => unawaited(_remove(value[index].mark.id)),
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
    required this.held,
    required this.index,
    required this.onJump,
    required this.onRemove,
  });

  final LocalBookmark held;
  final int index;
  final VoidCallback onJump;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final mark = held.mark;
    final stamp = formatTimecode(Duration(milliseconds: mark.positionMs));
    final note = mark.note;
    final caption = switch (held.sync) {
      BookmarkSync.synced => null,
      BookmarkSync.pending => l10n.playerBookmarkPending,
      BookmarkSync.refused => l10n.playerBookmarkRefused(
        explainRefusal(l10n, held.refusal ?? const Object()),
      ),
    };
    final label = note == null
        ? l10n.playerBookmarkPlayFrom(stamp)
        : l10n.playerBookmarkNoteAt(note, stamp);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              WaxTappable(
                semanticsId: SemanticsIds.playerBookmark(index),
                label: caption == null ? label : '$label, $caption',
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
              // Outside the tappable, which hides its children, and not
              // read aloud: the tappable's own label already says it.
              if (caption != null)
                Semantics(
                  identifier: SemanticsIds.playerBookmarkState(index),
                  container: true,
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WaxSpace.s24,
                      0,
                      WaxSpace.s24,
                      WaxSpace.s12,
                    ),
                    child: Text(
                      caption,
                      style: WaxType.caption.copyWith(
                        color: held.sync == BookmarkSync.refused
                            ? colors.error
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
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
