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
