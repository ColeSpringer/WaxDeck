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

/// The app's handle on the OS media session's extra control.
///
/// One control at a time: a notification has room for one button past
/// the transport, and a queue of them would appear in an order nobody
/// chose.
abstract interface class MediaSessionPort {
  /// Raises [extra] on the notification, or clears it when null.
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
  MediaSessionExtra? _pending;

  /// Points this at the platform's session. Anything raised before the
  /// session existed is applied now rather than lost.
  void bind(MediaSessionPort port) {
    _port = port;
    port.showExtra(_pending);
  }

  @override
  void showExtra(MediaSessionExtra? extra) {
    _pending = extra;
    _port?.showExtra(extra);
  }
}
