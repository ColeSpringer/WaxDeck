/// One node of the media browse tree that Android Auto (and any other
/// media browser) renders. Ids are opaque to the OS; playable leaves
/// carry the item pid as their id.
class BrowseEntry {
  const BrowseEntry({
    required this.id,
    required this.title,
    this.subtitle,
    this.playable = false,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// Playable leaves start playback when tapped; everything else opens
  /// as a folder.
  final bool playable;
}

/// The root id media browsers start from.
const browseRootId = 'root';

/// Supplies browse-tree children. The app feeds this purely from the
/// local mirror, so the tree works identically offline.
abstract interface class BrowseSourcePort {
  Future<List<BrowseEntry>> children(String parentId);
}

/// One thing an OS media surface names: what is playing now on the lock
/// screen, MPRIS, the Windows transport controls and macOS's now-playing
/// panel, or one row of the queue a head unit renders as up-next.
///
/// A plain view-data struct rather than the app's `ItemSummary`, for the
/// same reason the design system takes one: this package knows nothing
/// about the catalog, and everything here is what an OS surface can
/// actually draw.
class MediaSessionItem {
  const MediaSessionItem({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.artUri,
    this.live = false,
  });

  /// The item pid. Opaque to the OS, which round-trips it back on a
  /// browse-tree play.
  final String id;

  final String title;
  final String? artist;
  final String? album;

  /// Absent for a live stream, and for an item whose length is not known
  /// until it loads.
  final Duration? duration;

  /// Where the OS fetches the cover. A local file on native, because the
  /// surfaces fetch it themselves and carry no credential of the app's;
  /// the server URL on web, where the browser attaches its own cookie.
  final Uri? artUri;

  /// A station: no length, no seeking, and nothing to step to.
  final bool live;
}

/// One extra button on the OS media notification, beside the transport.
///
/// Raised for as long as it means something and dropped after: the
/// sleep timer's fade is the case this exists for, where a listener in
/// bed should be able to extend without unlocking the phone.
class MediaSessionExtra {
  const MediaSessionExtra({
    required this.action,
    required this.label,
    required this.onPressed,
  });

  /// The platform action name. Stable, because the OS round-trips it
  /// back rather than the label.
  final String action;

  /// What the button says.
  final String label;

  final void Function() onPressed;
}

/// The app's handle on the OS media session: what it says is playing,
/// what it offers to skip to, and its one extra control.
abstract interface class MediaSessionPort {
  /// Names what this device is playing, or clears it when the device is
  /// playing nothing of its own - an empty queue, or a session handed to
  /// another endpoint, where a lock screen still offering a transport
  /// would be offering one over silence.
  void publish(MediaSessionItem? item);

  /// The queue a head unit renders as a list, and which row of it is
  /// playing. Empty for media that does not queue.
  void publishQueue(List<MediaSessionItem> items, {int index = 0});

  /// Moves the highlight within the queue already published. Separate
  /// from [publishQueue] because a track advance changes only this, and
  /// the alternative is five hundred rows over a channel per track.
  void publishQueueIndex(int index);

  /// Raises [extra] on the notification, or clears it when null.
  ///
  /// One control at a time: a notification has room for one button past
  /// the transport, and a queue of them would appear in an order nobody
  /// chose.
  void showExtra(MediaSessionExtra? extra);
}

/// The app's standing reference to the media session, bound once the
/// platform has one.
///
/// A holder rather than a provider override because the session is
/// registered after the container is built (it needs the local mirror),
/// and because most platforms never register one at all: the callers
/// raise their control unconditionally and this absorbs the difference.
class MediaSessionHandle implements MediaSessionPort {
  MediaSessionPort? _port;
  MediaSessionExtra? _pendingExtra;
  MediaSessionItem? _pendingItem;
  List<MediaSessionItem> _pendingQueue = const <MediaSessionItem>[];
  int _pendingIndex = 0;

  /// Set once the platform has answered that there will be no session.
  bool _hopeless = false;

  /// Whether anything published here can still reach a platform. False
  /// once registration has failed, so callers stop building a queue
  /// nothing can read.
  bool get live => !_hopeless;

  /// Says the platform will never bind.
  void unavailable() {
    _hopeless = true;
    _pendingItem = null;
    _pendingQueue = const <MediaSessionItem>[];
    _pendingExtra = null;
  }

  /// Points this at the platform's session. Anything published before the
  /// session existed is applied now rather than lost: registration is a
  /// platform round trip and the app is already playing by the time it
  /// lands on a launch that restored a queue.
  void bind(MediaSessionPort port) {
    _hopeless = false;
    _port = port;
    port
      ..publish(_pendingItem)
      ..publishQueue(_pendingQueue, index: _pendingIndex)
      ..showExtra(_pendingExtra);
  }

  @override
  void publish(MediaSessionItem? item) {
    if (_hopeless) return;
    _pendingItem = item;
    _port?.publish(item);
  }

  @override
  void publishQueue(List<MediaSessionItem> items, {int index = 0}) {
    if (_hopeless) return;
    _pendingQueue = items;
    _pendingIndex = index;
    _port?.publishQueue(items, index: index);
  }

  @override
  void publishQueueIndex(int index) {
    if (_hopeless) return;
    _pendingIndex = index;
    _port?.publishQueueIndex(index);
  }

  @override
  void showExtra(MediaSessionExtra? extra) {
    if (_hopeless) return;
    _pendingExtra = extra;
    _port?.showExtra(extra);
  }
}
