import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// How a piece of artwork is shaped.
///
/// Shape is a domain signal that reads at 40 px and survives greyscale,
/// doing work the domain hues alone cannot. Artwork always renders in its
/// native aspect ratio, fitted, never cropped: book covers vary between
/// square (audio sources) and portrait (book sources), and cropping one
/// to match the other loses the title.
enum ArtworkShape {
  /// Music and podcast art: square by nature.
  square,

  /// Book covers: fitted on a quiet matte, so portrait and square covers
  /// can share a grid without either being cut.
  portrait,

  /// Radio station logos.
  circle,
}

/// How a component asks for the artwork it is about to draw.
///
/// The component is the only thing that knows how big the artwork will
/// be on this screen (its extent times the device pixel ratio); the app
/// is the only thing that knows how a URL becomes bytes — which stored
/// size to ask the server for, the header a native request needs, the
/// copy pinned for offline. So artwork crosses the boundary as a
/// function of the size it will be drawn at, in physical pixels, and the
/// app answers with a provider fetched and decoded for that size.
///
/// Answering null is a real state, not a loading one: an item with no
/// cover draws the monogram.
typedef WaxArtwork = ImageProvider? Function(int px);

/// Artwork that is already decided at every size: assets, generated
/// covers, test doubles. Anything drawn from a URL comes through the
/// app's artwork store instead, which sizes the request to the draw.
WaxArtwork fixedArtwork(ImageProvider provider) =>
    (_) => provider;

/// What a card or row needs to draw one item.
///
/// Plain data on purpose: `waxdeck_ui` never imports the API package, so
/// screens map their models into this at the call site. That keeps golden
/// tests free of API fakes and keeps the design system out of the app's
/// invalidation traffic.
@immutable
class MediaTileData {
  const MediaTileData({
    required this.title,
    this.subtitle,
    this.artwork,
    this.domain = WaxDomain.music,
    this.shape = ArtworkShape.square,
    this.progress,
    this.trailingText,
    this.starred = false,
    this.downloaded = false,
    this.unavailableOffline = false,
    this.semanticsId,
  });

  final String title;
  final String? subtitle;

  /// The artwork, asked for at the size the card will draw it. Null
  /// renders the monogram placeholder, which is a real state (fresh
  /// imports, feeds without art), not a loading one.
  final WaxArtwork? artwork;

  final WaxDomain domain;
  final ArtworkShape shape;

  /// Resume progress from 0 to 1, drawn as a ring on the artwork.
  final double? progress;

  /// Right-aligned metadata: duration, remaining time, track count. Set
  /// in mono by the components that show it.
  final String? trailingText;

  final bool starred;
  final bool downloaded;

  /// Dimmed and answered with an explanation rather than dying silently
  /// when tapped offline.
  final bool unavailableOffline;

  /// The stable identifier the e2e suite drives this control by. Every
  /// component that can be an e2e touchpoint takes one and applies
  /// `Semantics(identifier:)` itself.
  final String? semanticsId;
}

/// What happens at the end of the queue, as the transport draws it.
///
/// The design system's own copy of the queue's three modes: a control
/// that cycles through states has to be able to show which one it is
/// in, and `waxdeck_ui` cannot see the app's queue to ask.
enum WaxRepeat { off, all, one }

/// What the deck bar and the players need to draw the current item.
@immutable
class NowPlayingData {
  const NowPlayingData({
    required this.title,
    required this.position,
    required this.duration,
    required this.playing,
    this.subtitle,
    this.provenance,
    this.artwork,
    this.domain = WaxDomain.music,
    this.shape = ArtworkShape.square,
    this.buffered,
    this.live = false,
    this.starred = false,
    this.shuffled = false,
    this.repeat = WaxRepeat.off,
    this.remoteEndpoint,
    this.speed,
  });

  final String title;

  /// Artist, show, or author.
  final String? subtitle;

  /// Where playback came from: "Playing from Nightjar", a chapter name,
  /// a station's now-playing line. The players render it as their context
  /// line; nothing else reads it.
  final String? provenance;

  final WaxArtwork? artwork;
  final WaxDomain domain;
  final ArtworkShape shape;

  final Duration position;
  final Duration duration;
  final Duration? buffered;
  final bool playing;

  /// Radio: no seek bar, no queue, and play/stop rather than play/pause,
  /// because a pause affordance on a live stream is a lie.
  final bool live;

  final bool starred;

  /// The queue's standing modes, so the two controls that cycle them can
  /// show which state they are in. Radio draws neither.
  final bool shuffled;
  final WaxRepeat repeat;

  /// Set when playback is being controlled on another endpoint: the bar
  /// says so rather than pretending the sound is local.
  final String? remoteEndpoint;

  /// Playback rate for spoken word, shown as a compact chip.
  final double? speed;

  double get fraction => fractionAt(position);

  /// How far through the item [at] is, for a surface reading the live
  /// position from somewhere other than this snapshot: the deck bar
  /// ticks in a leaf of its own so the rest of the bar does not rebuild
  /// with it.
  double fractionAt(Duration at) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (at.inMilliseconds / total).clamp(0, 1);
  }
}

/// Formats a duration the way readouts show it: `4:05`, `1:02:41`.
String formatTimecode(Duration d) {
  final total = d.inSeconds;
  final seconds = (total % 60).abs().toString().padLeft(2, '0');
  final minutes = ((total ~/ 60) % 60).abs();
  final hours = total ~/ 3600;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// Spells a duration for screen readers and for prose: "2 minutes
/// 41 seconds", "8 hours 2 minutes".
///
/// Every unit is named and hours are their own step: this is the only
/// positional feedback a screen-reader user gets, and an audiobook read
/// as "482 minutes 13" is not feedback.
String spellDuration(Duration d) {
  final total = d.inSeconds.abs();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;

  String unit(int value, String singular) =>
      '$value $singular${value == 1 ? '' : 's'}';

  if (hours > 0) {
    // Seconds are noise at this scale, and a screen reader reads every
    // word of them.
    return minutes == 0
        ? unit(hours, 'hour')
        : '${unit(hours, 'hour')} ${unit(minutes, 'minute')}';
  }
  if (minutes == 0) return unit(seconds, 'second');
  if (seconds == 0) return unit(minutes, 'minute');
  return '${unit(minutes, 'minute')} ${unit(seconds, 'second')}';
}
