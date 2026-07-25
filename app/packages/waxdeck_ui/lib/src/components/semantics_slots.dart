import 'package:flutter/foundation.dart';

/// The e2e handles a composite surface exposes, supplied by the caller.
///
/// The design system emits no identifier strings of its own. Identifiers
/// are a contract between the app and the browser-driven suite, generated
/// into both from `app/semantics-ids.json`, and a package that cannot see
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
    this.play,
    this.next,
    this.previous,
    this.skipBack,
    this.skipForward,
    this.shuffle,
    this.repeat,
    this.star,
    this.seek,
    this.queue,
    this.lyrics,
    this.cast,
    this.more,
  });

  final String? bar;
  final String? play;
  final String? next;
  final String? previous;
  final String? skipBack;
  final String? skipForward;
  final String? shuffle;
  final String? repeat;
  final String? star;
  final String? seek;
  final String? queue;
  final String? lyrics;
  final String? cast;
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
