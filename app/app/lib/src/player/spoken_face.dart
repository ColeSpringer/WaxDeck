import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../podcasts/podcasts_controller.dart';
import '../podcasts/show_notes.dart';
import '../providers.dart';
import '../settings/client_prefs.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'bookmarks.dart';
import 'playback_session.dart';
import 'speed_sheet.dart';
import 'waveform.dart';

/// Rebuilds only when the live position crosses into a new [T].
///
/// The player's position ticks several times a second, and the lists
/// under it change on a chapter or a cue boundary. A plain
/// `ValueListenableBuilder` would rebuild them per tick for a highlight
/// that moves once every few minutes.
class WhenChanged<T> extends StatefulWidget {
  const WhenChanged({
    required this.listenable,
    required this.select,
    required this.builder,
    super.key,
  });

  final ValueListenable<Duration> listenable;
  final T Function(Duration at) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<WhenChanged<T>> createState() => _WhenChangedState<T>();
}

class _WhenChangedState<T> extends State<WhenChanged<T>> {
  late T _value = widget.select(widget.listenable.value);

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant WhenChanged<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_tick);
      widget.listenable.addListener(_tick);
    }
    // The selector closes over what the caller drew from (a chapter
    // list, a set of cues), so a rebuild with a new one re-selects
    // rather than holding a value the old list produced.
    _value = widget.select(widget.listenable.value);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    final next = widget.select(widget.listenable.value);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Which chapter [position] falls in, or null when the book has none.
///
/// The latest start at or before the position, taken by comparison
/// rather than by walking to the end of the list. The contract says
/// chapters arrive ordered by `startMs` and they always have; these
/// marks come out of file metadata through a third-party reader, and a
/// helper that reads the same either way costs nothing to write.
///
/// A position before the first chapter answers the first one: the book
/// is in its opening chapter as far as anything that names one is
/// concerned, which is what the title block and the chapter list want.
/// The seek cluster is what holds that position inside the span it
/// draws.
ChapterMark? chapterAt(List<ChapterMark> chapters, Duration position) {
  final positionMs = position.inMilliseconds;
  ChapterMark? current;
  for (final chapter in chapters) {
    if (chapter.startMs > positionMs) continue;
    if (current == null || chapter.startMs > current.startMs) current = chapter;
  }
  return current ?? (chapters.isEmpty ? null : chapters.first);
}

/// A chapter's own name, or its number when the source named none.
String chapterTitle(ChapterMark chapter) =>
    chapter.title ?? 'Chapter ${chapter.index + 1}';

/// Where a chapter ends on the timeline it lives on.
///
/// The mark's own end when it carries one, the *nearest* later start
/// when it does not, and the item's end for the last one. Nearest by
/// comparison rather than first-encountered, for the reason [chapterAt]
/// compares: an end taken from the first later mark in an unordered
/// list is a chapter bar drawn twice its width and a sleep timer that
/// stops a chapter late.
int chapterEndMs(List<ChapterMark> chapters, ChapterMark chapter, int totalMs) {
  if (chapter.endMs != null) return chapter.endMs!;
  int? nearest;
  for (final other in chapters) {
    if (other.startMs <= chapter.startMs) continue;
    if (nearest == null || other.startMs < nearest) nearest = other.startMs;
  }
  return nearest ?? totalMs;
}

/// The show an episode is from, above its title and tappable.
class ShowOverline extends ConsumerWidget {
  const ShowOverline({required this.episode, super.key});

  final EpisodeSummary episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WaxColors.of(context);
    // The summary's own artist line is the show's name and arrives with
    // the item; the detail is watched only so a show renamed elsewhere
    // corrects itself without a reload.
    final name =
        ref.watch(podcastDetailProvider(episode.showPid)).value?.show.title ??
        episode.artist;
    if (name == null) return const SizedBox.shrink();
    return WaxTappable(
      semanticsId: SemanticsIds.playerShow,
      label: context.l10n.playerGoToName(name),
      borderRadius: WaxRadius.chip,
      onPressed: () => context.go(WaxRoute.show(episode.showPid)),
      child: InkWell(
        borderRadius: WaxRadius.chip,
        onTap: () => context.go(WaxRoute.show(episode.showPid)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s8,
            vertical: WaxSpace.s4,
          ),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WaxType.overline.copyWith(color: colors.accent),
          ),
        ),
      ),
    );
  }
}

