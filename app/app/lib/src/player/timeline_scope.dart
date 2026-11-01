import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show ClientSettingKeys;

import '../settings/client_prefs.dart';
import 'chapters.dart';
import 'playback_session.dart';

/// What a book's seek bars span: the chapter playing, or the whole book.
enum BookTimelineScope { chapter, book }

/// The one scope the deck, the full player and the mini window draw a
/// book with chapters in, so a bar collapsed or expanded keeps its scale.
///
/// Per device, not synced: it describes this screen. The lock screen and
/// the OS scrubbers keep the whole book, as they offer no way to switch.
class BookTimelineScopeSetting extends EnumSetting<BookTimelineScope> {
  @override
  String get settingKey => ClientSettingKeys.bookTimelineScope;

  @override
  BookTimelineScope get defaultValue => BookTimelineScope.chapter;

  @override
  List<BookTimelineScope> get options => BookTimelineScope.values;

  void toggle() => set(
    state == BookTimelineScope.chapter
        ? BookTimelineScope.book
        : BookTimelineScope.chapter,
  );
}

final bookTimelineScopeProvider =
    NotifierProvider<BookTimelineScopeSetting, BookTimelineScope>(
      BookTimelineScopeSetting.new,
    );

/// The stretch of a book's timeline a bar draws, and the chapter it is,
/// or null for the whole book.
typedef BookWindow = ({Duration start, Duration span, ChapterMark? chapter});

const BookWindow _nothing = (
  start: Duration.zero,
  span: Duration.zero,
  chapter: null,
);

/// The window a book's bar draws at [at]: the chapter it stands in, or
/// the whole book in [BookTimelineScope.book] or when it has no chapters.
/// A position before the first chapter stands in that chapter, as
/// [chapterAt] answers.
BookWindow bookWindow({
  required List<ChapterMark> chapters,
  required Duration at,
  required Duration total,
  required BookTimelineScope scope,
}) {
  final chapter = scope == BookTimelineScope.chapter
      ? chapterAt(chapters, at)
      : null;
  if (chapter == null) {
    return (start: Duration.zero, span: total, chapter: null);
  }
  final endMs = chapterEndMs(chapters, chapter, total.inMilliseconds);
  return (
    start: Duration(milliseconds: chapter.startMs),
    span: Duration(milliseconds: endMs - chapter.startMs),
    chapter: chapter,
  );
}

/// The book position [at] on [window]'s bar, held inside it: an intro
/// stands before its opening chapter, and `formatTimecode` does not draw
/// a negative as one (minus five seconds reads "0:55").
Duration withinWindow(Duration at, BookWindow window) {
  final within = at - window.start;
  if (within < Duration.zero) return Duration.zero;
  return within > window.span ? window.span : within;
}

/// A session's position as its bar draws it, for the surfaces that follow
/// one outside the player: the deck and the mini window.
///
/// [value] is the position on the bar and ticks; [window] changes only at
/// a chapter crossing, a scope switch or a new session, so a surface
/// rebuilds on it and leaves the ticking to its leaf. Anything but a book
/// passes its position through and keeps no window.
class BookWindowFeed extends ValueNotifier<Duration> {
  BookWindowFeed() : super(Duration.zero);

  ValueListenable<BookWindow> get window => _window;
  final ValueNotifier<BookWindow> _window = ValueNotifier(_nothing);

  PlaybackSession? _session;
  BookTimelineScope? _scope;
  StreamSubscription<Duration>? _feed;
  Duration _at = Duration.zero;

  bool get _book => _session?.item.mediaType == MediaType.audiobook;

  /// The bar's length: the window's for a book, otherwise the session's
  /// own, read live because a stream learns its length after it starts.
  Duration get span =>
      _book ? _window.value.span : _session?.mediaDuration ?? Duration.zero;

  /// Where a seek to [to] on the bar lands on the session's timeline.
  Duration seekTarget(Duration to) => _window.value.start + to;

  /// Follows [session] in [scope]. Naming what it already follows does
  /// nothing.
  void follow(PlaybackSession? session, BookTimelineScope scope) {
    final moved = !identical(session, _session);
    if (!moved && scope == _scope) return;
    _scope = scope;
    if (moved) {
      _session = session;
      unawaited(_feed?.cancel());
      _at = session?.displayPosition ?? Duration.zero;
      _feed = session?.displayPositionStream.listen((at) {
        _at = at;
        _apply();
      });
    }
    _apply();
  }

  void _apply() {
    final session = _session;
    if (session == null || !_book) {
      _window.value = _nothing;
      value = _at;
      return;
    }
    final next = bookWindow(
      chapters: session.book?.chapters ?? const <ChapterMark>[],
      at: _at,
      total: session.mediaDuration,
      scope: _scope!,
    );
    _window.value = next;
    value = withinWindow(_at, next);
  }

  @override
  void dispose() {
    unawaited(_feed?.cancel());
    _window.dispose();
    super.dispose();
  }
}
