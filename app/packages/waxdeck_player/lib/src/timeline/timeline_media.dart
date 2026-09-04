/// A whole queue rendered as one continuous stream, and the arithmetic
/// that maps a position on it back to the item playing.
///
/// Pure Dart on purpose: the mapping is the part that has to be exactly
/// right, and it is worth testing without a browser, an engine, or a
/// server anywhere near it.
library;

/// One member's place on a timeline, in samples at the timeline's
/// envelope rate.
class TimelineMember {
  const TimelineMember({
    required this.pid,
    required this.offsetSamples,
    required this.durationSamples,
  });

  /// The queue item this member renders.
  final String pid;

  /// Where the member starts on the combined timeline.
  final int offsetSamples;

  /// The member's own length, which is what a listen reports and what a
  /// progress bar draws against.
  final int durationSamples;
}

/// The seam arithmetic over a timeline's members.
///
/// Two rules run through all of it. Positions are integers of
/// milliseconds derived from samples the same way the server derives
/// them, so a boundary computed here and one computed there name the
/// same instant rather than drifting by a rounding. And a seam is the
/// *next member's offset*, never this member's offset plus its
/// duration: under a crossfade consecutive members overlap, so summing
/// durations walks past the end of the timeline and puts every seam
/// after the first in the wrong place.
mixin TimelineMap {
  /// Sample rate the member offsets are measured at.
  int get envelopeRate;

  /// Members in play order.
  List<TimelineMember> get members;

  /// Milliseconds where member [i] begins.
  int offsetMs(int i) => _ms(members[i].offsetSamples);

  /// Member [i]'s own duration: what it would report if it were loaded
  /// on its own, and what a finished listen is credited with. Named
  /// apart from the timeline's own duration, which is a different
  /// number on the same object.
  int memberDurationMs(int i) => _ms(members[i].durationSamples);

  /// Where playback crosses out of member [i]. The next member's
  /// offset, or - for the last one, which has nothing after it - its
  /// own end.
  int seamMs(int i) => i + 1 < members.length
      ? offsetMs(i + 1)
      : offsetMs(i) + memberDurationMs(i);

  /// The member holding an absolute timeline position: the last one
  /// that has begun by then. Clamped at both ends, so a position before
  /// the first offset or past the last seam still names a member.
  int locate(int absMs) {
    var found = 0;
    for (var i = 0; i < members.length; i++) {
      if (offsetMs(i) <= absMs) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  /// How far into member [i] an absolute position sits, never negative.
  int memberPosition(int i, int absMs) {
    final within = absMs - offsetMs(i);
    return within < 0 ? 0 : within;
  }

  /// The absolute position of [positionMs] into member [i].
  int absolute(int i, int positionMs) => offsetMs(i) + positionMs;

  int _ms(int samples) =>
      envelopeRate <= 0 ? 0 : samples * 1000 ~/ envelopeRate;
}

/// One minted timeline: the stream and everything needed to play a
/// queue through it.
class TimelineMedia with TimelineMap {
  TimelineMedia({
    required this.url,
    required this.mimeType,
    required this.durationMs,
    required this.envelopeRate,
    required this.members,
    required this.expiresAt,
    this.crossfadeSeconds,
    this.format,
  });

  /// The one stream URL that plays every member end to end.
  final String url;

  final String mimeType;

  /// The combined timeline's duration.
  final int durationMs;

  @override
  final int envelopeRate;

  @override
  final List<TimelineMember> members;

  /// When the URL's media token stops being accepted. A stream still
  /// playing across this instant fails its next fetch, which is one of
  /// the ways a timeline is lost.
  final DateTime expiresAt;

  /// The crossfade the timeline was minted with, when nonzero.
  final double? crossfadeSeconds;

  /// The audio format it was rendered in, when the server said.
  final String? format;
}