/// The chapter a book stands in, under its title.
class BookSubtitle extends StatelessWidget {
  const BookSubtitle({
    required this.chapters,
    required this.position,
    super.key,
  });

  final List<ChapterMark> chapters;
  final ValueListenable<Duration> position;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return WhenChanged<ChapterMark?>(
      listenable: position,
      select: (at) => chapterAt(chapters, at),
      builder: (context, chapter) {
        if (chapter == null) return const SizedBox.shrink();
        return Text(
          chapterTitle(chapter),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WaxType.body.copyWith(color: colors.textSecondary),
        );
      },
    );
  }
}

/// A book's seek cluster: the chapter by default, the whole book on
/// request.
///
/// The chapter is the unit a listener thinks in, and a nine-hour bar
/// moves a pixel a minute; the toggle is there because "how far through
/// the book am I" is a real question the chapter view cannot answer, and
/// the caption answers it either way.
///
/// Both views draw the same envelope. A book's waveform is the book's,
/// stitched server-side across its parts, because a part is a file
/// boundary and neither view is one: the chapter view is a slice of the
/// whole rather than a request of its own, so toggling costs nothing
/// and never rescales the shape under the listener.
class BookSeek extends ConsumerStatefulWidget {
  const BookSeek({
    required this.session,
    required this.position,
    required this.chapters,
    super.key,
  });

  final PlaybackSession session;
  final ValueListenable<Duration> position;
  final List<ChapterMark> chapters;

  @override
  ConsumerState<BookSeek> createState() => _BookSeekState();
}

class _BookSeekState extends ConsumerState<BookSeek> {
  static const _chapterView = 'chapter';
  static const _bookView = 'book';

