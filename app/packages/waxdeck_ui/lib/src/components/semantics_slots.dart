import 'package:flutter/foundation.dart';

/// The e2e handles a composite surface exposes, supplied by the caller.
///
/// The design system emits no identifier strings of its own. Identifiers
/// are a contract between the app and the browser-driven suite, generated
/// into both from `app/semantics-ids/`, and a package that cannot see
/// that registry has no business inventing them: two definitions of one
/// contract string is exactly the drift the registry exists to prevent.
///
/// So a surface with many controls declares the *shape* of its handles
/// here, and the shell fills them in from `SemanticsIds`. Left null, a
/// control still carries its role and its accessible name; it just has no
/// stable handle for a spec to grab.
@immutable
class DeckBarIds {
  const DeckBarIds({
    this.bar,
    this.expand,
    this.play,
    this.next,
    this.previous,
    this.skipBack,
    this.skipForward,
    this.shuffle,
    this.repeat,
    this.star,
    this.saveSong,
    this.seek,
    this.queue,
    this.lyrics,
    this.cast,
    this.volume,
    this.mute,
    this.more,
  });

  final String? bar;

  /// The visible way into the full player. Its own handle, because the
  /// two gesture surfaces that also expand the bar are excluded from the
  /// semantics tree, so this button is the only expand a spec or a
  /// screen reader can reach.
  final String? expand;
  final String? play;
  final String? next;
  final String? previous;
  final String? skipBack;
  final String? skipForward;
  final String? shuffle;
  final String? repeat;
  final String? star;

  /// Keeps the song a live stream just named. Distinct from [star],
  /// which is per-item state a stream has none of: this one is about the
  /// announcement, not the station.
  final String? saveSong;

  final String? seek;
  final String? queue;
  final String? lyrics;
  final String? cast;
  final String? volume;
  final String? mute;
  final String? more;
}

/// The full player's handles. See [DeckBarIds] for why these arrive from
/// the caller.
@immutable
class PlayerIds {
  const PlayerIds({
    this.surface,
    this.collapse,
    this.play,
    this.next,
    this.previous,
    this.skipBack,
    this.skipForward,
    this.shuffle,
    this.repeat,
    this.seek,
  });

  final String? surface;
  final String? collapse;
  final String? play;
  final String? next;
  final String? previous;
  final String? skipBack;
  final String? skipForward;
  final String? shuffle;
  final String? repeat;
  final String? seek;
}
