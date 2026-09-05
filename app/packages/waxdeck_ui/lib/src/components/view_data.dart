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
/// is the only thing that knows how a URL becomes bytes - which stored
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
    this.trailingSpoken,
    this.trailingDetail,
    this.trailingDetailSpoken,
    this.trailingDetailSemanticsId,
    this.badge,
    this.starred = false,
    this.downloaded = false,
    this.unplayed = false,
    this.unavailableOffline = false,
    this.semanticsId,
    this.tooltip,
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
  /// in mono by the components that show it, and clamped to one line -
  /// the components reserve one line for it.
  final String? trailingText;

  /// What a screen reader hears in place of [trailingText], where the
  /// drawn form is abbreviated for the room it has. "6 hr" is the right
  /// caption and the wrong thing to read aloud; `WaxLocalizations`'s
  /// `spellDuration` is what belongs here. Defaults to the drawn text.
  final String? trailingSpoken;

  /// A second right-aligned readout beside [trailingText]: a play count
  /// on an album row is the one so far. A bare number carries nothing
  /// aloud, so [trailingDetailSpoken] words it, and it is announced as
  /// its own node rather than folded into the row's name - the row's
  /// label excludes everything under it, which is what keeps a control
  /// inside a row reachable.
  ///
  /// Rows only. A card has no trailing column to put it in, so
  /// [MediaCard] ignores this and the same view data drawn as a grid
  /// tile is the row without its detail, not a tile with one somewhere
  /// else.
  final String? trailingDetail;

  /// What a screen reader hears in place of [trailingDetail]. Defaults
  /// to the drawn text, which for a bare count is a number on its own.
  final String? trailingDetailSpoken;

  /// The identifier the detail's own node carries, for the surfaces the
  /// e2e suite reads a count off.
  final String? trailingDetailSemanticsId;

  /// A word over the artwork naming what kind of thing this is, where the
  /// kind changes what the item does rather than only what it holds: a
  /// smart playlist evaluates itself, so it takes no reorder and no
  /// removal. One or two words, and only where a caption would be read
  /// too late - it is announced with the title rather than after it.
  final String? badge;

  final bool starred;
  final bool downloaded;

  /// Never played to the medium's threshold: a dot before the title, the
  /// mark every podcast client uses for "you have not heard this". It is
  /// a state of its own rather than the absence of [progress], which an
  /// episode started and abandoned also has.
  final bool unplayed;

  /// Dimmed and answered with an explanation rather than dying silently
  /// when tapped offline.
  final bool unavailableOffline;

  /// The stable identifier the e2e suite drives this control by. Every
  /// component that can be an e2e touchpoint takes one and applies
  /// `Semantics(identifier:)` itself.
  final String? semanticsId;

  /// The full text a hover reveals, for tiles whose lines truncate: a
  /// card clamps its title to two lines and its caption to one, and the
  /// tooltip is where the rest of a long name goes. Null shows none.
  final String? tooltip;
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
    this.songSaved = false,
    this.shuffled = false,
    this.repeat = WaxRepeat.off,
    this.remoteEndpoint,
    this.volume,
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

  /// Whether the announcement a live stream is playing has been kept, so
  /// the heart draws filled. Separate from [starred]: that is per-item
  /// state, and a station has no item to hold any.
  final bool songSaved;

  /// The queue's standing modes, so the two controls that cycle them can
  /// show which state they are in. Radio draws neither.
  final bool shuffled;
  final WaxRepeat repeat;

  /// Set when playback is being controlled on another endpoint: the bar
  /// says so rather than pretending the sound is local.
  final String? remoteEndpoint;

  /// The output level, 0 to 1, when there is one this surface should
  /// offer. Null hides the slider, and hiding it is the ordinary case
  /// rather than the exception: the layout system gives the bar a volume
  /// control under two conditions and only two - local output on desktop
  /// and web, and a remote endpoint that reports it can be turned down.
  /// A phone controlling its own playback has hardware buttons and an OS
  /// volume stack that a software slider only fights, so it gets none,
  /// and the caller is the only thing that knows which case it is in.
  final double? volume;

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