  var _view = _chapterView;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.session.mediaDuration;
    // The whole book's envelope, whichever view is drawn. A book that
    // has not been analyzed, or one part of which cannot be, answers
    // null and the bar is the plain one it has always been.
    final book = ref.watch(bookWaveformProvider(widget.session.item.pid)).value;
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.position,
      builder: (context, at, _) {
        final chapter = _view == _chapterView
            ? chapterAt(widget.chapters, at)
            : null;
        final start = chapter == null
            ? Duration.zero
            : Duration(milliseconds: chapter.startMs);
        final span = chapter == null
            ? total
            : Duration(
                milliseconds:
                    chapterEndMs(
                      widget.chapters,
                      chapter,
                      total.inMilliseconds,
                    ) -
                    chapter.startMs,
              );
        return Column(
          children: <Widget>[
            if (widget.chapters.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: WaxSpace.s8),
                child: WaxSegmented(
                  label: l10n.playerSeekSpans,
                  selected: _view,
                  segments: <WaxSegment>[
                    WaxSegment(
                      name: _chapterView,
                      label: l10n.playerSpanChapter,
                      semanticsId: SemanticsIds.playerTimeline(_chapterView),
                    ),
                    WaxSegment(
                      name: _bookView,
                      label: l10n.playerSpanBook,
                      semanticsId: SemanticsIds.playerTimeline(_bookView),
                    ),
                  ],
                  onSelect: (view) => setState(() => _view = view),
                ),
              ),
            SeekCluster(
              now: NowPlayingData(
                title: widget.session.item.title,
                // Chapter-relative, so both timecodes read as the
                // chapter's own rather than as book positions the bar
                // is not drawing. Held inside the chapter, because a
                // book whose first chapter starts after zero - an
                // intro, a credits region - stands before its own
                // opening chapter for as long as that lasts, and the
                // bare subtraction is negative there. `formatTimecode`
                // does not draw a negative as one: minus five seconds
                // reads "0:55".
                position: _within(at - start, span),
                duration: span,
                playing: true,
              ),
              // The chapter view is a window on the same envelope, kept
              // on the book's own scale: a quiet chapter has to stay
              // quiet, or the toggle would change how the audio looks.
              peaks: chapter == null
                  ? book
                  : _chapterPeaks(book, start, span, total),
              // Chapter starts, on the whole-book bar only: inside one
              // chapter the only division is the edge of the bar.
              marks: chapter == null ? _chapterStarts() : null,
              // Always the whole book, whichever bar is drawn: it is the
              // answer the chapter view cannot give, and the reason the
              // toggle is not needed most of the time.
              remainingLabel: _bookProgress(context.waxL10n, total, at),
              onSeek: (to) => unawaited(widget.session.seek(start + to)),
              semanticsId: SemanticsIds.playerSeek,
            ),
          ],
        );
      },
    );
  }

  /// Where [at] falls in [total], as a fraction.
  static double _fractionOf(Duration at, Duration total) {
    final ms = total.inMilliseconds;
    if (ms <= 0) return 0;
    return (at.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  /// The window of the book's envelope this chapter covers, held for
  /// the reason the starts below are: this is rebuilt on every position
  /// tick, and the slice depends on the chapter rather than on the
  /// position. A fresh list each tick would also defeat the seek bar's
  /// own identity guards, which exist so a thousand buckets - four
  /// thousand on a long book - are not reduced again every frame.
  List<double>? _slice;
  ({List<double>? book, Duration start, Duration span, Duration total})?
  _sliceOf;

  List<double>? _chapterPeaks(
    List<double>? book,
    Duration start,
    Duration span,
    Duration total,
  ) {
    final key = (book: book, start: start, span: span, total: total);
    if (_sliceOf != key) {
      _sliceOf = key;
      _slice = slicePeaks(
        book,
        _fractionOf(start, total),
        _fractionOf(start + span, total),
      );
    }
    return _slice;
  }

  /// The chapter starts, held so the seek bar can compare them by
  /// identity: the position moves several times a second and the
  /// chapters do not.
  List<Duration>? _starts;
  List<ChapterMark>? _startsFrom;

  List<Duration>? _chapterStarts() {
    final chapters = widget.chapters;
    if (chapters.isEmpty) return null;
    if (!identical(_startsFrom, chapters)) {
      _startsFrom = chapters;
      _starts = <Duration>[
        for (final chapter in chapters) Duration(milliseconds: chapter.startMs),
      ];
    }
    return _starts;
  }

  /// A position held inside the span the bar is drawing.
  static Duration _within(Duration at, Duration span) {
    if (at < Duration.zero) return Duration.zero;
    return at > span ? span : at;
  }

  /// "42 percent, 6 hr 12 min left" (5.3). Percent and a span, because
  /// each answers a question the other does not: how far in, and how
  /// much of the evening this is.
  String? _bookProgress(WaxLocalizations l10n, Duration total, Duration at) {
    final totalMs = total.inMilliseconds;
    if (totalMs <= 0) return null;
    final percent = ((at.inMilliseconds / totalMs) * 100).clamp(0, 100).round();
    final left = total - at;
    if (left <= Duration.zero) return '$percent percent';
    return '$percent percent, ${l10n.formatSpan(left)} left';
  }
}

/// The spoken-word verbs: rate, the two effects, bookmarks on a book.
///
/// A list rather than a row, because the player composes one wrapping
/// row out of these and the sleep timer: four labelled chips do not fit
/// a phone in one line, and the row they belong to has to be able to
/// take a second one.
///
/// The sleep timer is not here - it is on every face and the player owns
/// it, because falling asleep to a record is what the control is for.
List<Widget> spokenActionChips(PlaybackSession session) => <Widget>[
  SpeedChip(session: session),
  TrimChip(session: session),
  VoiceBoostChip(session: session),
  if (session.item.mediaType == MediaType.audiobook)
    BookmarkButton(session: session),
];

/// The rate, as the door to the speed sheet.
class SpeedChip extends StatelessWidget {
  const SpeedChip({required this.session, super.key});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: session.engine.speedStream,
      initialData: session.engine.speed,
      builder: (context, snapshot) {
        final l10n = context.l10n;
        final speed = snapshot.data ?? 1.0;
        return WaxPill(
          semanticsId: SemanticsIds.playerSpeed,
          label: l10n.playerSpeedAt(l10n.formatSpeed(speed)),
          text: l10n.formatSpeed(speed),
          mono: true,
          onPressed: () => unawaited(showSpeedSheet(context, session)),
        );
      },
    );
  }
}

