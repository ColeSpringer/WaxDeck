import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../auth/auth_controller.dart';
import '../home/pin_action.dart';
import '../player/download_action.dart';
import '../player/item_star_rating_row.dart';
import '../player/now_playing_controller.dart';
import '../player/play_progress.dart';
import '../player/play_state_controller.dart';
import '../podcasts/episode_screen.dart' show formatCueTimestamp;
import '../podcasts/show_notes.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../search/search_chrome.dart';
import '../sharing/share_dialog.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../tools/tasks_screen.dart' show toolTasksProvider;
import 'books_controller.dart';

/// What the book's overflow can do.
enum _BookAction {
  pin,
  markFinished,
  startOver,
  share,
  editMetadata,
  merge,
  split,
}

/// One audiobook: its cover, who made it, where the listener is in it,
/// and its chapters.
class BookScreen extends ConsumerWidget {
  const BookScreen({required this.pid, super.key});

  final String pid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(bookDetailProvider(pid));
    final book = detail.value;

    return WaxScaffold(
      title: book?.title ?? 'Audiobook',
      largeTitle: false,
      // Pops where something pushed this - a search hit, a shelf on
      // home - and goes to the hub where nothing did, so the arrow and
      // the system gesture agree from either entry point.
      onBack: () => context.leave(fallback: WaxRoute.books),
      actions: <Widget>[
        if (book != null) _BookOverflow(book: book),
        const SearchAction(),
      ],
      slivers: <Widget>[
        switch (detail) {
          AsyncData(:final value) => SliverList.list(
            children: <Widget>[
              _Header(book: value),
              _Description(book: value),
              _Chapters(book: value),
              _PartsNote(book: value),
              _Edition(book: value),
              const SizedBox(height: WaxSpace.s32),
            ],
          ),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: 'Could not load this book',
              message: error is WaxDeckApiException
                  ? error.message
                  : 'The server did not answer.',
              onRetry: () => ref.invalidate(bookDetailProvider(pid)),
            ),
          ),
          _ => const SliverFillRemaining(
            hasScrollBody: false,
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
      ],
    );
  }
}

/// Builds the summary the player needs from the book detail.
ItemSummary bookItemSummary(BookDetail book) => ItemSummary(
  pid: book.pid,
  mediaType: MediaType.audiobook,
  title: book.title,
  artist: book.authors.isEmpty ? null : book.authors.join(', '),
  album: book.series,
  durationMs: book.durationMs,
  artUrl: book.artUrl,
);

/// Starts [book] at [positionMs] on the book timeline and opens the
/// player.
///
/// A book queues as itself: its parts roll inside the session, so there
/// is nothing else in the queue for chapters to be.
void playBook(
  BuildContext context,
  WidgetRef ref,
  BookDetail book, {
  required int positionMs,
}) {
  ref
      .read(nowPlayingProvider.notifier)
      .play(
        [bookItemSummary(book)],
        source: QueueSource(
          kind: QueueSourceKind.book,
          label: book.title,
          pid: book.pid,
        ),
        positionMs: positionMs,
      );
  context.push(WaxRoute.nowPlaying);
}

