import 'package:waxdeck_api/waxdeck_api.dart';

import 'playback_session.dart';

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

/// Where a chapter ends on the timeline it lives on.
///
/// The mark's own end when it carries one, the *nearest* later start
/// when it does not, and the item's end for the last one. Nearest by
/// comparison rather than first-encountered, for the reason [chapterAt]
/// compares: an end taken from the first later mark in an unordered
/// list is a chapter bar drawn twice its width and a sleep timer that
/// stops a chapter late.
///
/// [relayed] is an episode the server streams from its feed, whose last
/// chapter it ends at the length the feed declares, which can be 0 or
/// off the audio: that chapter ends at [totalMs] instead whenever that is
/// past its start, and where the stream ends ([PlaybackSession.mediaEndStopMs])
/// when no length is known.
int chapterEndMs(
  List<ChapterMark> chapters,
  ChapterMark chapter,
  int totalMs, {
  bool relayed = false,
}) {
  int? nearest;
  for (final other in chapters) {
    if (other.startMs <= chapter.startMs) continue;
    if (nearest == null || other.startMs < nearest) nearest = other.startMs;
  }
  if (relayed && nearest == null) {
    return totalMs > chapter.startMs ? totalMs : PlaybackSession.mediaEndStopMs;
  }
  return chapter.endMs ?? nearest ?? totalMs;
}

/// Where end-of-chapter sleep stops in the chapter playing at [position],
/// the marks laid out against [totalMs] as [chapterEndMs] lays them
/// ([relayed] likewise): that chapter's end, or null when no chapter is
/// playing, its end is not known (the last chapter of audio whose length
/// nothing reports yet), or the end is not ahead of [position] (a gap
/// between hand-edited chapters).
int? chapterStopMs(
  List<ChapterMark> chapters,
  Duration position,
  int totalMs, {
  bool relayed = false,
}) {
  final current = chapterAt(chapters, position);
  if (current == null) return null;
  final end = chapterEndMs(chapters, current, totalMs, relayed: relayed);
  return end > current.startMs && end > position.inMilliseconds ? end : null;
}