/// Says what an effect does, the first time somebody presses it.
///
/// Once per device, and only on the way on: an effect that is being
/// turned off has already explained itself, and a sentence that
/// appears every time is one nobody reads. The flag is written before
/// the message so a double press cannot say it twice.
void explainOnce(
  BuildContext context,
  WidgetRef ref,
  NotifierProvider<BoolSetting, bool> seen,
  String message,
) {
  if (ref.read(seen)) return;
  ref.read(seen.notifier).set(true);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Silence-trimming toggle with its own saved badge.
///
/// Trim jumps only, which is narrower than what the stats now report and
/// is deliberate: this is the trim control, and the number beside it is
/// the reason to leave the trim control on. Crediting it with what the
/// speed chip saved would be the wrong number under the wrong toggle.
class TrimChip extends ConsumerWidget {
  const TrimChip({required this.session, super.key});

  final PlaybackSession session;

  static String savedLabel(int savedMs) {
    final d = Duration(milliseconds: savedMs);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m > 0) return 'saved ${m}m ${s}s';
    return 'saved ${s}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<bool>(
      valueListenable: session.trimEnabled,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<int>(
          valueListenable: session.hoursSavedMs,
          builder: (context, savedMs, _) {
            final l10n = context.l10n;
            final label = savedMs > 0
                ? l10n.playerTrimSilenceSaved(savedLabel(savedMs))
                : l10n.playerTrimSilence;
            // A chip with its readout drawn rather than an icon with the
            // readout only spoken: what the session has saved is the
            // reason to leave the toggle on, and a glyph says none of it.
            return WaxPill(
              semanticsId: SemanticsIds.playerTrim,
              label: label,
              text: label,
              selected: enabled,
              onPressed: () {
                if (!enabled) {
                  explainOnce(
                    context,
                    ref,
                    trimSilenceExplainedProvider,
                    l10n.playerTrimExplained,
                  );
                }
                session.setTrimEnabled(!enabled);
              },
            );
          },
        );
      },
    );
  }
}

/// Spoken-word loudness normalization, per show or per book.
///
/// The server applies it when it mints the stream, so pressing this
/// reopens what is playing. That is why it is a chip that can be busy: a
/// round trip and a reload stand between the press and the sound
/// changing, and a control that looked instant would read as broken on a
/// slow link.
class VoiceBoostChip extends ConsumerStatefulWidget {
  const VoiceBoostChip({required this.session, super.key});

  final PlaybackSession session;

  @override
  ConsumerState<VoiceBoostChip> createState() => _VoiceBoostChipState();
}

class _VoiceBoostChipState extends ConsumerState<VoiceBoostChip> {
  var _busy = false;

  Future<void> _toggle(bool to) async {
    if (_busy) return;
    final l10n = context.l10n;
    if (to) {
      explainOnce(
        context,
        ref,
        voiceBoostExplainedProvider,
        l10n.playerVoiceBoostExplained,
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // The chip puts itself back when there was nothing to store the
      // choice on, so the refusal is visible; saying why is this
      // surface's half of it.
      if (!await widget.session.setVoiceBoost(to)) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.playerVoiceBoostFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.session.voiceBoost,
      builder: (context, enabled, _) => WaxPill(
        semanticsId: SemanticsIds.playerVoiceBoost,
        label: context.l10n.playerVoiceBoost,
        text: context.l10n.playerVoiceBoost,
        selected: enabled,
        onPressed: _busy ? null : () => unawaited(_toggle(!enabled)),
      ),
    );
  }
}

/// The bottom region of a spoken-word player: what the episode or book
/// says about itself, under the transport.
///
/// Bounded rather than free: the region shares a window with the hero
/// and the clusters, so it takes a share of the height and scrolls
/// inside it. On a window with nothing to spare it draws nothing at all,
/// the same rule the hero follows.
class SpokenBottomRegion extends ConsumerStatefulWidget {
  const SpokenBottomRegion({
    required this.session,
    required this.position,
    super.key,
  });

  final PlaybackSession session;
  final ValueListenable<Duration> position;

  @override
  ConsumerState<SpokenBottomRegion> createState() => _SpokenBottomRegionState();
}

class _SpokenBottomRegionState extends ConsumerState<SpokenBottomRegion> {
  String? _region;