/// Cover, contributors, where the listener stands, and the verbs.
class _Header extends ConsumerWidget {
  const _Header({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = _progressOf(ref, book.pid);
    final resume = ref.watch(bookResumeProvider(book.pid)).value;
    // The resume endpoint is the cross-device answer and names the
    // chapter; the batch play state is what the hub already holds. Either
    // one places the listener, so the screen draws whichever landed.
    final positionMs = resume?.positionMs ?? progress.positionMs;
    final started = positionMs > 0 && !progress.finished;
    // A finished book's checkpoint sits at its own end, and the button
    // says "Play". An explicit position overrides the session's own
    // finished guard, so this is where it is made.
    final playFromMs = progress.finished ? 0 : positionMs;

    return EntityHeader(
      title: book.title,
      subtitle: book.subtitle,
      metadata: _facts(
        book,
        positionMs: positionMs,
        finished: progress.finished,
      ),
      shape: ArtworkShape.portrait,
      domain: WaxDomain.audiobooks,
      artwork: ref.watch(artworkStoreProvider).source(book.artUrl),
      description: _people(book),
      actions: <Widget>[
        WaxButton(
          // The verb says where it will put you, and the chapter name is
          // the part that makes it a promise rather than a guess.
          label: started ? _resumeLabel(resume) : 'Play',
          icon: WaxIcons.play,
          semanticsId: SemanticsIds.bookResume,
          onPressed: () => playBook(context, ref, book, positionMs: playFromMs),
        ),
        if (book.series != null) _SeriesLink(book: book),
        DownloadAction(
          pid: book.pid,
          artUrl: book.artUrl,
          label: 'Download for offline',
          semanticsId: SemanticsIds.bookDownload,
        ),
        _SettingsButton(book: book),
        ItemStarRatingRow(pid: book.pid),
      ],
    );
  }

  /// "12 hr 40 min · 38 percent · 7 hr 50 min left", or the plain length
  /// where nothing has been heard.
  static String _facts(
    BookDetail book, {
    required int positionMs,
    required bool finished,
  }) {
    final total = Duration(milliseconds: book.durationMs);
    final parts = <String>[spellDuration(total)];
    if (finished) {
      parts.add('Finished');
    } else if (positionMs > 0 && book.durationMs > 0) {
      final percent = (positionMs / book.durationMs * 100).round().clamp(
        0,
        100,
      );
      parts.add('$percent percent');
      final left = book.durationMs - positionMs;
      if (left > 0) {
        parts.add('${spellDuration(Duration(milliseconds: left))} left');
      }
    }
    if (book.parts.length > 1) {
      parts.add('${book.parts.length} parts');
    }
    return parts.join(' · ');
  }

  /// Authors and narrators, as the header's own lines.
  static String? _people(BookDetail book) {
    final lines = <String>[
      if (book.authors.isNotEmpty) 'By ${book.authors.join(', ')}',
      if (book.narrators.isNotEmpty) 'Read by ${book.narrators.join(', ')}',
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// "Resume Chapter 12" where the resume point named its chapter, and
  /// plain "Resume" where it did not - a book with no chapter marks, or a
  /// screen whose resume read has not landed and is drawing the batch
  /// play state's position instead.
  static String _resumeLabel(BookResume? resume) {
    final chapter = resume?.chapter?.title;
    return chapter == null ? 'Resume' : 'Resume $chapter';
  }
}

/// The series line, which navigates to the books that share it.
class _SeriesLink extends ConsumerWidget {
  const _SeriesLink({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = book.series!;
    final sequence = book.seriesSequence;
    return WaxButton(
      label: sequence == null ? series : 'Book $sequence of $series',
      kind: WaxButtonKind.text,
      // A series is not a location: the catalog has no series dimension
      // to drill, so this narrows the hub to the author instead, which
      // is where the rest of the series is. The route lands when the
      // dimension does.
      // Narrows rather than toggles: toggling would clear the filter when
      // the hub already held this author.
      onPressed: () {
        final author = book.authors.firstOrNull;
        if (author != null) {
          ref.read(bookViewProvider.notifier).narrowToAuthor(author);
        }
        context.go(WaxRoute.books);
      },
    );
  }
}

/// The per-book playback settings sheet's trigger.
class _SettingsButton extends ConsumerWidget {
  const _SettingsButton({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context, WidgetRef ref) => WaxIconButton(
    glyph: WaxIcons.speed,
    label: 'Playback settings',
    semanticsId: SemanticsIds.bookSettingsOpen,
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BookSettingsSheet(
        pid: book.pid,
        initial: book.settings ?? const BookSettings(),
      ),
    ),
  );
}

/// The blurb, sanitized server-side and rendered as blocks.
class _Description extends ConsumerWidget {
  const _Description({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final html = book.descriptionHtml;
    if (html == null || html.isEmpty) return const SizedBox.shrink();
    final sizeClass = WaxSizeClass.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s16,
        sizeClass.gutter.horizontal / 2,
        0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WaxSpace.readingWidth),
        child: ShowNotesView(
          html: html,
          onOpenLink: ref.read(urlOpenerProvider).open,
        ),
      ),
    );
  }
}

/// The chapters, with the one holding the listener's place marked.
class _Chapters extends ConsumerWidget {
  const _Chapters({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (book.chapters.isEmpty) return const SizedBox.shrink();
    final sizeClass = WaxSizeClass.of(context);
    final resume = ref.watch(bookResumeProvider(book.pid)).value;
    final positionMs =
        resume?.positionMs ?? _progressOf(ref, book.pid).positionMs;
    final current = _chapterAt(book.chapters, positionMs);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sizeClass.gutter.horizontal / 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: WaxSpace.s24),
          SectionHeader(
            title: 'Chapters',
            overline: '${book.chapters.length} in this book',
          ),
          for (var i = 0; i < book.chapters.length; i++)
            MediaListRow(
              data: MediaTileData(
                title:
                    book.chapters[i].title ??
                    'Chapter ${book.chapters[i].index + 1}',
                trailingText: _chapterLength(book, i),
                semanticsId: SemanticsIds.chapter(book.chapters[i].index),
              ),
              // The timecode where a track number would be: it is what
              // orders the list, and a chapter has no number of its own
              // that a listener would recognise.
              leadingText: formatCueTimestamp(book.chapters[i].startMs),
              // Selected, not playing. `playing` means the engine is on
              // this item and draws the animated bars over the leading
              // slot - which would take the timecode away from the one
              // row whose position a listener most wants to see, and
              // claim playback for a chapter that may be nothing but a
              // saved place.
              selected: i == current,
              onTap: () => playBook(
                context,
                ref,
                book,
                positionMs: book.chapters[i].startMs,
              ),
            ),
        ],
      ),
    );
  }

  /// Which chapter holds [positionMs], or -1 before anything is heard.
  static int _chapterAt(List<ChapterMark> chapters, int positionMs) {
    if (positionMs <= 0) return -1;
    for (var i = chapters.length - 1; i >= 0; i--) {
      if (positionMs >= chapters[i].startMs) return i;
    }
    return -1;
  }

  /// How long chapter [at] runs: to the next chapter's start, or to the
  /// end of the book for the last one.
  static String? _chapterLength(BookDetail book, int at) {
    final chapter = book.chapters[at];
    final endMs =
        chapter.endMs ??
        (at + 1 < book.chapters.length
            ? book.chapters[at + 1].startMs
            : book.durationMs);
    final length = endMs - chapter.startMs;
    return length > 0 ? formatTimecode(Duration(milliseconds: length)) : null;
  }
}

/// The footnote a multi-file book gets, so a listener who wonders why
/// their book is three files has the answer where they are looking.
class _PartsNote extends StatelessWidget {
  const _PartsNote({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context) {
    if (book.parts.length <= 1) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s16,
        sizeClass.gutter.horizontal / 2,
        0,
      ),
      child: Semantics(
        identifier: SemanticsIds.bookPartsNote,
        child: Text(
          'This book is ${book.parts.length} files, played as one '
          'timeline. Positions and chapters span all of them.',
          style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}

/// The technical rows, behind an expander: the power-user channel the
/// first layer never pays for.
class _Edition extends StatelessWidget {
  const _Edition({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      if (book.publisher != null) (label: 'Publisher', value: book.publisher!),
      if (book.edition != null) (label: 'Edition', value: book.edition!),
      if (book.isbn != null) (label: 'ISBN', value: book.isbn!),
      if (book.asin != null) (label: 'ASIN', value: book.asin!),
      if (book.abridged != null)
        (label: 'Abridged', value: book.abridged! ? 'Yes' : 'No'),
      if (book.parts.length > 1)
        (label: 'Files', value: '${book.parts.length}'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sizeClass.gutter.horizontal / 2,
        WaxSpace.s16,
        sizeClass.gutter.horizontal / 2,
        0,
      ),
      child: Semantics(
        identifier: SemanticsIds.bookEdition,
        child: ExpansionTile(
          key: const Key(SemanticsIds.bookEdition),
          tilePadding: EdgeInsets.zero,
          title: Text(
            'About this edition',
            style: WaxType.headline.copyWith(color: colors.textPrimary),
          ),
          children: <Widget>[
            for (final row in rows)
              MonoDetailRow(label: row.label, value: row.value),
          ],
        ),
      ),
    );
  }
}

/// Mark finished, start over, share, edit, and the admin file tools.
class _BookOverflow extends ConsumerWidget {
  const _BookOverflow({required this.book});

  final BookDetail book;

  bool get _canMerge => book.parts.length > 1;
  bool get _canSplit => book.parts.length <= 1 && book.chapters.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    return WaxMenuButton<_BookAction>(
      glyph: WaxIcons.more,
      label: 'More',
      semanticsId: SemanticsIds.bookOverflow,
      items: <WaxMenuItem<_BookAction>>[
        pinMenuItem<_BookAction>(
          ref,
          book.pid,
          value: _BookAction.pin,
          semanticsId: SemanticsIds.bookPin,
        ),
        WaxMenuItem<_BookAction>(
          value: _BookAction.markFinished,
          label: 'Mark finished',
          glyph: WaxIcons.check,
          semanticsId: SemanticsIds.bookMarkFinished,
        ),
        WaxMenuItem<_BookAction>(
          value: _BookAction.startOver,
          label: 'Start over',
          glyph: WaxIcons.refresh,
          semanticsId: SemanticsIds.bookStartOver,
        ),
        const WaxMenuItem<_BookAction>(
          value: _BookAction.share,
          label: 'Share link',
          glyph: WaxIcons.share,
        ),
        if (isAdmin) ...<WaxMenuItem<_BookAction>>[
          const WaxMenuItem<_BookAction>(
            value: _BookAction.editMetadata,
            label: 'Edit metadata',
            glyph: WaxIcons.edit,
          ),
          if (_canMerge)
            const WaxMenuItem<_BookAction>(
              value: _BookAction.merge,
              label: 'Merge into one chaptered file',
              glyph: WaxIcons.sort,
            ),
          if (_canSplit)
            const WaxMenuItem<_BookAction>(
              value: _BookAction.split,
              label: 'Split at chapters',
              glyph: WaxIcons.sort,
            ),
        ],
      ],
      onSelected: (action) => _run(context, ref, action),
    );
  }

  void _run(BuildContext context, WidgetRef ref, _BookAction action) {
    switch (action) {
      case _BookAction.pin:
        unawaited(togglePin(context, ref, book.pid, label: book.title));
      case _BookAction.markFinished:
        unawaited(
          _writePosition(context, ref, book.durationMs, 'Marked finished'),
        );
      case _BookAction.startOver:
        unawaited(_writePosition(context, ref, 0, 'Back to the beginning'));
      case _BookAction.share:
        unawaited(showShareLinkDialog(context, pid: book.pid));
      case _BookAction.editMetadata:
        context.push(WaxRoute.metadata(book.pid));
      case _BookAction.merge:
        unawaited(
          _runTool(
            context,
            ref,
            () => ref.read(repositoryProvider).mergeBook(book.pid),
          ),
        );
      case _BookAction.split:
        unawaited(
          _runTool(
            context,
            ref,
            () => ref.read(repositoryProvider).splitBook(book.pid),
          ),
        );
    }
  }

  /// Both position verbs are one write, with the previous position in
  /// hand so the toast can undo it.
  ///
  /// Read before the write rather than from a held state: the resume
  /// point is the cross-device one, and the undo has to put back where
  /// the listener actually was, not where this screen last drew.
  Future<void> _writePosition(
    BuildContext context,
    WidgetRef ref,
    int positionMs,
    String message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // The container rather than `ref`, and captured here rather than read
    // inside the toast: the undo outlives the row that offered it. A
    // `WidgetRef` is dead the moment its element is disposed, so a book
    // screen left behind while the toast is still up would take the undo
    // with it - the same lesson the mark-older dialog is built on.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(repositoryProvider);
    try {
      final before = await repository.getPlayState(book.pid);
      await repository.putPlayState(book.pid, positionMs);
      _refresh(container);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => unawaited(_undo(container, repository, before)),
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Puts back everything the verb moved, not only the position.
  ///
  /// Writing the old position back is not enough on its own: marking
  /// finished writes a position at the book's end, which sets `played`
  /// and `finished`, and the completion rules are monotonic - they mark
  /// and never un-mark - so a mis-tap used to leave the book in the
  /// Finished shelf forever with the hub's unfinished filter hiding it.
  /// The flags go back through their own verb, with the play count the
  /// mark added cleared rather than left standing.
  ///
  /// Position first, flags second: a checkpoint re-derives completion
  /// from the position it writes, so the flag write has to be the one
  /// nothing runs after. Doing it the other way round leaves the write
  /// that can re-mark as the last word.
  ///
  /// Attempted independently, which is the half that matters more. One
  /// `try` around both meant any failure of the first - a 503, a network
  /// blip, or the catalog's own refusal of a played row with a zero
  /// count - skipped the second and landed in an empty catch: the toast
  /// dismissed and nothing moved at all, where before this verb existed
  /// the position at least went back.
  Future<void> _undo(
    ProviderContainer container,
    WaxDeckRepository repository,
    PlayState before,
  ) async {
    var moved = false;
    try {
      await repository.putPlayState(book.pid, before.positionMs);
      moved = true;
    } on WaxDeckApiException {
      // Nothing to say from a dismissed toast; the flag write still runs.
    }
    try {
      await repository.setPlayed(
        book.pid,
        played: before.played,
        finished: before.finished,
        // Zero rather than null when the book was not played before:
        // null keeps the stored count, which would leave the play the
        // mark added counted. The catalog refuses a played row with a
        // zero count, so a book that was already played keeps its own.
        playCount: before.played ? before.playCount : 0,
      );
      moved = true;
    } on WaxDeckApiException {
      // Same: the position above may well have landed.
    }
    if (moved) _refresh(container);
  }

  /// Everything that reads this book's position, after one is written.
  void _refresh(ProviderContainer container) {
    container.invalidate(bookResumeProvider(book.pid));
    container.invalidate(playStateControllerProvider(book.pid));
    // The hub's shelf and its finished filter read the batch, which is
    // keyed by whichever rows were on screen; dropping the family is
    // cheaper than working out which key held this pid.
    container.invalidate(playProgressProvider);
  }

  Future<void> _runTool(
    BuildContext context,
    WidgetRef ref,
    Future<ToolTask> Function() start,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    // The container, captured first: this runs unawaited from a menu, so
    // `ref` may be dead by the time the request lands.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await start();
      container.invalidate(toolTasksProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Queued. Follow it in Tasks.'),
            action: SnackBarAction(
              label: 'Tasks',
              onPressed: () => router.push<void>(WaxRoute.tasks),
            ),
          ),
        );
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// This book's play state, from the batch read the hub already holds.
PlayProgress _progressOf(WidgetRef ref, String pid) {
  final key = playPidsKey(<String>[pid]);
  return PlayProgressView(
    ref.watch(playProgressProvider(key)).value ?? const {},
  )[pid];
}

/// Where the caller left off, with the chapter that position falls in.
final bookResumeProvider = FutureProvider.autoDispose
    .family<BookResume, String>(
      (ref, pid) => ref.watch(repositoryProvider).getBookResume(pid),
    );

/// Per-book playback settings editor; Save PUTs the complete object.
class BookSettingsSheet extends ConsumerStatefulWidget {
  const BookSettingsSheet({
    required this.pid,
    required this.initial,
    super.key,
  });

  final String pid;
  final BookSettings initial;

  @override
  ConsumerState<BookSettingsSheet> createState() => _BookSettingsSheetState();
}

class _BookSettingsSheetState extends ConsumerState<BookSettingsSheet> {
  late double _speed;
  late bool _voiceBoost;
  late bool _trimSilence;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _speed = widget.initial.speed ?? 1.0;
    _voiceBoost = widget.initial.voiceBoost ?? false;
    _trimSilence = widget.initial.trimSilence ?? false;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .putBookSettings(
            widget.pid,
            BookSettings(
              speed: _speed,
              voiceBoost: _voiceBoost,
              trimSilence: _trimSilence,
            ),
          );
      ref.invalidate(bookDetailProvider(widget.pid));
      // Only while this sheet is still up: a save outlives a sheet
      // somebody swiped away, and popping then takes the book screen
      // underneath with it.
      if (mounted) navigator.pop();
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
    final colors = WaxColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: WaxSpace.s16,
        right: WaxSpace.s16,
        top: WaxSpace.s16,
        bottom: WaxSpace.s16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Playback settings',
            style: WaxType.headline.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: WaxSpace.s8),
          Text(
            'Speed ${_speed.toStringAsFixed(2)}x',
            style: WaxType.monoData.copyWith(color: colors.textSecondary),
          ),
          Semantics(
            identifier: SemanticsIds.bookSettingsSpeed,
            label: 'Playback speed',
            child: Slider(
              key: const Key(SemanticsIds.bookSettingsSpeed),
              value: _speed,
              min: 0.5,
              max: 3.5,
              divisions: 60,
              label: _speed.toStringAsFixed(2),
              onChanged: (v) => setState(() => _speed = v),
            ),
          ),
          WaxSettingRow(
            key: const Key('book-settings-boost'),
            title: 'Voice boost',
            help: 'Lifts speech over a noisy room',
            control: WaxSwitch(
              value: _voiceBoost,
              label: 'Voice boost',
              onChanged: (v) => setState(() => _voiceBoost = v),
            ),
          ),
          WaxSettingRow(
            key: const Key('book-settings-trim'),
            title: 'Trim silence',
            help: 'Shortens the pauses between sentences',
            control: WaxSwitch(
              value: _trimSilence,
              label: 'Trim silence',
              onChanged: (v) => setState(() => _trimSilence = v),
            ),
          ),
          const SizedBox(height: WaxSpace.s16),
          Align(
            alignment: Alignment.centerRight,
            child: WaxButton(
              label: 'Save',
              semanticsId: SemanticsIds.bookSettingsSave,
              onPressed: _busy ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