  ItemSummary get _item => widget.session.item;
  bool get _isBook => _item.mediaType == MediaType.audiobook;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final height = MediaQuery.sizeOf(context).height;
    // A fifth of the window, capped: three or four rows, and small
    // enough that the clusters above keep their room. The region is
    // what the item says about itself and the transport is what the
    // screen is for, so this is the half that gives - a taller panel
    // scrolls the play button off a phone, which is how it was first
    // built and what the sleep-timer tests caught.
    final extent = math.min(200.0, height * 0.22);
    if (extent < 100) return const SizedBox.shrink();

    final regions = _regions();
    if (regions.isEmpty) return const SizedBox.shrink();
    final selected = regions.any((r) => r.name == _region)
        ? _region!
        : regions.first.name;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.veil,
        borderRadius: WaxRadius.sheetTop,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (regions.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s8),
              child: FilterChipRow(
                padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                chips: <WaxFilterChip>[
                  for (final region in regions)
                    WaxFilterChip(
                      name: region.name,
                      label: region.label,
                      semanticsId: SemanticsIds.playerRegion(region.name),
                    ),
                ],
                selected: selected,
                onSelect: (name) => setState(() => _region = name),
              ),
            ),
          SizedBox(
            height: extent,
            child: regions.firstWhere((r) => r.name == selected).build(context),
          ),
        ],
      ),
    );
  }

  List<_Region> _regions() {
    if (_isBook) {
      final book = widget.session.book;
      if (book == null || book.chapters.isEmpty) return const <_Region>[];
      return <_Region>[
        _Region(
          'chapters',
          'Chapters',
          (context) => _ChapterList(
            session: widget.session,
            position: widget.position,
            chapters: book.chapters,
            parts: book.parts,
            totalMs: book.durationMs,
          ),
        ),
      ];
    }
    final episode = ref.watch(episodeDetailProvider(_item.pid)).value;
    if (episode == null) return const <_Region>[];
    return <_Region>[
      if (episode.chapters.isNotEmpty)
        _Region(
          'chapters',
          'Chapters',
          (context) => _ChapterList(
            session: widget.session,
            position: widget.position,
            chapters: episode.chapters,
            parts: const <BookPart>[],
            totalMs: episode.durationMs,
          ),
        ),
      if (episode.descriptionHtml?.isNotEmpty ?? false)
        _Region(
          'notes',
          'Notes',
          (context) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              WaxSpace.s16,
              WaxSpace.s8,
              WaxSpace.s16,
              WaxSpace.s16,
            ),
            child: ShowNotesView(
              html: episode.descriptionHtml!,
              onOpenLink: ref.read(urlOpenerProvider).open,
            ),
          ),
        ),
      if (episode.hasTranscript)
        _Region(
          'transcript',
          'Transcript',
          (context) => _TranscriptRegion(
            session: widget.session,
            position: widget.position,
          ),
        ),
    ];
  }
}

class _Region {
  const _Region(this.name, this.label, this.build);

  final String name;
  final String label;
  final Widget Function(BuildContext context) build;
}

/// Chapters on whatever timeline they belong to, with the one playing
/// marked and part boundaries drawn where a book has several files.
class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.session,
    required this.position,
    required this.chapters,
    required this.parts,
    required this.totalMs,
  });

  final PlaybackSession session;
  final ValueListenable<Duration> position;
  final List<ChapterMark> chapters;
  final List<BookPart> parts;
  final int totalMs;

  /// Which parts each chapter opens, by chapter index.
  ///
  /// Chapters and file boundaries rarely line up to the millisecond -
  /// a book's chapters are as often derived as authored - so the
  /// chapter that opens a part is the first one at or after its start
  /// rather than one landing exactly on it. Part one opens the book and
  /// needs no line, and a single-file book has no boundaries at all.
  ///
  /// Built once per draw rather than asked per row: the row builder runs
  /// on every scroll, and a search over every part crossed with a search
  /// over every chapter is thousands of comparisons per row on a book
  /// with three hundred of them. A list per chapter rather than one
  /// part, because a part that contains no chapter start at all shares
  /// its opener with the part before it, and the header it would
  /// otherwise never get is the one that says a file boundary passed.
  Map<int, List<int>> _partHeaders() {
    final headers = <int, List<int>>{};
    if (parts.length < 2 || chapters.isEmpty) return headers;
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      var opener = -1;
      for (var c = 0; c < chapters.length; c++) {
        final start = chapters[c].startMs;
        if (start < part.startMs) continue;
        if (opener < 0 || start < chapters[opener].startMs) opener = c;
      }
      if (opener < 0) continue;
      (headers[opener] ??= <int>[]).add(part.index);
    }
    return headers;
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final headers = _partHeaders();
    return Semantics(
      identifier: SemanticsIds.playerChapters,
      container: true,
      explicitChildNodes: true,
      label: context.l10n.playerChapters,
      // On chapter changes, not on position ticks: the highlight moves
      // once every few minutes and the position moves several times a
      // second, and rebuilding a list for the second is the most
      // repeated frame work a book player could do.
      child: WhenChanged<ChapterMark?>(
        listenable: position,
        select: (at) => chapterAt(chapters, at),
        builder: (context, current) {
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: WaxSpace.s8),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              final playing = current?.index == chapter.index;
              final l10n = context.l10n;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final part in headers[index] ?? const <int>[])
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        WaxSpace.s16,
                        WaxSpace.s8,
                        WaxSpace.s16,
                        WaxSpace.s4,
                      ),
                      child: Text(
                        context.l10n.playerPart(part + 1),
                        style: WaxType.overline.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  WaxTappable(
                    semanticsId: SemanticsIds.playerChapter(chapter.index),
                    label: playing
                        ? l10n.playerChapterPlaying(chapterTitle(chapter))
                        : chapterTitle(chapter),
                    selected: playing,
                    onPressed: () => unawaited(
                      session.seek(Duration(milliseconds: chapter.startMs)),
                    ),
                    child: InkWell(
                      onTap: () => unawaited(
                        session.seek(Duration(milliseconds: chapter.startMs)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WaxSpace.s16,
                          vertical: WaxSpace.s8,
                        ),
                        child: Row(
                          children: <Widget>[
                            Text(
                              formatTimecode(
                                Duration(milliseconds: chapter.startMs),
                              ),
                              style: WaxType.monoTime.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: WaxSpace.s12),
                            Expanded(
                              child: Text(
                                chapterTitle(chapter),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WaxType.body.copyWith(
                                  color: playing
                                      ? colors.accent
                                      : colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The transcript, following playback until somebody scrolls.
class _TranscriptRegion extends ConsumerStatefulWidget {
  const _TranscriptRegion({required this.session, required this.position});

  final PlaybackSession session;
  final ValueListenable<Duration> position;

  @override
  ConsumerState<_TranscriptRegion> createState() => _TranscriptRegionState();
}

class _TranscriptRegionState extends ConsumerState<_TranscriptRegion> {
  late final Future<List<LyricLine>> _loading = ref
      .read(repositoryProvider)
      .getEpisodeTranscript(widget.session.item.pid)
      .then(_asLines);

  /// The cues as the lyrics view draws them.
  ///
  /// A transcript and a lyric sheet are the same surface: timed lines
  /// that follow a playhead, tap to seek, following handed over on a
  /// scroll and offered back by a button. This region was a hand-written
  /// copy of that, and the two had already drifted - the lyrics view
  /// scrolls to the line when the button is pressed and this one only
  /// flipped the flag. One component draws both now, and the speaker is
  /// folded into the line, which is how it read before.
  ///
  /// Mapped once into a future rather than per build, because the view
  /// resets a reader's scroll when it is handed a different list.
  static List<LyricLine> _asLines(Transcript transcript) => <LyricLine>[
    for (final cue in transcript.cues)
      LyricLine(
        at: Duration(milliseconds: cue.startMs),
        text: cue.speaker == null ? cue.text : '${cue.speaker}: ${cue.text}',
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return FutureBuilder<List<LyricLine>>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Padding(
            padding: const EdgeInsets.all(WaxSpace.s16),
            child: Text(
              error is WaxDeckApiException
                  ? explainError(context.l10n, error)
                  : context.l10n.playerTranscriptError,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
          );
        }
        final lines = snapshot.data;
        if (lines == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return LyricsView(
          position: widget.position,
          lines: lines,
          onSeek: (at) => unawaited(widget.session.seek(at)),
          lineSemanticsId: SemanticsIds.transcriptCue,
          followSemanticsId: SemanticsIds.transcriptFollow,
        );
      },
    );
  }
}
